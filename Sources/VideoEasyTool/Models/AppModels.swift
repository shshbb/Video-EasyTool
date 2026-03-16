import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable, Codable {
    case openAICompatible = "OpenAI Compatible"
    case ollama = "Ollama"

    var id: String { rawValue }
}

enum TranslationMode: String, CaseIterable, Identifiable, Codable {
    case fast = "极速"
    case balanced = "标准"
    case quality = "高质量"

    var id: String { rawValue }
}

enum DisplayLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese = "简体中文"
    case english = "English"

    var id: String { rawValue }

    static var systemDefault: DisplayLanguage {
        let preferred = Locale.preferredLanguages

        for identifier in preferred {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("zh-hans") || normalized.hasPrefix("zh-hant") || normalized.hasPrefix("zh") {
                return .simplifiedChinese
            }
        }

        return .english
    }
}

enum TaskKind: String, Equatable {
    case downloadVideo
    case transcodeVideo
    case transcribeVideo
    case translateSubtitle
    case downloadModel
    case checkModel
    case deleteModel
    case installDependency
}

enum TranscriptionModel: String, CaseIterable, Identifiable, Codable {
    case tiny = "ggml-tiny.bin"
    case base = "ggml-base.bin"
    case small = "ggml-small.bin"
    case medium = "ggml-medium.bin"
    case largeV3 = "ggml-large-v3.bin"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tiny:
            return "Whisper Tiny"
        case .base:
            return "Whisper Base"
        case .small:
            return "Whisper Small"
        case .medium:
            return "Whisper Medium"
        case .largeV3:
            return "Whisper Large V3"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(rawValue)")!
    }
}

enum TargetLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese = "中文（简体）"
    case traditionalChinese = "中文（繁体）"
    case english = "English"
    case japanese = "日本語"
    case korean = "한국어"
    case french = "Français"
    case german = "Deutsch"
    case spanish = "Español"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .simplifiedChinese: return "zh-CN"
        case .traditionalChinese: return "zh-TW"
        case .english: return "en"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .spanish: return "es"
        }
    }
}

struct AppSettings: Codable {
    var globalOutputDirectory: String
    var downloadOutputDirectory: String
    var transcodeOutputDirectory: String
    var transcribeOutputDirectory: String
    var translateOutputDirectory: String
    var openAIBaseURL: String
    var openAIAPIKey: String
    var transcriptionModel: TranscriptionModel
    var translationModel: String
    var ollamaBaseURL: String
    var ollamaModel: String
    var targetLanguage: TargetLanguage
    var provider: TranslationProvider
    var translationMode: TranslationMode
    var translationTemperature: Double
    var useCustomTranslationBatchSize: Bool
    var customTranslationBatchSize: Int
    var displayLanguage: DisplayLanguage

    enum CodingKeys: String, CodingKey {
        case outputDirectory
        case globalOutputDirectory
        case downloadOutputDirectory
        case transcodeOutputDirectory
        case transcribeOutputDirectory
        case translateOutputDirectory
        case openAIBaseURL
        case openAIAPIKey
        case transcriptionModel
        case translationModel
        case ollamaBaseURL
        case ollamaModel
        case targetLanguage
        case provider
        case translationMode
        case translationTemperature
        case useCustomTranslationBatchSize
        case customTranslationBatchSize
        case displayLanguage
    }

