import Foundation

struct DownloadResult {
    let videoPath: String
    let title: String
}

struct YouTubeDownloader {
    func download(
        url: String,
        outputDirectory: String,
        tempDirectory: String? = nil,
        onOutput: ((String) -> Void)? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onProcessStart: ((Process) -> Void)? = nil
    ) async throws -> DownloadResult {
        try ProcessRunner.requireTool("yt-dlp")
        try ProcessRunner.requireTool("ffmpeg")

        let outputTemplate = "\(outputDirectory)/%(title)s.%(ext)s"
        var args: [String] = [
            "-f", "bv*+ba/b",
            "--newline",
            "--merge-output-format", "mp4",
            "-o", outputTemplate
        ]
        if let tempDirectory {
            args.append(contentsOf: ["-P", "temp:\(tempDirectory)"])
        }
        args.append(url)

        let runOutput = try await ProcessRunner.run(
            "yt-dlp",
            args: args,
            onOutput: { chunk in
                onOutput?(chunk)
                if let progress = parsePercent(from: chunk) {
                    onProgress?(progress)
                }
            },
            onProcessStart: onProcessStart
        )

        if let mergedPath = parseMergedOutputPath(from: runOutput),
           FileManager.default.fileExists(atPath: mergedPath) {
            cleanupIntermediateFiles(finalPath: mergedPath)
            let title = URL(fileURLWithPath: mergedPath).deletingPathExtension().lastPathComponent
            return DownloadResult(videoPath: mergedPath, title: title)
        }

        if let latestPath = latestVideoFile(in: outputDirectory) {
            cleanupIntermediateFiles(finalPath: latestPath)
            let title = URL(fileURLWithPath: latestPath).deletingPathExtension().lastPathComponent
            return DownloadResult(videoPath: latestPath, title: title)
        }

        throw AppError.ioFailed("下载已完成，但未能定位输出视频文件。请检查目录: \(outputDirectory)")
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

    private func parseMergedOutputPath(from text: String) -> String? {
        let pattern = #"\[Merger\]\s+Merging formats into\s+"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let pathRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[pathRange])
    }

    private func latestVideoFile(in directory: String) -> String? {
        let videoExts = Set(["mp4", "mkv", "webm", "mov", "m4v"])
        let preferredOrder = ["mp4", "mkv", "mov", "m4v", "webm"]
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = items.filter { url in
            videoExts.contains(url.pathExtension.lowercased())
        }

        let sorted = candidates.sorted { lhs, rhs in
            let lExt = lhs.pathExtension.lowercased()
            let rExt = rhs.pathExtension.lowercased()
            let lRank = preferredOrder.firstIndex(of: lExt) ?? preferredOrder.count
            let rRank = preferredOrder.firstIndex(of: rExt) ?? preferredOrder.count
            if lRank != rRank {
                return lRank < rRank
            }
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }
        return sorted.first?.path
    }

    private func cleanupIntermediateFiles(finalPath: String) {
        let finalURL = URL(fileURLWithPath: finalPath)
        let directory = finalURL.deletingLastPathComponent()
        let baseName = finalURL.deletingPathExtension().lastPathComponent
        let finalFilename = finalURL.lastPathComponent

        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for item in items {
            let filename = item.lastPathComponent
            guard filename != finalFilename else { continue }
            guard item.deletingPathExtension().lastPathComponent == baseName else { continue }

            let ext = item.pathExtension.lowercased()
            if ["webm", "m4a", "mp3", "opus", "part", "temp"].contains(ext) || filename.contains(".f") {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}
