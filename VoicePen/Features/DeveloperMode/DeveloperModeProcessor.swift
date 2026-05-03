import Foundation
import Stencil

nonisolated enum DeveloperModeProcessor {
    static func process(
        text: String,
        config: UserConfig,
        uiOverride: DeveloperMode?,
        activeApplication: ActiveApplicationInfo?,
        configDiagnosticNotes: [String] = []
    ) -> DeveloperModeProcessingResult {
        let context = ActiveAppContextClassifier.resolve(
            uiOverride: uiOverride,
            configMode: config.developer.mode,
            activeApplication: activeApplication
        )
        let aliases = config.aliases.aliases(for: context)
        let normalized = AliasNormalizer.normalize(text, aliases: aliases)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var diagnosticNotes = configDiagnosticNotes
        let commands = config.commands.commands(for: context)

        guard
            let match = bestCommandMatch(
                normalizedText: normalized,
                commands: commands,
                aliases: aliases
            )
        else {
            if looksCommandLike(normalized), !commands.isEmpty {
                diagnosticNotes.append("Command-like phrase did not match a configured command.")
            }

            return DeveloperModeProcessingResult(
                text: normalized,
                diagnosticNotes: diagnosticNotes,
                activeContext: context
            )
        }

        let action = resolvedAction(
            for: match.command,
            config: config,
            context: context
        )

        if match.command.template.contains("args"),
            match.args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            diagnosticNotes.append("Command rendered with empty args.")
        }

        do {
            let rendered = try CommandTemplateRenderer.render(
                template: match.command.template,
                text: text,
                normalized: normalized,
                args: match.args
            )
            let finalText = rendered.trimmingCharacters(in: .whitespacesAndNewlines)

            if finalText.isEmpty {
                diagnosticNotes.append("Command template rendered empty text.")
                return DeveloperModeProcessingResult(
                    text: normalized,
                    diagnosticNotes: diagnosticNotes,
                    activeContext: context,
                    matchedCommandID: match.command.id
                )
            }

            return DeveloperModeProcessingResult(
                text: finalText,
                insertionAction: action,
                diagnosticNotes: diagnosticNotes,
                activeContext: context,
                matchedCommandID: match.command.id
            )
        } catch {
            diagnosticNotes.append("Command template could not be rendered: \(error.localizedDescription)")
            return DeveloperModeProcessingResult(
                text: normalized,
                diagnosticNotes: diagnosticNotes,
                activeContext: context,
                matchedCommandID: match.command.id
            )
        }
    }

    private static func bestCommandMatch(
        normalizedText: String,
        commands: [DeveloperCommand],
        aliases: [String: String]
    ) -> CommandMatch? {
        let inputPhrase = CommandPhraseNormalizer.tokenize(normalizedText)
        guard !inputPhrase.tokens.isEmpty else { return nil }

        return
            commands
            .flatMap { command in
                command.triggers.compactMap { trigger -> CommandMatch? in
                    let triggerPhrase = CommandPhraseNormalizer.tokenize(
                        AliasNormalizer.normalize(trigger, aliases: aliases)
                    )
                    guard !triggerPhrase.tokens.isEmpty else { return nil }
                    guard
                        let consumedTokenCount = inputPhrase.consumedTokenCount(
                            matching: triggerPhrase,
                            ignoring: CommandPhraseNormalizer.fillerTokens
                        )
                    else { return nil }

                    let args = inputPhrase.args(afterTokenCount: consumedTokenCount)
                    guard command.template.contains("args") || args.isEmpty else { return nil }

                    return CommandMatch(
                        command: command,
                        normalizedTrigger: triggerPhrase.text,
                        triggerTokenCount: triggerPhrase.tokens.count,
                        args: args
                    )
                }
            }
            .sorted {
                if $0.triggerTokenCount != $1.triggerTokenCount {
                    return $0.triggerTokenCount > $1.triggerTokenCount
                }
                if $0.normalizedTrigger.count != $1.normalizedTrigger.count {
                    return $0.normalizedTrigger.count > $1.normalizedTrigger.count
                }
                return $0.command.id < $1.command.id
            }
            .first
    }

    private static func resolvedAction(
        for command: DeveloperCommand,
        config: UserConfig,
        context: ActiveAppContext
    ) -> TextInsertionAction {
        let configuredAction = command.action ?? config.developer.terminalCommandAction
        guard context == .terminal else {
            return .paste
        }
        return configuredAction
    }

    private static func looksCommandLike(_ text: String) -> Bool {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixes = [
            "git ",
            "show ",
            "create ",
            "new ",
            "покажи ",
            "создай ",
            "новая ",
            "новый "
        ]
        return prefixes.contains { lowercased.hasPrefix($0) }
    }
}

nonisolated enum CommandPhraseNormalizer {
    private static let punctuationSeparators = CharacterSet(charactersIn: ".,!?;:。！？")
    static let fillerTokens = Set(["ну", "давай", "пожалуйста", "please"])

    static func tokenize(_ text: String) -> CommandPhrase {
        let separated = String(
            text.unicodeScalars.map { scalar in
                punctuationSeparators.contains(scalar) ? " " : Character(scalar)
            }
        )
        let tokens =
            separated
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        return CommandPhrase(tokens: tokens)
    }
}

