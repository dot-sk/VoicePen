import Foundation

nonisolated enum DeveloperMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case plain
    case auto
    case developer
    case terminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain:
            return "Plain"
        case .auto:
            return "Auto"
        case .developer:
            return "Writing Code"
        case .terminal:
            return "Terminal"
        }
    }

    var userDescription: String {
        switch self {
        case .plain:
            return "Keeps dictation simple and inserts the cleaned-up text without code or terminal command handling."
        case .auto:
            return "Chooses the best mode from the active app: Terminal for shells, Writing Code for code editors, Plain everywhere else."
        case .developer:
            return "For writing code and technical notes. Improves developer terms without submitting terminal commands."
        case .terminal:
            return "For shells. Can map configured voice phrases to commands, such as \"show git status\" to \"git status --short --branch\"."
        }
    }
}

nonisolated enum ActiveAppContext: String, Codable, Sendable {
    case plain
    case developer
    case terminal
}

nonisolated enum TextInsertionAction: String, Codable, Sendable {
    case paste
    case pasteAndSubmit
}

nonisolated struct ActiveApplicationInfo: Equatable, Sendable {
    var bundleIdentifier: String?
    var localizedName: String?
}

nonisolated struct DeveloperCommand: Codable, Equatable, Sendable {
    var id: String
    var triggers: [String]
    var template: String
    var action: TextInsertionAction?

    init(
        id: String,
        triggers: [String],
        template: String,
        action: TextInsertionAction? = nil
    ) {
        self.id = id
        self.triggers = triggers
        self.template = template
        self.action = action
    }
}

nonisolated struct DeveloperConfig: Codable, Equatable, Sendable {
    var mode: DeveloperMode
    var terminalCommandAction: TextInsertionAction
    var intentParser: DeveloperIntentParserConfig

    init(
        mode: DeveloperMode = .auto,
        terminalCommandAction: TextInsertionAction = .paste,
        intentParser: DeveloperIntentParserConfig = DeveloperIntentParserConfig()
    ) {
        self.mode = mode
        self.terminalCommandAction = terminalCommandAction
        self.intentParser = intentParser
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case terminalCommandAction = "terminal_command_action"
        case intentParser = "intent_parser"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decodeIfPresent(DeveloperMode.self, forKey: .mode) ?? .auto
        self.terminalCommandAction =
            try container.decodeIfPresent(TextInsertionAction.self, forKey: .terminalCommandAction) ?? .paste
        self.intentParser =
            try container.decodeIfPresent(DeveloperIntentParserConfig.self, forKey: .intentParser)
            ?? DeveloperIntentParserConfig()
    }
}

nonisolated struct DeveloperIntentParserConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var confidenceThreshold: Double

    init(
        enabled: Bool = false,
        confidenceThreshold: Double = 0.75
    ) {
        self.enabled = enabled
        self.confidenceThreshold = confidenceThreshold
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case confidenceThreshold = "confidence_threshold"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.confidenceThreshold =
            try container.decodeDoubleOrIntIfPresent(forKey: .confidenceThreshold) ?? 0.75
    }
}

nonisolated struct UserAliasesConfig: Codable, Equatable, Sendable {
    var common: [String: String]
    var developer: [String: String]
    var terminal: [String: String]

    init(
        common: [String: String] = [:],
        developer: [String: String] = [:],
        terminal: [String: String] = [:]
    ) {
        self.common = common
        self.developer = developer
        self.terminal = terminal
    }

    func aliases(for context: ActiveAppContext) -> [String: String] {
        switch context {
        case .plain:
            return common
        case .developer:
            return common.merging(developer) { _, contextValue in contextValue }
        case .terminal:
            return common.merging(terminal) { _, contextValue in contextValue }
        }
    }

    enum CodingKeys: String, CodingKey {
        case common
        case developer
        case terminal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.common = try container.decodeIfPresent([String: String].self, forKey: .common) ?? [:]
        self.developer = try container.decodeIfPresent([String: String].self, forKey: .developer) ?? [:]
        self.terminal = try container.decodeIfPresent([String: String].self, forKey: .terminal) ?? [:]
    }
}

nonisolated struct UserCommandsConfig: Codable, Equatable, Sendable {
    var developer: [DeveloperCommand]
    var terminal: [DeveloperCommand]

    init(
        developer: [DeveloperCommand] = [],
        terminal: [DeveloperCommand] = []
    ) {
        self.developer = developer
        self.terminal = terminal
    }

    func commands(for context: ActiveAppContext) -> [DeveloperCommand] {
        switch context {
        case .plain:
            return []
        case .developer:
            return developer
        case .terminal:
            return terminal
        }
    }

    enum CodingKeys: String, CodingKey {
        case developer
        case terminal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.developer = try container.decodeIfPresent([DeveloperCommand].self, forKey: .developer) ?? []
        self.terminal = try container.decodeIfPresent([DeveloperCommand].self, forKey: .terminal) ?? []
    }
}

nonisolated struct UserConfig: Codable, Equatable, Sendable {
    var env: [String: String]
    var llm: LLMConfig
    var developer: DeveloperConfig
    var aliases: UserAliasesConfig
    var commands: UserCommandsConfig

    init(
        env: [String: String] = [:],
        llm: LLMConfig = LLMConfig(),
        developer: DeveloperConfig = DeveloperConfig(),
        aliases: UserAliasesConfig = UserAliasesConfig(),
        commands: UserCommandsConfig = UserCommandsConfig()
    ) {
        self.env = env
        self.llm = llm
        self.developer = developer
        self.aliases = aliases
        self.commands = commands
    }
}

nonisolated struct UserConfigLoadResult: Equatable, Sendable {
    var config: UserConfig
    var diagnosticNotes: [String]

    init(config: UserConfig, diagnosticNotes: [String] = []) {
        self.config = config
        self.diagnosticNotes = diagnosticNotes
    }
}

nonisolated struct DeveloperModeProcessingResult: Equatable, Sendable {
    var text: String
    var insertionAction: TextInsertionAction
    var diagnosticNotes: [String]
    var activeContext: ActiveAppContext
    var matchedCommandID: String?

    init(
        text: String,
        insertionAction: TextInsertionAction = .paste,
        diagnosticNotes: [String] = [],
        activeContext: ActiveAppContext = .plain,
        matchedCommandID: String? = nil
    ) {
        self.text = text
        self.insertionAction = insertionAction
        self.diagnosticNotes = diagnosticNotes
        self.activeContext = activeContext
        self.matchedCommandID = matchedCommandID
    }
}

nonisolated private extension KeyedDecodingContainer {
    func decodeDoubleOrIntIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}
