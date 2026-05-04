import Foundation

nonisolated struct CommandIntent: Equatable, Sendable {
    var id: String
    var confidence: Double
    var argumentText: String?
    var slots: [String: String]

    init(
        id: String,
        confidence: Double,
        argumentText: String?,
        slots: [String: String] = [:]
    ) {
        self.id = id
        self.confidence = confidence
        self.argumentText = argumentText
        self.slots = slots
    }
}

nonisolated enum LLMIntentParserResult: Equatable, Sendable {
    case disabled
    case parsed(CommandIntent)
    case rejected(LLMIntentRejectionReason)
    case providerFailed(LLMClientError)
    case invalidModelOutput(LLMInvalidModelOutputReason)
}

nonisolated protocol LLMIntentParsing: Sendable {
    func parse(
        transcript: String,
        context: ActiveAppContext,
        config: UserConfig
    ) async -> LLMIntentParserResult
}

nonisolated enum LLMIntentRejectionReason: Equatable, Sendable {
    case lowConfidence(confidence: Double, threshold: Double)
    case unsupportedIntent(String)
    case unknown
}

nonisolated enum LLMInvalidModelOutputReason: Equatable, Sendable {
    case invalidJSON
    case schemaMismatch(String)
}

nonisolated struct LLMIntentDefinition: Equatable, Sendable {
    var id: String
    var description: String
    var argumentPolicy: String
    var slotHints: [String]

    init(
        id: String,
        description: String,
        argumentPolicy: String,
        slotHints: [String] = []
    ) {
        self.id = id
        self.description = description
        self.argumentPolicy = argumentPolicy
        self.slotHints = slotHints
    }
}

nonisolated enum LLMIntentRegistry {
    static func intents(for context: ActiveAppContext) -> [LLMIntentDefinition] {
        switch context {
        case .plain:
            return []
        case .developer:
            return commonDeveloperIntents
        case .terminal:
            return terminalIntents + commonDeveloperIntents
        }
    }

    private static let terminalIntents: [LLMIntentDefinition] = [
        LLMIntentDefinition(
            id: "git.branch.create",
            description: "create a new branch",
            argumentPolicy: "argumentText is branch topic/name/key as spoken",
            slotHints: ["branchKind feature/fix/refactor/chore/docs/test when explicit"]
        ),
        LLMIntentDefinition(
            id: "git.pull",
            description: "pull changes",
            argumentPolicy: "argumentText is null unless the user names a useful target",
            slotHints: ["targetBranch when master/main is explicit"]
        ),
        LLMIntentDefinition(
            id: "git.push",
            description: "push current branch",
            argumentPolicy: "argumentText is null unless the user names a useful target",
            slotHints: ["remoteName when origin/upstream is explicit"]
        ),
        LLMIntentDefinition(
            id: "git.commit",
            description: "create commit",
            argumentPolicy: "argumentText is commit message",
            slotHints: []
        )
    ]

    private static let commonDeveloperIntents: [LLMIntentDefinition] = [
        LLMIntentDefinition(
            id: "unknown",
            description: "unsupported, destructive, or ambiguous request",
            argumentPolicy: "argumentText is null",
            slotHints: []
        )
    ]
}

nonisolated enum LLMIntentPromptBuilder {
    static func buildPrompt(transcript: String, intents: [LLMIntentDefinition]) -> String {
        """
        Parse noisy Russian developer speech into one JSON object.
        No shell commands, markdown, prose, thoughts, or reasoning. Return final JSON only.

        Output keys exactly: intent, confidence, argumentText, slots.
        intent must be one of the allowed intents below.
        confidence is a number from 0 to 1.
        argumentText is the useful spoken object/target/message for the command. Keep it short.
        Use null when the user did not provide a useful object.
        slots is a JSON object with obvious controlled metadata only. Use string values. Use {} when none.

        Allowed intents:
        \(intentCatalog(from: intents))

        General rules:
        - Choose the intent from the user's requested action, not from exact keywords only.
        - Do not invent issue keys, branch names, remotes, or target branches.
        - Do not do complex spoken-number conversion. Preserve the useful spoken object if unsure.
        - Current repo, current branch, and default remote are implicit.
        - If the utterance is not a supported developer command, use intent "unknown".
        - If the command is destructive or ambiguous, use intent "unknown".

        Input: \(transcript)
        Output:
        """
    }

    static func intentCatalog(from intents: [LLMIntentDefinition]) -> String {
        intents
            .map { intent in
                let slotText = intent.slotHints.isEmpty ? "slots: {} when none" : "slots: \(intent.slotHints.joined(separator: "; "))"
                return "- \(intent.id): \(intent.description). \(intent.argumentPolicy). \(slotText)."
            }
            .joined(separator: "\n")
    }
}