nonisolated struct CommandPhrase: Equatable, Sendable {
    var tokens: [String]

    var text: String {
        tokens.joined(separator: " ")
    }

    private var comparableTokens: [String] {
        tokens.map { $0.lowercased() }
    }

    func consumedTokenCount(matching trigger: CommandPhrase, ignoring fillerTokens: Set<String>) -> Int? {
        let inputTokens = comparableTokens
        let triggerTokens = trigger.comparableTokens
        var inputIndex = 0
        var triggerIndex = 0

        while triggerIndex < triggerTokens.count {
            guard inputIndex < inputTokens.count else { return nil }

            if inputTokens[inputIndex] == triggerTokens[triggerIndex] {
                inputIndex += 1
                triggerIndex += 1
            } else if fillerTokens.contains(inputTokens[inputIndex]) {
                inputIndex += 1
            } else {
                return nil
            }
        }

        return inputIndex
    }

    func args(afterTokenCount tokenCount: Int) -> String {
        guard tokens.count > tokenCount else { return "" }
        return tokens.dropFirst(tokenCount).joined(separator: " ")
    }
}

nonisolated enum AliasNormalizer {
    static func normalize(_ text: String, aliases: [String: String]) -> String {
        var normalized = text
        let orderedAliases = aliases.sorted {
            if $0.key.count != $1.key.count {
                return $0.key.count > $1.key.count
            }
            return $0.key.localizedStandardCompare($1.key) == .orderedAscending
        }

        for (spoken, canonical) in orderedAliases {
            normalized = replacing(
                spoken: spoken,
                with: canonical,
                in: normalized
            )
        }

        return normalized
    }

    private static func replacing(spoken: String, with canonical: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: spoken)
        let pattern = "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"

        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: canonical
        )
    }
}

nonisolated enum CommandTemplateRenderer {
    static func render(
        template: String,
        text: String,
        normalized: String,
        args: String
    ) throws -> String {
        let extensionObject = Extension()
        registerFilters(on: extensionObject)
        let environment = Environment(extensions: [extensionObject])
        return try environment.renderTemplate(
            string: template,
            context: [
                "text": text,
                "normalized": normalized,
                "args": args
            ]
        )
    }

    private static func registerFilters(on extensionObject: Extension) {
        registerStringFilter("trim", on: extensionObject) {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        registerStringFilter("lowercase", on: extensionObject) { $0.lowercased() }
        registerStringFilter("uppercase", on: extensionObject) { $0.uppercased() }
        registerStringFilter("kebabcase", on: extensionObject, transform: CaseFormatter.kebabCase)
        registerStringFilter("snakecase", on: extensionObject, transform: CaseFormatter.snakeCase)
        registerStringFilter("pascalcase", on: extensionObject, transform: CaseFormatter.pascalCase)
        registerStringFilter("camelcase", on: extensionObject, transform: CaseFormatter.camelCase)
        registerStringFilter("gitBranch", on: extensionObject, transform: CaseFormatter.gitBranch)
    }

    private static func registerStringFilter(
        _ name: String,
        on extensionObject: Extension,
        transform: @escaping (String) -> String
    ) {
        extensionObject.registerFilter(name) { value in
            transform(stringValue(value))
        }
    }

    private static func stringValue(_ value: Any?) -> String {
        if let string = value as? String {
            return string
        }
        return value.map { String(describing: $0) } ?? ""
    }
}

nonisolated enum CaseFormatter {
    static func kebabCase(_ value: String) -> String {
        tokens(in: value).joined(separator: "-")
    }

    static func snakeCase(_ value: String) -> String {
        tokens(in: value).joined(separator: "_")
    }

    static func pascalCase(_ value: String) -> String {
        tokens(in: value)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
    }

    static func camelCase(_ value: String) -> String {
        let pascal = pascalCase(value)
        guard let first = pascal.first else { return "" }
        return first.lowercased() + pascal.dropFirst()
    }

    static func gitBranch(_ value: String) -> String {
        let latin =
            value
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)
            ?? value
        var branch = snakeCase(latin)
        branch = branch.replacingOccurrences(
            of: #"[^A-Za-z0-9_/-]+"#,
            with: "_",
            options: .regularExpression
        )
        branch = branch.replacingOccurrences(
            of: #"_+"#,
            with: "_",
            options: .regularExpression
        )
        branch = branch.replacingOccurrences(
            of: #"/+"#,
            with: "/",
            options: .regularExpression
        )
        branch = branch.replacingOccurrences(
            of: #"(^[\/_\-\s]+|[\/_\-\s]+$)"#,
            with: "",
            options: .regularExpression
        )
        return branch
    }

    private static func tokens(in value: String) -> [String] {
        let camelSpaced = value.replacingOccurrences(
            of: #"([a-z0-9])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        let separated = camelSpaced.replacingOccurrences(
            of: #"[^[:alnum:]]+"#,
            with: " ",
            options: .regularExpression
        )

        return
            separated
            .split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }
}

private struct CommandMatch {
    var command: DeveloperCommand
    var normalizedTrigger: String
    var triggerTokenCount: Int
    var args: String
}
