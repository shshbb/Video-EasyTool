import Foundation

protocol TranscriptionService {
    func transcribe(videoPath: String, model: String) async throws -> [SubtitleCue]
}

final class OpenAICompatibleTranscriber: TranscriptionService {
    private let client: OpenAICompatibleClient

    init(client: OpenAICompatibleClient) {
        self.client = client
    }

    func transcribe(videoPath: String, model: String) async throws -> [SubtitleCue] {
        let url = URL(fileURLWithPath: videoPath)
        let audioData = try Data(contentsOf: url)

        var form = MultipartFormData()
        form.addText(name: "model", value: model)
        form.addText(name: "response_format", value: "verbose_json")
        form.addText(name: "timestamp_granularities[]", value: "segment")
        form.addFile(name: "file", filename: url.lastPathComponent, mimeType: "video/mp4", data: audioData)

        let data = try await client.postMultipart(path: "v1/audio/transcriptions", formData: form)
        return try parseVerboseJSON(data: data)
    }

    private func parseVerboseJSON(data: Data) throws -> [SubtitleCue] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let segments = root["segments"] as? [[String: Any]]
        else {
            throw AppError.parseFailed("转录 JSON 不包含 segments")
        }

        var cues: [SubtitleCue] = []
        for (index, segment) in segments.enumerated() {
            guard
                let start = segment["start"] as? Double,
                let end = segment["end"] as? Double,
                let text = segment["text"] as? String
            else {
                continue
            }
            cues.append(SubtitleCue(id: index + 1, start: start, end: end, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return cues
    }
}