nonisolated enum LLMIntentOutputSchema {
    static let schema = LLMJSONSchema(
        name: "voicepen_intent_parse",
        schema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([
                .string("intent"),
                .string("confidence"),
                .string("argumentText"),
                .string("slots")
            ]),
            "properties": .object([
                "intent": .object([
                    "type": .string("string")
                ]),
                "confidence": .object([
                    "type": .string("number"),
                    "minimum": .number(0),
                    "maximum": .number(1)
                ]),
                "argumentText": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "slots": .object([
                    "type": .string("object"),
                    "additionalProperties": .object([
                        "type": .string("string")
                    ])
                ])
            ])
        ]),
        strict: true
    )
}

nonisolated enum LLMIntentCandidateDetector {
    private static let maximumCharacters = 160
    private static let maximumTokens = 24

    private static let actionTokens = Set([
        "создай",
        "сделай",
        "новая",
        "новую",
        "new",
        "create",
        "закоммить",
        "закомить",
        "коммит",
        "commit",
        "пуш",
        "пушни",
        "запушь",
        "push",
        "пул",
        "пулл",
        "pull",
        "обнови",
        "запусти",
        "run",
        "удали",
        "delete"
    ])

    private static let conversationalTokens = Set([
        "что",
        "какие",
        "покажи",
        "показать",
        "давай",
        "ну",
        "please",
        "show"
    ])

    private static let domainTokens = Set([
        "git",
        "гит",
        "гид",
        "гита",
        "гите",
        "гиту",
        "ветка",
        "ветку",
        "ветки",
        "branch",
        "branches",
        "бранч",
        "брэнч",
        "бренч",
        "коммит",
        "commit",
        "пуш",
        "push",
        "пул",
        "пулл",
        "pull",
        "origin",
        "ориджин",
        "main",
        "мейн",
        "master",
        "мастер"
    ])

    static func isCandidate(transcript: String, context: ActiveAppContext, intents: [LLMIntentDefinition]) -> Bool {
        guard context != .plain, !intents.isEmpty else { return false }

        let trimmed = transcript.trimmed
        guard !trimmed.isEmpty, trimmed.count <= maximumCharacters else { return false }

        let tokens = tokenize(trimmed)
        guard !tokens.isEmpty, tokens.count <= maximumTokens else { return false }

        let tokenSet = Set(tokens)
        let hasDomainSignal = !tokenSet.isDisjoint(with: domainTokens)
        let hasActionSignal = !tokenSet.isDisjoint(with: actionTokens)
        let hasConversationalSignal = !tokenSet.isDisjoint(with: conversationalTokens)

        if hasDomainSignal, hasActionSignal || hasConversationalSignal {
            return true
        }

        return containsCommandPhrase(tokens)
    }

    private static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func containsCommandPhrase(_ tokens: [String]) -> Bool {
        let text = tokens.joined(separator: " ")
        let phrases = [
            "создай ветку",
            "сделай ветку",
            "создай бранч",
            "сделай бранч",
            "new branch",
            "create branch",
            "git status",
            "git pull",
            "git push",
            "git commit"
        ]
        return phrases.contains { text.contains($0) }
    }
}

