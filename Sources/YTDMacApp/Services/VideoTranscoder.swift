import Foundation

struct VideoTranscoder {
    func transcode(
        inputPath: String,
        outputPath: String,
        format: String,
        crf: Int,
        onOutput: ((String) -> Void)? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onProcessStart: ((Process) -> Void)? = nil
    ) async throws {
        let duration = try await probeDuration(inputPath: inputPath)

        var args = [
            "-y",
            "-i", inputPath,
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", String(crf)
        ]

        if format == "webm" {
            args.append(contentsOf: ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", String(max(crf, 30)), "-c:a", "libopus"])
        } else {
            args.append(contentsOf: ["-c:a", "aac", "-b:a", "192k"])
        }

        args.append(contentsOf: ["-progress", "pipe:1", "-nostats", outputPath])

        _ = try await ProcessRunner.run(
            "ffmpeg",
            args: args,
            onOutput: { chunk in
                onOutput?(chunk)
                if let progress = parseProgress(chunk: chunk, duration: duration) {
                    onProgress?(progress)
                }
            },
            onProcessStart: onProcessStart
        )
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
        for lineSub in lines {
            let line = String(lineSub)
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
}
