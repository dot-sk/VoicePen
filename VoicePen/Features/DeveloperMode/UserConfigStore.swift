import Foundation
import TOMLKit

nonisolated struct AppEnvironmentSettings: Equatable, Sendable {
    var env: [String: String]

    static let empty = AppEnvironmentSettings(env: [:])
}

nonisolated final class UserConfigStore: @unchecked Sendable {
    private let configURL: URL
    private let defaultConfigURL: URL?
    private let defaultConfigText: String?
    private let fileManager: FileManager
    private let lock = NSLock()
    private var lastValidConfig: UserConfig?

    init(
        configURL: URL? = nil,
        defaultConfigURL: URL? = nil,
        defaultConfigText: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL ?? Self.defaultConfigURL(fileManager: fileManager)
        self.defaultConfigURL = defaultConfigURL
        self.defaultConfigText = defaultConfigText
        self.fileManager = fileManager
    }

    func loadConfig() -> UserConfigLoadResult {
        var diagnosticNotes: [String] = []

        do {
            try ensureUserConfigExists()
            let text = try String(contentsOf: configURL, encoding: .utf8)
            let config = try Self.parseConfig(text)
            let normalizedConfig = Self.normalizedConfig(config)
            setLastValidConfig(normalizedConfig)
            return UserConfigLoadResult(config: normalizedConfig)
        } catch {
            diagnosticNotes.append("User config could not be loaded: \(error.localizedDescription)")
            return UserConfigLoadResult(
                config: fallbackConfig(),
                diagnosticNotes: diagnosticNotes
            )
        }
    }

    func loadEnvironmentSettings() -> AppEnvironmentSettings {
        AppEnvironmentSettings(env: loadConfig().config.env)
    }

    func applyEnvironment(_ setEnvironmentValue: (String, String) -> Void = defaultSetEnvironmentValue) {
        let settings = loadEnvironmentSettings()
        for (key, value) in settings.env {
            setEnvironmentValue(key, value)
        }
    }

    var userConfigURL: URL {
        configURL
    }

    func ensureUserConfigFileExists() throws {
        try ensureUserConfigExists()
    }

    func saveAISettings(
        llm: LLMConfig,
        intentParser: DeveloperIntentParserConfig
    ) throws -> UserConfigLoadResult {
        try ensureUserConfigExists()
        let text = try String(contentsOf: configURL, encoding: .utf8)
        var config = try Self.parseConfig(text)
        config.llm = llm
        config.developer.intentParser = intentParser

        let normalizedConfig = Self.normalizedConfig(config)
        let encodedConfig = try Self.configEncoder.encode(normalizedConfig)
        try encodedConfig.write(to: configURL, atomically: true, encoding: .utf8)
        setLastValidConfig(normalizedConfig)
        return UserConfigLoadResult(config: normalizedConfig)
    }

    static func defaultConfigURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".voicepen", isDirectory: true)
            .appendingPathComponent("config.toml")
    }

    static func normalizedEnvironment(_ environment: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]

        for (key, value) in environment {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty, !normalizedValue.isEmpty else { continue }
            normalized[normalizedKey] = normalizedValue
        }

        mirrorProxyValue(lowercaseKey: "http_proxy", uppercaseKey: "HTTP_PROXY", in: &normalized)

        if normalized["https_proxy"] == nil {
            normalized["https_proxy"] = normalized["HTTPS_PROXY"] ?? normalized["http_proxy"]
        }

        mirrorProxyValue(lowercaseKey: "https_proxy", uppercaseKey: "HTTPS_PROXY", in: &normalized)

        return normalized
    }

    private static func mirrorProxyValue(
        lowercaseKey: String,
        uppercaseKey: String,
        in environment: inout [String: String]
    ) {
        if environment[lowercaseKey] == nil, let value = environment[uppercaseKey] {
            environment[lowercaseKey] = value
        }

        if environment[uppercaseKey] == nil, let value = environment[lowercaseKey] {
            environment[uppercaseKey] = value
        }
    }

    private func ensureUserConfigExists() throws {
        guard !fileManager.fileExists(atPath: configURL.path) else { return }

        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try resolvedDefaultConfigText().write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func fallbackConfig() -> UserConfig {
        if let lastValidConfigValue {
            return lastValidConfigValue
        }

        do {
            let config = try Self.parseConfig(resolvedDefaultConfigText())
            let normalizedConfig = Self.normalizedConfig(config)
            setLastValidConfig(normalizedConfig)
            return normalizedConfig
        } catch {
            return UserConfig()
        }
    }

    private var lastValidConfigValue: UserConfig? {
        lock.lock()
        defer { lock.unlock() }
        return lastValidConfig
    }

    private func setLastValidConfig(_ config: UserConfig) {
        lock.lock()
        lastValidConfig = config
        lock.unlock()
    }

    private func resolvedDefaultConfigText() throws -> String {
        if let defaultConfigText {
            return defaultConfigText
        }

        if let defaultConfigURL {
            return try String(contentsOf: defaultConfigURL, encoding: .utf8)
        }

        let bundleURL =
            Bundle.main.url(forResource: "default-config", withExtension: "toml")
            ?? Bundle.main.url(
                forResource: "default-config",
                withExtension: "toml",
                subdirectory: "Resources"
            )

        guard let bundleURL else {
            throw UserConfigStoreError.missingDefaultConfig
        }

        return try String(contentsOf: bundleURL, encoding: .utf8)
    }

    private static func parseConfig(_ text: String) throws -> UserConfig {
        let table = try TOMLTable(string: text)
        let rawConfig = try TOMLDecoder().decode(RawUserConfig.self, from: table)
        return UserConfig(
            env: rawConfig.env ?? [:],
            llm: rawConfig.llm ?? LLMConfig(),
            developer: rawConfig.developer ?? DeveloperConfig(),
            aliases: rawConfig.aliases ?? UserAliasesConfig(),
            commands: rawConfig.commands ?? UserCommandsConfig()
        )
    }

    private static func normalizedConfig(_ config: UserConfig) -> UserConfig {
        UserConfig(
            env: normalizedEnvironment(config.env),
            llm: normalizedLLMConfig(config.llm),
            developer: config.developer,
            aliases: UserAliasesConfig(
                common: normalizedAliases(config.aliases.common),
                developer: normalizedAliases(config.aliases.developer),
                terminal: normalizedAliases(config.aliases.terminal)
            ),
            commands: UserCommandsConfig(
                developer: normalizedCommands(config.commands.developer),
                terminal: normalizedCommands(config.commands.terminal)
            )
        )
    }

    private static func normalizedAliases(_ aliases: [String: String]) -> [String: String] {
        aliases.reduce(into: [:]) { result, pair in
            let key = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            result[key] = value
        }
    }

    private static func normalizedCommands(_ commands: [DeveloperCommand]) -> [DeveloperCommand] {
        commands.compactMap { command in
            let id = command.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let triggers = command.triggers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let template = command.template.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !triggers.isEmpty, !template.isEmpty else { return nil }
            return DeveloperCommand(
                id: id,
                triggers: triggers,
                template: template,
                action: command.action
            )
        }
    }

    private static func normalizedLLMConfig(_ config: LLMConfig) -> LLMConfig {
        LLMConfig(
            provider: config.provider,
            ollama: OllamaLLMConfig(
                baseURL: normalizedString(config.ollama.baseURL, fallback: OllamaLLMConfig.defaultBaseURL),
                model: normalizedString(config.ollama.model, fallback: OllamaLLMConfig.defaultModel),
                timeoutSeconds: positiveSeconds(
                    config.ollama.timeoutSeconds,
                    fallback: OllamaLLMConfig.defaultTimeoutSeconds
                ),
                think: config.ollama.think
            ),
            openrouter: OpenRouterLLMConfig(
                baseURL: normalizedString(config.openrouter.baseURL, fallback: OpenRouterLLMConfig.defaultBaseURL),
                model: normalizedString(config.openrouter.model, fallback: OpenRouterLLMConfig.defaultModel),
                apiKey: config.openrouter.apiKey.trimmed,
                timeoutSeconds: positiveSeconds(
                    config.openrouter.timeoutSeconds,
                    fallback: OpenRouterLLMConfig.defaultTimeoutSeconds
                )
            )
        )
    }

    private static func normalizedString(_ value: String, fallback: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? fallback : normalized
    }

    private static var configEncoder: TOMLEncoder {
        TOMLEncoder(options: [
            .allowLiteralStrings,
            .allowMultilineStrings,
            .allowUnicodeStrings,
            .indentations
        ])
    }

    private static func positiveSeconds(_ value: Double, fallback: Double) -> Double {
        value > 0 ? value : fallback
    }
}

typealias AppEnvironmentSettingsStore = UserConfigStore

nonisolated private struct RawUserConfig: Decodable {
    var env: [String: String]?
    var llm: LLMConfig?
    var developer: DeveloperConfig?
    var aliases: UserAliasesConfig?
    var commands: UserCommandsConfig?
}

private enum UserConfigStoreError: LocalizedError {
    case missingDefaultConfig

    var errorDescription: String? {
        switch self {
        case .missingDefaultConfig:
            return "Bundled default config is missing."
        }
    }
}

nonisolated private func defaultSetEnvironmentValue(_ key: String, _ value: String) {
    setenv(key, value, 1)
}