nonisolated final class LLMIntentParser: @unchecked Sendable {
    private let client: LLMClient
    private let registry: @Sendable (ActiveAppContext) -> [LLMIntentDefinition]

    init(
        client: LLMClient,
        registry: @escaping @Sendable (ActiveAppContext) -> [LLMIntentDefinition] = { LLMIntentRegistry.intents(for: $0) }
    ) {
        self.client = client
        self.registry = registry
    }

    func parse(
        transcript: String,
        context: ActiveAppContext,
        config: UserConfig
    ) async -> LLMIntentParserResult {
        guard config.developer.intentParser.enabled, context != .plain else {
            return .disabled
        }

        let intents = registry(context)
        guard !intents.isEmpty else {
            return .disabled
        }
        guard LLMIntentCandidateDetector.isCandidate(
            transcript: transcript,
            context: context,
            intents: intents
        ) else {
            return .disabled
        }

        let prompt = LLMIntentPromptBuilder.buildPrompt(transcript: transcript, intents: intents)
        let result = await client.completeJSON(
            LLMStructuredRequest(prompt: prompt, schema: LLMIntentOutputSchema.schema)
        )

        switch result {
        case let .failure(error):
            return .providerFailed(error)
        case let .success(output):
            return validate(
                output,
                allowedIntentIDs: Set(intents.map(\.id)),
                threshold: config.developer.intentParser.confidenceThreshold
            )
        }
    }

    private func validate(
        _ output: String,
        allowedIntentIDs: Set<String>,
        threshold: Double
    ) -> LLMIntentParserResult {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .invalidModelOutput(.invalidJSON)
        }

        let expectedKeys = Set(["intent", "confidence", "argumentText", "slots"])
        guard Set(object.keys) == expectedKeys else {
            return .invalidModelOutput(.schemaMismatch("Output keys must be exactly intent, confidence, argumentText, slots."))
        }

        guard let intent = object["intent"] as? String else {
            return .invalidModelOutput(.schemaMismatch("intent must be a string."))
        }
        guard let confidence = object["confidence"] as? Double, (0...1).contains(confidence) else {
            return .invalidModelOutput(.schemaMismatch("confidence must be a number from 0 to 1."))
        }
        guard object["argumentText"] is String || object["argumentText"] is NSNull else {
            return .invalidModelOutput(.schemaMismatch("argumentText must be a string or null."))
        }
        guard let slots = object["slots"] as? [String: String] else {
            return .invalidModelOutput(.schemaMismatch("slots must be an object with string values."))
        }

        guard allowedIntentIDs.contains(intent) else {
            return .rejected(.unsupportedIntent(intent))
        }
        guard intent != "unknown" else {
            return .rejected(.unknown)
        }
        guard confidence >= threshold else {
            return .rejected(.lowConfidence(confidence: confidence, threshold: threshold))
        }

        let rawArgument = object["argumentText"] as? String
        let argumentText = rawArgument?.trimmed
        return .parsed(
            CommandIntent(
                id: intent,
                confidence: confidence,
                argumentText: argumentText?.isEmpty == true ? nil : argumentText,
                slots: slots
            )
        )
    }
}

extension LLMIntentParser: LLMIntentParsing {}

nonisolated enum LLMIntentCommandRenderer {
    static func render(
        intent: CommandIntent,
        config: UserConfig,
        context: ActiveAppContext,
        diagnosticNotes: [String]
    ) -> DeveloperModeProcessingResult? {
        guard context == .terminal,
              let commandText = commandText(for: intent)
        else {
            return nil
        }

        return DeveloperModeProcessingResult(
            text: commandText,
            insertionAction: config.developer.terminalCommandAction,
            diagnosticNotes: diagnosticNotes,
            activeContext: context,
            matchedCommandID: "llm:\(intent.id)"
        )
    }

    private static func commandText(for intent: CommandIntent) -> String? {
        switch intent.id {
        case "git.branch.create":
            guard let branchTopic = intent.argumentText?.trimmed, !branchTopic.isEmpty else {
                return nil
            }
            let branchName = branchName(from: branchTopic, slots: intent.slots)
            guard !branchName.isEmpty else { return nil }
            return "git checkout -b \(branchName)"
        case "git.pull":
            return "git pull"
        case "git.push":
            if let remoteName = allowedRemoteName(intent.slots["remoteName"]) {
                return "git push \(remoteName)"
            }
            return "git push"
        case "git.commit":
            guard let message = intent.argumentText?.trimmed, !message.isEmpty else {
                return nil
            }
            return "git commit -m \(shellSingleQuoted(message))"
        default:
            return nil
        }
    }

    private static func branchName(from argumentText: String, slots: [String: String]) -> String {
        let topic = CaseFormatter.gitBranch(argumentText)
        guard let branchKind = allowedBranchKind(slots["branchKind"]) else {
            return topic
        }
        return "\(branchKind)/\(topic)"
    }

    private static func allowedBranchKind(_ value: String?) -> String? {
        guard let value = value?.lowercased() else { return nil }
        let allowed = Set(["feature", "fix", "refactor", "chore", "docs", "test"])
        return allowed.contains(value) ? value : nil
    }

    private static func allowedRemoteName(_ value: String?) -> String? {
        guard let value = value?.lowercased() else { return nil }
        let allowed = Set(["origin", "upstream"])
        return allowed.contains(value) ? value : nil
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
