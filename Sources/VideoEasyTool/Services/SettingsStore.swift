import Foundation

final class SettingsStore {
    private let fileURL: URL
    private let keychain = KeychainStore()
    private let openAIAPIKeyAccount = "openai_api_key"

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VideoEasyTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("settings.json")
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL) else {
            var settings = AppSettings.default
            settings.openAIAPIKey = keychain.read(account: openAIAPIKeyAccount) ?? ""
            return settings
        }

        var settings = (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .default
        let legacyAPIKey = settings.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keychainAPIKey = keychain.read(account: openAIAPIKeyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !keychainAPIKey.isEmpty {
            settings.openAIAPIKey = keychainAPIKey
        } else if !legacyAPIKey.isEmpty {
            keychain.write(legacyAPIKey, account: openAIAPIKeyAccount)
            settings.openAIAPIKey = legacyAPIKey
            save(settings)
        } else {
            settings.openAIAPIKey = ""
        }

        return settings
    }

    func save(_ settings: AppSettings) {
        let apiKey = settings.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if apiKey.isEmpty {
            keychain.delete(account: openAIAPIKeyAccount)
        } else {
            keychain.write(apiKey, account: openAIAPIKeyAccount)
        }

        do {
            var sanitized = settings
            sanitized.openAIAPIKey = ""
            let data = try JSONEncoder().encode(sanitized)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // No-op: keep UI responsive even if persistence fails.
        }
    }
}
