import Foundation

struct LocalWhisperTranscriber {
    private let subtitleService = SubtitleService()
    private let chunkDurationSeconds: Int = 480
    private let chunkIdleTimeoutSeconds: TimeInterval = 180

    func transcribe(
        videoPath: String,
        modelPath: String,
        outputSRTPath: String,
        onOutput: ((String) -> Void)? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onProcessStart: ((Process) -> Void)? = nil
    ) async throws {
        let mediaDuration = try await probeDuration(inputPath: videoPath)
        let workingDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisper-chunks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: workingDirectory)
        }

        let chunkPattern = workingDirectory.appendingPathComponent("chunk-%03d.wav").path

        _ = try await ProcessRunner.run(
            "ffmpeg",
            args: [
                "-y",
                "-nostdin",
                "-i", videoPath,
                "-vn",
                "-ac", "1",
                "-ar", "16000",
                "-c:a", "pcm_s16le",
                "-f", "segment",
                "-segment_time", "\(chunkDurationSeconds)",
                "-reset_timestamps", "1",
                "-progress", "pipe:1",
                "-nostats",
                chunkPattern
            ],
            onOutput: { chunk in
                onOutput?(chunk)
                if let p = parseFFmpegProgress(chunk: chunk, duration: mediaDuration) {
                    onProgress?(min(max(p * 0.20, 0), 0.20))
                }
            },
            onProcessStart: onProcessStart
        )

        let chunkURLs = try chunkFiles(in: workingDirectory)
        guard !chunkURLs.isEmpty else {
            throw AppError.ioFailed("未能生成用于本地转录的音频分段。")
        }

        var mergedCues: [SubtitleCue] = []
        var skippedChunks = 0
        onOutput?("\n[INFO] 已切分音频: \(chunkURLs.count) 段，每段约 \(chunkDurationSeconds / 60) 分钟\n")

        for (index, chunkURL) in chunkURLs.enumerated() {
            let chunkNumber = index + 1
            onOutput?(
                "\n[INFO] 开始转录分段 \(chunkNumber)/\(chunkURLs.count): \(chunkURL.lastPathComponent)\n"
            )

            let prefix = workingDirectory.appendingPathComponent("chunk-\(String(format: "%03d", index))").path
            let chunkSRTPath = prefix + ".srt"
            var lastLoggedPercent = -1
            let monitor = ChunkActivityMonitor()

            do {
                let whisperOutput = try await withChunkWatchdog(monitor: monitor, onOutput: onOutput) {
                    try await ProcessRunner.run(
                        "whisper-cli",
                        args: [
                            "-m", modelPath,
                            "-f", chunkURL.path,
                            "-mc", "0",
                            "-ml", "120",
                            "-sow",
                            "-sns",
                            "-pp",
                            "-osrt",
                            "-of", prefix
                        ],
                        onOutput: { chunk in
                            monitor.noteActivity()
                            onOutput?(chunk)
                            if let progress = parsePercent(from: chunk) {
                                let chunkPercent = Int((progress * 100).rounded())
                                if chunkPercent >= 0, chunkPercent != lastLoggedPercent, chunkPercent % 10 == 0 {
                                    lastLoggedPercent = chunkPercent
                                    onOutput?("[INFO] 分段进度 \(chunkNumber)/\(chunkURLs.count): \(chunkPercent)%\n")
                                }
                                let chunkBase = Double(index) / Double(chunkURLs.count)
                                let chunkWeight = 1.0 / Double(chunkURLs.count)
                                let total = 0.20 + (chunkBase + progress * chunkWeight) * 0.80
                                onProgress?(min(max(total, 0), 1))
                            }
                        },
                        onProcessStart: { process in
                            monitor.setProcess(process)
                            onProcessStart?(process)
                        }
                    )
                }

                if whisperOutput.contains("failed to read audio") || whisperOutput.contains("failed to open audio") {
                    throw AppError.ioFailed("Whisper 无法读取音频输入，请检查 ffmpeg 是否可用以及源视频是否损坏。")
                }

                guard FileManager.default.fileExists(atPath: chunkSRTPath) else {
                    throw AppError.ioFailed("本地 Whisper 转录完成，但未找到分段字幕: \(chunkSRTPath)")
                }

                let chunkCues = try subtitleService.parseSRT(path: chunkSRTPath)
                let chunkOffset = TimeInterval(index * chunkDurationSeconds)
                mergedCues.append(contentsOf: shiftCues(chunkCues, by: chunkOffset, startingAt: mergedCues.count + 1))
                onOutput?("[INFO] 分段完成 \(chunkNumber)/\(chunkURLs.count): 生成 \(chunkCues.count) 条字幕\n")
            } catch {
                skippedChunks += 1
                if monitor.didTimeout {
                    onOutput?("[WARN] 分段 \(chunkNumber)/\(chunkURLs.count) 长时间无输出，已强制终止并跳过。\n")
                } else {
                    onOutput?("[WARN] 分段 \(chunkNumber)/\(chunkURLs.count) 转录失败，已跳过。原因: \(error.localizedDescription)\n")
                }
                continue
            }
        }

        guard !mergedCues.isEmpty else {
            throw AppError.ioFailed("所有音频分段都未成功转录。")
        }

        if skippedChunks > 0 {
            onOutput?("[WARN] 已跳过 \(skippedChunks) 个异常分段，最终字幕可能缺少对应内容。\n")
        }

        try subtitleService.writeSRT(cues: mergedCues, to: outputSRTPath)

        guard FileManager.default.fileExists(atPath: outputSRTPath) else {
            throw AppError.ioFailed("本地 Whisper 转录完成，但未找到输出字幕: \(outputSRTPath)")
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
            throw AppError.parseFailed("无法获取输入媒体时长")
        }
        return duration
    }

    private func parseFFmpegProgress(chunk: String, duration: Double) -> Double? {
        let lines = chunk.split(separator: "\n")
        for raw in lines {
            let line = String(raw)
            if line.hasPrefix("out_time_ms=") {
                let value = line.replacingOccurrences(of: "out_time_ms=", with: "")
                if let ms = Double(value), duration > 0 {
                    return min(max((ms / 1_000_000.0) / duration, 0), 1)
                }
            }
            if line == "progress=end" {
                return 1
            }
        }
        return nil
    }

    private func parsePercent(from text: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Double(text[valueRange]) else {
            return nil
        }
        return min(max(value / 100.0, 0), 1)
    }

    private func chunkFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "wav" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func shiftCues(_ cues: [SubtitleCue], by offset: TimeInterval, startingAt startID: Int) -> [SubtitleCue] {
        cues.enumerated().map { index, cue in
            SubtitleCue(
                id: startID + index,
                start: cue.start + offset,
                end: cue.end + offset,
                text: cue.text
            )
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func withChunkWatchdog<T>(
        monitor: ChunkActivityMonitor,
        onOutput: ((String) -> Void)?,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let watchdog = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let stalledProcess = monitor.processIfStalled(idleTimeout: chunkIdleTimeoutSeconds) {
                    onOutput?("[WARN] 当前分段超过 \(Int(chunkIdleTimeoutSeconds)) 秒无新输出，正在终止该分段...\n")
                    ProcessRunner.terminateProcessTree(stalledProcess)
                    break
                }
            }
        }

        defer { watchdog.cancel() }
        return try await operation()
    }
}

private final class ChunkActivityMonitor {
    private let lock = NSLock()
    private var lastActivity = Date()
    private var process: Process?
    private(set) var didTimeout = false

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

        guard !didTimeout,
              let process,
              process.isRunning,
              Date().timeIntervalSince(lastActivity) > idleTimeout else {
            return nil
        }

        didTimeout = true
        return process
    }
}