    init(
        globalOutputDirectory: String,
        downloadOutputDirectory: String,
        transcodeOutputDirectory: String,
        transcribeOutputDirectory: String,
        translateOutputDirectory: String,
        openAIBaseURL: String,
        openAIAPIKey: String,
        transcriptionModel: TranscriptionModel,
        translationModel: String,
        ollamaBaseURL: String,
        ollamaModel: String,
        targetLanguage: TargetLanguage,
        provider: TranslationProvider,
        translationMode: TranslationMode,
        translationTemperature: Double,
        useCustomTranslationBatchSize: Bool,
        customTranslationBatchSize: Int,
        displayLanguage: DisplayLanguage
    ) {
        self.globalOutputDirectory = globalOutputDirectory
        self.downloadOutputDirectory = downloadOutputDirectory
        self.transcodeOutputDirectory = transcodeOutputDirectory
        self.transcribeOutputDirectory = transcribeOutputDirectory
        self.translateOutputDirectory = translateOutputDirectory
        self.openAIBaseURL = openAIBaseURL
        self.openAIAPIKey = openAIAPIKey
        self.transcriptionModel = transcriptionModel
        self.translationModel = translationModel
        self.ollamaBaseURL = ollamaBaseURL
        self.ollamaModel = ollamaModel
        self.targetLanguage = targetLanguage
        self.provider = provider
        self.translationMode = translationMode
        self.translationTemperature = translationTemperature
        self.useCustomTranslationBatchSize = useCustomTranslationBatchSize
        self.customTranslationBatchSize = customTranslationBatchSize
        self.displayLanguage = displayLanguage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultDir = AppSettings.default.globalOutputDirectory
        let legacyOutput = try container.decodeIfPresent(String.self, forKey: .outputDirectory)
        self.globalOutputDirectory = try container.decodeIfPresent(String.self, forKey: .globalOutputDirectory) ?? legacyOutput ?? defaultDir
        self.downloadOutputDirectory = try container.decodeIfPresent(String.self, forKey: .downloadOutputDirectory) ?? self.globalOutputDirectory
        self.transcodeOutputDirectory = try container.decodeIfPresent(String.self, forKey: .transcodeOutputDirectory) ?? self.globalOutputDirectory
        self.transcribeOutputDirectory = try container.decodeIfPresent(String.self, forKey: .transcribeOutputDirectory) ?? self.globalOutputDirectory
        self.translateOutputDirectory = try container.decodeIfPresent(String.self, forKey: .translateOutputDirectory) ?? self.globalOutputDirectory
        self.openAIBaseURL = try container.decodeIfPresent(String.self, forKey: .openAIBaseURL) ?? AppSettings.default.openAIBaseURL
        self.openAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? AppSettings.default.openAIAPIKey
        self.translationModel = try container.decodeIfPresent(String.self, forKey: .translationModel) ?? AppSettings.default.translationModel
        self.ollamaBaseURL = try container.decodeIfPresent(String.self, forKey: .ollamaBaseURL) ?? AppSettings.default.ollamaBaseURL
        self.ollamaModel = try container.decodeIfPresent(String.self, forKey: .ollamaModel) ?? AppSettings.default.ollamaModel
        self.provider = try container.decodeIfPresent(TranslationProvider.self, forKey: .provider) ?? AppSettings.default.provider
        self.translationMode = try container.decodeIfPresent(TranslationMode.self, forKey: .translationMode) ?? .balanced
        self.translationTemperature = try container.decodeIfPresent(Double.self, forKey: .translationTemperature) ?? AppSettings.default.translationTemperature
        self.useCustomTranslationBatchSize = try container.decodeIfPresent(Bool.self, forKey: .useCustomTranslationBatchSize) ?? AppSettings.default.useCustomTranslationBatchSize
        self.customTranslationBatchSize = max(1, try container.decodeIfPresent(Int.self, forKey: .customTranslationBatchSize) ?? AppSettings.default.customTranslationBatchSize)
        self.displayLanguage = try container.decodeIfPresent(DisplayLanguage.self, forKey: .displayLanguage) ?? DisplayLanguage.systemDefault

        if let model = try? container.decode(TranscriptionModel.self, forKey: .transcriptionModel) {
            self.transcriptionModel = model
        } else if let modelRaw = try? container.decode(String.self, forKey: .transcriptionModel),
                  let model = TranscriptionModel(rawValue: modelRaw) {
            self.transcriptionModel = model
        } else {
            self.transcriptionModel = AppSettings.default.transcriptionModel
        }

        if let language = try? container.decode(TargetLanguage.self, forKey: .targetLanguage) {
            self.targetLanguage = language
        } else if let languageRaw = try? container.decode(String.self, forKey: .targetLanguage),
                  let mapped = TargetLanguage.allCases.first(where: { $0.code == languageRaw || $0.rawValue == languageRaw }) {
            self.targetLanguage = mapped
        } else {
            self.targetLanguage = AppSettings.default.targetLanguage
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(globalOutputDirectory, forKey: .globalOutputDirectory)
        try container.encode(downloadOutputDirectory, forKey: .downloadOutputDirectory)
        try container.encode(transcodeOutputDirectory, forKey: .transcodeOutputDirectory)
        try container.encode(transcribeOutputDirectory, forKey: .transcribeOutputDirectory)
        try container.encode(translateOutputDirectory, forKey: .translateOutputDirectory)
        try container.encode(openAIBaseURL, forKey: .openAIBaseURL)
        try container.encode(openAIAPIKey, forKey: .openAIAPIKey)
        try container.encode(transcriptionModel, forKey: .transcriptionModel)
        try container.encode(translationModel, forKey: .translationModel)
        try container.encode(ollamaBaseURL, forKey: .ollamaBaseURL)
        try container.encode(ollamaModel, forKey: .ollamaModel)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        try container.encode(provider, forKey: .provider)
        try container.encode(translationMode, forKey: .translationMode)
        try container.encode(translationTemperature, forKey: .translationTemperature)
        try container.encode(useCustomTranslationBatchSize, forKey: .useCustomTranslationBatchSize)
        try container.encode(customTranslationBatchSize, forKey: .customTranslationBatchSize)
        try container.encode(displayLanguage, forKey: .displayLanguage)
    }

    static let `default` = AppSettings(
        globalOutputDirectory: "outputs/global",
        downloadOutputDirectory: "outputs/downloads",
        transcodeOutputDirectory: "outputs/transcode",
        transcribeOutputDirectory: "outputs/transcribe",
        translateOutputDirectory: "outputs/translate",
        openAIBaseURL: "https://api.openai.com",
        openAIAPIKey: "",
        transcriptionModel: .base,
        translationModel: "gpt-4o-mini",
        ollamaBaseURL: "http://127.0.0.1:11434",
        ollamaModel: "qwen2.5:7b",
        targetLanguage: .simplifiedChinese,
        provider: .openAICompatible,
        translationMode: .balanced,
        translationTemperature: 0.1,
        useCustomTranslationBatchSize: false,
        customTranslationBatchSize: 12,
        displayLanguage: .systemDefault
    )
}

struct SubtitleCue: Identifiable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}
