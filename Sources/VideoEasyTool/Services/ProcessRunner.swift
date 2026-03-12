import Foundation

struct ProcessRunner {
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
            if process.isRunning {
                process.terminate()
            }
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

        let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for path in searchPaths {
            let candidate = "\(path)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw AppError.toolNotFound(tool)
    }
}
