import Foundation

struct LocalWhisperTranscriber {
    func transcribe(
        videoPath: String,
        modelPath: String,
        outputSRTPath: String,
        onOutput: ((String) -> Void)? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onProcessStart: ((Process) -> Void)? = nil
    ) async throws {
        let mediaDuration = try? await probeDuration(inputPath: videoPath)

        let tempWavPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisper-audio-\(UUID().uuidString).wav")
            .path
        defer {
            try? FileManager.default.removeItem(atPath: tempWavPath)
        }

        // Convert video/audio input to PCM WAV, which whisper.cpp reliably accepts.
        _ = try await ProcessRunner.run(
            "ffmpeg",
            args: [
                "-y",
                "-nostdin",
                "-i", videoPath,
                "-vn",
                "-ac", "1",
                "-ar", "16000",
                "-f", "wav",
                "-progress", "pipe:1",
                "-nostats",
                tempWavPath
            ],
            onOutput: { chunk in
                onOutput?(chunk)
                if let duration = mediaDuration,
                   let p = parseFFmpegProgress(chunk: chunk, duration: duration) {
                    onProgress?(min(max(p * 0.35, 0), 0.35))
                }
            },
            onProcessStart: onProcessStart
        )

        let prefix = URL(fileURLWithPath: outputSRTPath).deletingPathExtension().path

        let whisperOutput = try await ProcessRunner.run(
            "whisper-cli",
            args: [
                "-m", modelPath,
                "-f", tempWavPath,
                "-osrt",
                "-of", prefix
            ],
            onOutput: { chunk in
                onOutput?(chunk)
                if let progress = parsePercent(from: chunk) {
                    onProgress?(0.35 + progress * 0.65)
                }
            },
            onProcessStart: onProcessStart
        )

        if whisperOutput.contains("failed to read audio") || whisperOutput.contains("failed to open audio") {
            throw AppError.ioFailed("Whisper 无法读取音频输入，请检查 ffmpeg 是否可用以及源视频是否损坏。")
        }

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
}
