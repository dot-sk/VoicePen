import Foundation

nonisolated struct AppEnvironmentSettings: Codable, Equatable, Sendable {
    var env: [String: String]

    static let empty = AppEnvironmentSettings(env: [:])
}

nonisolated final class AppEnvironmentSettingsStore: @unchecked Sendable {
    private let settingsURL: URL
    private let fileManager: FileManager

    init(
        settingsURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.settingsURL = settingsURL ?? Self.defaultSettingsURL(fileManager: fileManager)
        self.fileManager = fileManager
    }

    func load() throws -> AppEnvironmentSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: settingsURL)
        let settings = try JSONDecoder().decode(AppEnvironmentSettings.self, from: data)
        return AppEnvironmentSettings(env: Self.normalizedEnvironment(settings.env))
    }

    func applyEnvironment(_ setEnvironmentValue: (String, String) -> Void = defaultSetEnvironmentValue) throws {
        let settings = try load()
        for (key, value) in settings.env {
            setEnvironmentValue(key, value)
        }
    }

    static func normalizedEnvironment(_ environment: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]

        for (key, value) in environment {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            normalized[normalizedKey] = normalizedValue
        }

        if normalized["http_proxy"] == nil, let value = normalized["HTTP_PROXY"] {
            normalized["http_proxy"] = value
        }

        if normalized["HTTP_PROXY"] == nil, let value = normalized["http_proxy"] {
            normalized["HTTP_PROXY"] = value
        }

        if normalized["https_proxy"] == nil {
            normalized["https_proxy"] = normalized["HTTPS_PROXY"] ?? normalized["http_proxy"]
        }

        if normalized["HTTPS_PROXY"] == nil, let value = normalized["https_proxy"] {
            normalized["HTTPS_PROXY"] = value
        }

        return normalized
    }

    static func defaultSettingsURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".voicepen", isDirectory: true)
            .appendingPathComponent("settings.json")
    }
}

nonisolated private func defaultSetEnvironmentValue(_ key: String, _ value: String) {
    setenv(key, value, 1)
}
