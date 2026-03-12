import Foundation
import Darwin

struct ProcessRunner {
    static func requireTool(_ tool: String) throws {
        _ = try findTool(tool)
    }

    static func run(
        _ launchPath: String,
        args: [String],
        onOutput: ((String) -> Void)? = nil,
        onProcessStart: ((Process) -> Void)? = nil
    ) async throws -> String {
        let executable = try findTool(launchPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        async let stdoutTask = streamOutput(from: stdout.fileHandleForReading, onOutput: onOutput)
        async let stderrTask = streamOutput(from: stderr.fileHandleForReading, onOutput: onOutput)

        try process.run()
        onProcessStart?(process)

        let status = await withTaskCancellationHandler(operation: {
            await Task.detached(priority: .utility) {
                process.waitUntilExit()
                return process.terminationStatus
            }.value
        }, onCancel: {
            terminateProcessTree(process)
        })

        let output = await stdoutTask
        let error = await stderrTask

        guard status == 0 else {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw AppError.processFailed("\(launchPath) exited with \(status): \(error)")
        }

        return output.isEmpty ? error : output
    }

    private static func streamOutput(from handle: FileHandle, onOutput: ((String) -> Void)?) async -> String {
        await Task.detached(priority: .utility) {
            var collected = ""
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                let text = String(decoding: data, as: UTF8.self)
                collected += text
                onOutput?(text)
            }
            return collected
        }.value
    }

    private static func findTool(_ tool: String) throws -> String {
        if tool.contains("/") {
            if FileManager.default.isExecutableFile(atPath: tool) {
                return tool
            }
            throw AppError.toolNotFound(tool)
        }

        for path in toolSearchPaths() {
            let candidate = "\(path)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw AppError.toolNotFound(tool)
    }

    static func terminateProcessTree(_ process: Process) {
        terminateProcessTree(pid: process.processIdentifier)
    }

    static func terminateProcessTree(pid: Int32) {
        guard pid > 0 else { return }

        for child in childPIDs(of: pid) {
            terminateProcessTree(pid: child)
        }

        _ = kill(pid, SIGTERM)
        usleep(250_000)
        if kill(pid, 0) == 0 {
            _ = kill(pid, SIGKILL)
        }
    }

    private static func childPIDs(of pid: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(pid)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func toolSearchPaths() -> [String] {
        var paths: [String] = []

        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: envPath.split(separator: ":").map(String.init))
        }

        paths.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])

        var seen = Set<String>()
        return paths.filter { path in
            guard !path.isEmpty, !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}
