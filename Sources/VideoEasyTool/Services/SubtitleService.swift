import Foundation

struct SubtitleService {
    func writeSRT(cues: [SubtitleCue], to path: String) throws {
        let content = cues.map { cue in
            """
            \(cue.id)
            \(format(cue.start)) --> \(format(cue.end))
            \(cue.text)
            """
        }.joined(separator: "\n\n") + "\n"

        try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    func parseSRT(path: String) throws -> [SubtitleCue] {
        let raw = try String(contentsOfFile: path, encoding: .utf8)
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            guard lines.count >= 3 else { continue }
            guard let id = Int(lines[0].trimmingCharacters(in: .whitespaces)) else { continue }

            let timeLine = lines[1]
            let timeParts = timeLine.components(separatedBy: " --> ")
            guard timeParts.count == 2 else { continue }

            guard let start = parseTime(timeParts[0]), let end = parseTime(timeParts[1]) else { continue }

            let text = lines.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(SubtitleCue(id: id, start: start, end: end, text: text))
        }

        if cues.isEmpty {
            throw AppError.parseFailed("SRT 文件为空或格式无法解析")
        }

        return cues.sorted { $0.id < $1.id }
    }

    func buildBilingualCues(original: [SubtitleCue], translatedTexts: [String]) throws -> [SubtitleCue] {
        guard original.count == translatedTexts.count else {
            throw AppError.parseFailed("原文和译文数量不一致")
        }

        return zip(original, translatedTexts).map { cue, translated in
            SubtitleCue(
                id: cue.id,
                start: cue.start,
                end: cue.end,
                text: "\(cue.text)\n\(translated)"
            )
        }
    }

    func cleanTranscriptionCues(_ cues: [SubtitleCue]) -> (cleaned: [SubtitleCue], removedCount: Int) {
        let sorted = cues.sorted {
            if $0.start == $1.start { return $0.id < $1.id }
            return $0.start < $1.start
        }

        var compacted: [SubtitleCue] = []
        compacted.reserveCapacity(sorted.count)

        for cue in sorted {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            let normalized = normalizeTextForCompare(text)
            let start = cue.start
            let end = max(cue.end, cue.start + 0.02)
            let duration = max(cue.end - cue.start, 0)

            if let last = compacted.last {
                let lastNormalized = normalizeTextForCompare(last.text)
                let sameText = normalized == lastNormalized
                let timeNear = start <= last.end + 0.20
                let sameStart = abs(start - last.start) <= 0.12
                let currentZeroLike = duration <= 0.08
                let lastZeroLike = (last.end - last.start) <= 0.08

                if sameText && (timeNear || sameStart) && (currentZeroLike || lastZeroLike || sameStart) {
                    let merged = SubtitleCue(
                        id: last.id,
                        start: min(last.start, start),
                        end: max(last.end, end),
                        text: last.text
                    )
                    compacted[compacted.count - 1] = merged
                    continue
                }
            }

            compacted.append(SubtitleCue(id: cue.id, start: start, end: end, text: text))
        }

        var cleaned: [SubtitleCue] = []
        cleaned.reserveCapacity(compacted.count)
        var lastEnd: TimeInterval = 0
        let minDuration: TimeInterval = 0.08

        for (index, cue) in compacted.enumerated() {
            let nextStart = (index + 1 < compacted.count) ? compacted[index + 1].start : nil
            let start = max(cue.start, lastEnd)
            var end = max(cue.end, start + minDuration)

            if let nextStart, end > nextStart {
                end = max(start + minDuration, min(end, nextStart))
            }
            if end <= start {
                end = start + minDuration
            }

            cleaned.append(SubtitleCue(id: cleaned.count + 1, start: start, end: end, text: cue.text))
            lastEnd = end
        }

        let removed = max(cues.count - cleaned.count, 0)
        return (cleaned, removed)
    }

    private func parseTime(_ value: String) -> TimeInterval? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = clean.components(separatedBy: [":", ","])
        guard parts.count == 4,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]),
              let ms = Double(parts[3]) else {
            return nil
        }
        return h * 3600 + m * 60 + s + ms / 1000.0
    }

    private func format(_ time: TimeInterval) -> String {
        let totalMillis = Int((time * 1000.0).rounded())
        let millis = totalMillis % 1000
        let totalSeconds = totalMillis / 1000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private func normalizeTextForCompare(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
