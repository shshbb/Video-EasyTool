import Foundation

protocol TranslationService {
    func translateBatch(_ sourceTexts: [String], targetLanguage: String) async throws -> [String]
}

actor TranslationRateLimiter {
    private var nextAllowedTime: Date = .distantPast

    func wait(minInterval: TimeInterval) async {
        let now = Date()
        if now < nextAllowedTime {
            let delay = nextAllowedTime.timeIntervalSince(now)
            let nanos = UInt64(max(delay, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
        nextAllowedTime = Date().addingTimeInterval(minInterval)
    }

    func penalize(waitSeconds: TimeInterval) {
        let now = Date()
        let until = now.addingTimeInterval(max(waitSeconds, 0))
        if until > nextAllowedTime {
            nextAllowedTime = until
        }
    }
}

final class OpenAICompatibleTranslator: TranslationService {
    private let client: OpenAICompatibleClient
    private let model: String
    private let rateLimiter = TranslationRateLimiter()

    init(client: OpenAICompatibleClient, model: String) {
        self.client = client
        self.model = model
    }

    func translateBatch(_ sourceTexts: [String], targetLanguage: String) async throws -> [String] {
        if usesQwenMTProtocol {
            return try await translateBatchWithQwenMT(sourceTexts, targetLanguage: targetLanguage)
        }
        return try await translateBatchAdaptive(sourceTexts, targetLanguage: targetLanguage, depth: 0)
    }

    private var usesQwenMTProtocol: Bool {
        let m = model.lowercased()
        return m.contains("qwen-mt")
    }

    private func translateBatchWithQwenMT(_ sourceTexts: [String], targetLanguage: String) async throws -> [String] {
        if sourceTexts.isEmpty { return [] }
        let target = qwenMTLanguageName(targetLanguage)
        var results: [String] = []
        results.reserveCapacity(sourceTexts.count)

        for text in sourceTexts {
            let body: [String: Any] = [
                "model": model,
                "messages": [
                    ["role": "user", "content": text]
                ],
                "translation_options": [
                    "source_lang": "auto",
                    "target_lang": target
                ]
            ]
            let data = try await postWithRetry(body: body)
            var translated = try parseSingleTranslation(data: data)
            // If the model returns near-identical source text, retry once with explicit user prompt.
            if shouldRetryUntranslated(source: text, translated: translated, targetLanguage: targetLanguage) {
                let prompt = """
                你是字幕翻译助手。请把下面文本翻译成\(target)，只输出译文，不要解释，不要补充，不要保留原文：
                \(text)
                """
                let retryBody: [String: Any] = [
                    "model": model,
                    "messages": [
                        ["role": "user", "content": prompt]
                    ]
                ]
                let retryData = try await postWithRetry(body: retryBody)
                translated = try parseSingleTranslation(data: retryData)
            }
            results.append(translated)
        }
        return results
    }

    private func qwenMTLanguageName(_ code: String) -> String {
        let lower = code.lowercased()
        if lower.hasPrefix("zh") { return "Chinese" }
        if lower.hasPrefix("en") { return "English" }
        if lower.hasPrefix("ja") { return "Japanese" }
        if lower.hasPrefix("ko") { return "Korean" }
        if lower.hasPrefix("fr") { return "French" }
        if lower.hasPrefix("de") { return "German" }
        if lower.hasPrefix("es") { return "Spanish" }
        if lower.hasPrefix("vi") { return "Vietnamese" }
        return code
    }

    private func translateBatchAdaptive(_ sourceTexts: [String], targetLanguage: String, depth: Int) async throws -> [String] {
        if sourceTexts.isEmpty { return [] }
        if sourceTexts.count == 1 {
            return try await translateBatchOnce(sourceTexts, targetLanguage: targetLanguage)
        }

        let totalChars = sourceTexts.reduce(0) { $0 + $1.count }
        if totalChars > 3200 && depth < 6 {
            let mid = sourceTexts.count / 2
            let left = try await translateBatchAdaptive(Array(sourceTexts[..<mid]), targetLanguage: targetLanguage, depth: depth + 1)
            let right = try await translateBatchAdaptive(Array(sourceTexts[mid...]), targetLanguage: targetLanguage, depth: depth + 1)
            return left + right
        }

        do {
            return try await translateBatchOnce(sourceTexts, targetLanguage: targetLanguage)
        } catch {
            if isFormatMismatch(error) && sourceTexts.count > 1 && depth < 8 {
                let mid = sourceTexts.count / 2
                let left = try await translateBatchAdaptive(Array(sourceTexts[..<mid]), targetLanguage: targetLanguage, depth: depth + 1)
                let right = try await translateBatchAdaptive(Array(sourceTexts[mid...]), targetLanguage: targetLanguage, depth: depth + 1)
                return left + right
            }
            throw error
        }
    }

    private func translateBatchOnce(_ sourceTexts: [String], targetLanguage: String) async throws -> [String] {
        // Use compact row format to reduce tokens while preserving subtitle order context.
        let rows = sourceTexts.enumerated().map { ["i": $0.offset + 1, "t": $0.element.replacingOccurrences(of: "\n", with: " ")] }
        let inputData = try JSONSerialization.data(withJSONObject: rows)
        let inputBlock = String(decoding: inputData, as: UTF8.self)
        let prompt = """
        You are a precise subtitle translator.
        Keep names, code, and numbers unchanged.

        TL=\(targetLanguage)
        Task: subtitle translation with natural context across lines.
        Keep line count and order unchanged.
        Every item MUST be translated to TL unless it is already in TL.
        Return STRICT JSON only:
        {"items":[{"i":1,"t":"..."},{"i":2,"t":"..."}]}
        Do not add wrappers like "Translation:".
        No markdown, no explanations.
        Input:
        \(inputBlock)
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1
        ]

        let data = try await postWithRetry(body: body)
        return try parseOpenAIChatContent(data: data, expectedCount: sourceTexts.count)
    }

    private func postWithRetry(body: [String: Any]) async throws -> Data {
        let maxAttempts = 8
        var attempt = 0
        var backoff: TimeInterval = usesQwenMTProtocol ? 1.6 : 1.2
        let minInterval: TimeInterval = usesQwenMTProtocol ? 1.25 : 0.9

        while true {
            attempt += 1
            await rateLimiter.wait(minInterval: minInterval)
            do {
                return try await client.postJSON(path: "v1/chat/completions", json: body)
            } catch {
                if is429(error), let retryAfter = retryAfterSeconds(from: error) {
                    await rateLimiter.penalize(waitSeconds: retryAfter)
                } else if is429(error) {
                    let adaptivePenalty = min(pow(2.0, Double(attempt)) * 0.9, 45.0)
                    await rateLimiter.penalize(waitSeconds: adaptivePenalty)
                }

                guard attempt < maxAttempts, shouldRetry(error) else {
                    throw error
                }
                let jitter = Double.random(in: 0...0.6)
                let sleepSeconds = min(backoff + jitter, 30.0)
                let nanos = UInt64(sleepSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                backoff *= 1.9
            }
        }
    }

    private func shouldRetry(_ error: Error) -> Bool {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                break
            }
        }

        if let appErr = error as? AppError {
            switch appErr {
            case .invalidResponse(let detail):
                return detail.contains("status=429") || detail.contains("status=500") || detail.contains("status=502") || detail.contains("status=503") || detail.contains("status=504")
            default:
                break
            }
        }
        return false
    }

    private func is429(_ error: Error) -> Bool {
        guard let appErr = error as? AppError,
              case let .invalidResponse(detail) = appErr else {
            return false
        }
        return detail.contains("status=429")
    }

    private func retryAfterSeconds(from error: Error) -> TimeInterval? {
        guard let appErr = error as? AppError,
              case let .invalidResponse(detail) = appErr else {
            return nil
        }

        let patterns = [
            #"retry[_-]?after["']?\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)"#,
            #"try again in\s*([0-9]+(?:\.[0-9]+)?)\s*s"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(detail.startIndex..<detail.endIndex, in: detail)
            guard let match = regex.firstMatch(in: detail, options: [], range: range),
                  match.numberOfRanges > 1,
                  let numRange = Range(match.range(at: 1), in: detail) else {
                continue
            }
            let value = String(detail[numRange])
            if let seconds = Double(value), seconds > 0 {
                return min(seconds, 120)
            }
        }
        return nil
    }

    private func parseOpenAIChatContent(data: Data, expectedCount: Int) throws -> [String] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AppError.parseFailed("chat completion 格式不正确")
        }

        if let strict = parseStrictItemsJSON(content: content, expectedCount: expectedCount) {
            return strict
        }

        if expectedCount == 1 {
            let one = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !one.isEmpty {
                return [one]
            }
        }

        if let jsonData = content.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: jsonData) as? [String],
           array.count == expectedCount {
            return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let lines = content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var translations: [String] = []
        for line in lines {
            if let dot = line.firstIndex(of: ".") {
                let text = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { translations.append(text) }
            }
        }

        guard translations.count == expectedCount else {
            throw AppError.parseFailed("翻译条数不一致: got=\(translations.count), expected=\(expectedCount)")
        }
        return translations
    }

    private func parseSingleTranslation(data: Data) throws -> String {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AppError.parseFailed("翻译响应格式不正确")
        }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AppError.parseFailed("翻译响应为空")
        }
        return text
    }

    private func shouldRetryUntranslated(source: String, translated: String, targetLanguage: String) -> Bool {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let dst = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty, !dst.isEmpty else { return false }
        guard src.count >= 6 else { return false }
        guard src == dst else { return false }

        let target = targetLanguage.lowercased()
        if target.hasPrefix("zh"), containsCJK(dst) {
            return false
        }
        if target.hasPrefix("en"), containsMostlyLatin(dst) {
            return false
        }
        return true
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    private func containsMostlyLatin(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return false }
        let latin = scalars.filter {
            (0x0041...0x005A).contains($0.value) || (0x0061...0x007A).contains($0.value)
        }.count
        return Double(latin) / Double(scalars.count) >= 0.55
    }

    private func isFormatMismatch(_ error: Error) -> Bool {
        guard case let AppError.parseFailed(detail) = error else { return false }
        return detail.contains("条数不一致")
    }

    private func parseStrictItemsJSON(content: String, expectedCount: Int) -> [String]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = extractJSONData(from: trimmed),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else {
            return nil
        }

        let sorted = items.sorted { lhs, rhs in
            (lhs["i"] as? Int ?? 0) < (rhs["i"] as? Int ?? 0)
        }
        let texts = sorted.compactMap { $0["t"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return texts.count == expectedCount ? texts : nil
    }

    private func extractJSONData(from text: String) -> Data? {
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        let candidate = String(text[start...end])
        guard let data = candidate.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return data
    }
}

final class OllamaTranslator: TranslationService {
    private let baseURL: URL
    private let model: String
    private let session: URLSession

    init(baseURL: String, model: String) throws {
        guard let url = URL(string: baseURL) else {
            throw AppError.invalidResponse("Ollama baseURL 无效: \(baseURL)")
        }
        self.baseURL = url
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 1800
        config.timeoutIntervalForResource = 7200
        self.session = URLSession(configuration: config)
    }

    func translateBatch(_ sourceTexts: [String], targetLanguage: String) async throws -> [String] {
        try await translateBatchAdaptive(sourceTexts, targetLanguage: targetLanguage, depth: 0)
    }

    private func translateBatchAdaptive(_ sourceTexts: [String], targetLanguage: String, depth: Int) async throws -> [String] {
        guard !sourceTexts.isEmpty else { return [] }
        if sourceTexts.count == 1 {
            return try await translateBatchOnce(sourceTexts, targetLanguage: targetLanguage)
        }

        let totalChars = sourceTexts.reduce(0) { $0 + $1.count }
        if totalChars > 2400 && depth < 6 {
            let mid = sourceTexts.count / 2
            let left = try await translateBatchAdaptive(Array(sourceTexts[..<mid]), targetLanguage: targetLanguage, depth: depth + 1)
            let right = try await translateBatchAdaptive(Array(sourceTexts[mid...]), targetLanguage: targetLanguage, depth: depth + 1)
            return left + right
        }

        do {
            return try await translateBatchOnce(sourceTexts, targetLanguage: targetLanguage)
        } catch {
            if (isTimeout(error) || isFormatMismatch(error)), sourceTexts.count > 1, depth < 8 {
                let mid = sourceTexts.count / 2
                let left = try await translateBatchAdaptive(Array(sourceTexts[..<mid]), targetLanguage: targetLanguage, depth: depth + 1)
                let right = try await translateBatchAdaptive(Array(sourceTexts[mid...]), targetLanguage: targetLanguage, depth: depth + 1)
                return left + right
            }
            throw error
        }
    }

    private func translateBatchOnce(_ sourceTexts: [String], targetLanguage: String) async throws -> [String] {
        let payloadInput = sourceTexts.enumerated().map { ["i": $0.offset + 1, "t": $0.element] }
        let inputData = try JSONSerialization.data(withJSONObject: payloadInput)
        let inputJSON = String(decoding: inputData, as: UTF8.self)

        let prompt = """
        Translate subtitle items to \(targetLanguage) with context.
        Return STRICT JSON only:
        {"items":[{"i":1,"t":"..."},{"i":2,"t":"..."}]}
        Rules:
        - Keep item count identical.
        - Keep i unchanged.
        - No extra fields, no markdown, no explanations.
        Input:
        \(inputJSON)
        """

        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "format": "json",
            "keep_alive": "0s",
            "options": [
                "temperature": 0.1
            ],
            "messages": [
                ["role": "system", "content": "You are a precise subtitle translator."],
                ["role": "user", "content": prompt]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 86_400
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let content = try await streamChatContent(request: request)
        let cleanedContent = stripThinkBlocks(in: content)

        return try parseStrictJSONOrFallback(content: cleanedContent, expectedCount: sourceTexts.count)
    }

    private func streamChatContent(request: URLRequest) async throws -> String {
        var attempt = 0
        var backoff: TimeInterval = 1.5
        let maxAttempts = 4

        while true {
            attempt += 1
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AppError.invalidResponse("Ollama 未返回 HTTP 响应")
                }
                guard (200...299).contains(http.statusCode) else {
                    throw AppError.invalidResponse("Ollama HTTP 状态异常: \(http.statusCode)")
                }

                var aggregated = ""
                for try await line in bytes.lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }

                    guard let lineData = trimmed.data(using: .utf8),
                          let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                    else {
                        continue
                    }

                    if let msg = root["message"] as? [String: Any],
                       let chunk = msg["content"] as? String {
                        aggregated += chunk
                    }

                    if let error = root["error"] as? String, !error.isEmpty {
                        throw AppError.invalidResponse("Ollama 返回错误: \(error)")
                    }
                }

                guard !aggregated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AppError.parseFailed("Ollama 返回为空")
                }
                return aggregated
            } catch {
                if attempt < maxAttempts, isRetriable(error) {
                    let jitter = Double.random(in: 0...0.5)
                    try? await Task.sleep(nanoseconds: UInt64((backoff + jitter) * 1_000_000_000))
                    backoff *= 2
                    continue
                }
                throw error
            }
        }
    }

    private func isRetriable(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet].contains(urlError.code)
        }
        if let appError = error as? AppError,
           case .invalidResponse(let detail) = appError {
            return detail.contains("408") || detail.contains("429") || detail.contains("500") || detail.contains("502") || detail.contains("503") || detail.contains("504")
        }
        return false
    }

    private func isTimeout(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        return false
    }

    private func isFormatMismatch(_ error: Error) -> Bool {
        guard case let AppError.parseFailed(detail) = error else { return false }
        return detail.contains("条数不一致") || detail.contains("JSON")
    }

    private func parseStrictJSONOrFallback(content: String, expectedCount: Int) throws -> [String] {
        if let strict = parseStrictItemsJSON(content: content, expectedCount: expectedCount) {
            return strict
        }

        // Fallback: numbered line parse with best-effort truncation.
        let lines = content
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var translations: [String] = []
        for line in lines {
            if let dot = line.firstIndex(of: ".") {
                let text = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { translations.append(text) }
            }
        }

        if translations.count >= expectedCount {
            return Array(translations.prefix(expectedCount))
        }

        if expectedCount == 1 {
            let one = normalizeSingleTranslation(content)
            if !one.isEmpty { return [one] }
        }

        throw AppError.parseFailed("Ollama 翻译条数不一致: got=\(translations.count), expected=\(expectedCount)")
    }

    private func parseStrictItemsJSON(content: String, expectedCount: Int) -> [String]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = extractJSONData(from: trimmed),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else {
            return nil
        }

        let sorted = items.sorted { lhs, rhs in
            (lhs["i"] as? Int ?? 0) < (rhs["i"] as? Int ?? 0)
        }
        let texts = sorted.compactMap { $0["t"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard texts.count == expectedCount else { return nil }
        return texts
    }

    private func extractJSONData(from text: String) -> Data? {
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        let candidate = String(text[start...end])
        guard let data = candidate.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return data
    }

    private func stripThinkBlocks(in text: String) -> String {
        var output = text
        let patterns = [
            #"<think>[\s\S]*?</think>"#,
            #"<\|begin_of_thought\|>[\s\S]*?<\|end_of_thought\|>"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: "")
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSingleTranslation(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return ""
        }
        return trimmed
    }
}
