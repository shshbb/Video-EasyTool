import Foundation

struct VideoTranscoder {
    private let idleTimeoutSeconds: TimeInterval = 180

    func transcode(
        inputPath: String,
        outputPath: String,
        format: String,
        crf: Int,
        clipStartTime: TimeInterval? = nil,
        clipEndTime: TimeInterval? = nil,
        onOutput: ((String) -> Void)? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onProcessStart: ((Process) -> Void)? = nil
    ) async throws {
        let duration = try await probeDuration(inputPath: inputPath)
        let monitor = FFmpegActivityMonitor()

        var args = [
            "-y",
            "-nostdin",
        ]

        if let clipStartTime {
            args.append(contentsOf: ["-ss", formatTime(clipStartTime)])
        }
        if let clipEndTime {
            args.append(contentsOf: ["-to", formatTime(clipEndTime)])
        }

        args.append(contentsOf: [
            "-i", inputPath,
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", String(crf)
        ])

        if format == "webm" {
            args.append(contentsOf: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", String(max(crf, 30)), "-c:a", "libopus"])
        } else {
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "192k"])
        }

        args.append(contentsOf: ["-progress", "pipe:1", "-stats_period", "1", "-nostats", outputPath])

        _ = try await withFFmpegWatchdog(monitor: monitor, onOutput: onOutput) {
            try await ProcessRunner.run(
                "ffmpeg",
                args: args,
                onOutput: { chunk in
                    monitor.noteActivity()
                    onOutput?(chunk)
                    if let progress = parseProgress(
                        chunk: chunk,
                        duration: effectiveDuration(totalDuration: duration, clipStartTime: clipStartTime, clipEndTime: clipEndTime)
                    ) {
                        onProgress?(progress)
                    }
                },
                onProcessStart: { process in
                    monitor.setProcess(process)
                    onProcessStart?(process)
                }
            )
        }
    }

    private func probeDuration(inputPath: String) async throws -> Double {
        let out = try await ProcessRunner.run(
            "ffprobe",
            args: [
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                inputPath
            ]
        )

        guard let duration = Double(out.trimmingCharacters(in: .whitespacesAndNewlines)), duration > 0 else {
            throw AppError.parseFailed("无法获取视频时长")
        }
        return duration
    }

    private func parseProgress(chunk: String, duration: Double) -> Double? {
        let lines = chunk.split(separator: "\n")
        var latestProgress: Double?
        for lineSub in lines {
            let line = String(lineSub)
            if line == "progress=end" {
                return 1
            }
            if line.hasPrefix("out_time_ms=") {
                let value = line.replacingOccurrences(of: "out_time_ms=", with: "")
                if let ms = Double(value), duration > 0 {
                    latestProgress = min(max((ms / 1_000_000.0) / duration, 0), 1)
                }
            }
        }
        return latestProgress
    }

    private func effectiveDuration(totalDuration: Double, clipStartTime: TimeInterval?, clipEndTime: TimeInterval?) -> Double {
        guard clipStartTime != nil || clipEndTime != nil else { return totalDuration }
        let start = max(clipStartTime ?? 0, 0)
        let end = min(clipEndTime ?? totalDuration, totalDuration)
        return max(end - start, 0.1)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let totalMilliseconds = Int((value * 1000).rounded())
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    private func withFFmpegWatchdog(
        monitor: FFmpegActivityMonitor,
        onOutput: ((String) -> Void)?,
        operation: @escaping () async throws -> String
    ) async throws -> String {
        let watchdog = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let stalled = monitor.processIfStalled(idleTimeout: idleTimeoutSeconds) {
                    onOutput?("[WARN] ffmpeg 超过 \(Int(idleTimeoutSeconds)) 秒无新输出，正在终止当前转码任务...\n")
                    ProcessRunner.terminateProcessTree(stalled)
                    break
                }
            }
        }

        defer { watchdog.cancel() }
        return try await operation()
    }
}

private final class FFmpegActivityMonitor {
    private let lock = NSLock()
    private var lastActivity = Date()
    private var process: Process?

    func noteActivity() {
        lock.lock()
        lastActivity = Date()
        lock.unlock()
    }

    func setProcess(_ process: Process) {
        lock.lock()
        self.process = process
        lastActivity = Date()
        lock.unlock()
    }

    func processIfStalled(idleTimeout: TimeInterval) -> Process? {
        lock.lock()
        defer { lock.unlock() }

        guard let process,
              process.isRunning,
              Date().timeIntervalSince(lastActivity) > idleTimeout else {
            return nil
        }

        return process
    }
}
