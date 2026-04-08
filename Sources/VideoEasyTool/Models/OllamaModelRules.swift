import Foundation

enum OllamaResolvedWorkMode: Equatable {
    case structuredJSON
    case singleText
    case unsupported(String)
}

enum OllamaModelCategory: String {
    case generalChat = "general-chat"
    case translation = "translation"
    case embedding = "embedding"
    case vision = "vision"
}

struct OllamaModelRule {
    let keywords: [String]
    let category: OllamaModelCategory
    let mode: OllamaResolvedWorkMode
    let reason: String

    func matches(_ normalizedName: String) -> Bool {
        keywords.contains { normalizedName.contains($0) }
    }

    func matchedKeywords(in normalizedName: String) -> [String] {
        keywords.filter { normalizedName.contains($0) }
    }
}

enum OllamaModelRules {
    static let rules: [OllamaModelRule] = [
        OllamaModelRule(
            keywords: ["translate", "translator"],
            category: .translation,
            mode: .singleText,
            reason: "Translation-oriented models usually work more reliably with one subtitle item per request."
        ),
        OllamaModelRule(
            keywords: ["embed", "embedding", "bge", "minilm", "e5", "nomic-embed", "mxbai-embed"],
            category: .embedding,
            mode: .unsupported("Embedding models do not generate subtitle translations."),
            reason: "Embedding models are for vector generation, not subtitle translation."
        ),
        OllamaModelRule(
            keywords: ["vision", "multimodal", "vl"],
            category: .vision,
            mode: .structuredJSON,
            reason: "Vision-capable chat models still use structured batch mode for subtitle translation."
        ),
        OllamaModelRule(
            keywords: ["qwen", "llama", "gemma", "mistral", "deepseek", "gpt-oss"],
            category: .generalChat,
            mode: .structuredJSON,
            reason: "General chat models default to structured batch translation."
        ),
        OllamaModelRule(
            keywords: ["instruct", "chat"],
            category: .generalChat,
            mode: .structuredJSON,
            reason: "Instruction/chat-tuned models default to structured batch translation."
        )
    ]

    static func resolve(modelName: String, userPreference: OllamaWorkMode) -> OllamaResolvedWorkMode {
        switch userPreference {
        case .structuredJSON:
            return .structuredJSON
        case .singleText:
            return .singleText
        case .automatic:
            let normalized = normalize(modelName)
            return matchedRule(forNormalizedName: normalized)?.mode ?? .structuredJSON
        }
    }

    static func matchedRule(for modelName: String) -> OllamaModelRule? {
        matchedRule(forNormalizedName: normalize(modelName))
    }

    static func matchedKeywords(for modelName: String) -> [String] {
        let normalized = normalize(modelName)
        guard let rule = matchedRule(forNormalizedName: normalized) else { return [] }
        return rule.matchedKeywords(in: normalized)
    }

    static func recommendedSummary() -> [String] {
        rules.map { rule in
            let names = rule.keywords.joined(separator: ", ")
            return "\(names): \(rule.reason)"
        }
    }

    private static func matchedRule(forNormalizedName normalized: String) -> OllamaModelRule? {
        let prioritizedCategories: [OllamaModelCategory] = [.embedding, .translation, .vision, .generalChat]

        for category in prioritizedCategories {
            if let rule = rules.first(where: { $0.category == category && $0.matches(normalized) }) {
                return rule
            }
        }
        return nil
    }

    private static func normalize(_ modelName: String) -> String {
        modelName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }
}
