import Foundation

nonisolated enum DictionaryCSVImporter {
    static func parse(_ text: String) throws -> [TermEntry] {
        var builder = DictionaryCSVImportBuilder()
        var parser = CSVStreamingParser { row in
            try builder.append(row)
        }
        try parser.consume(text)
        try parser.finish()
        return try builder.validatedEntries()
    }

    static func parse(fileURL: URL) throws -> [TermEntry] {
        guard let stream = InputStream(url: fileURL) else {
            throw DictionaryCSVImporterError.unableToOpenFile
        }

        stream.open()
        defer { stream.close() }

        var builder = DictionaryCSVImportBuilder()
        var parser = CSVStreamingParser { row in
            try builder.append(row)
        }
        var pendingData = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                throw stream.streamError ?? DictionaryCSVImporterError.readFailed
            }
            if readCount == 0 { break }

            pendingData.append(buffer, count: readCount)
            if let text = String(data: pendingData, encoding: .utf8) {
                try parser.consume(text)
                pendingData.removeAll(keepingCapacity: true)
            }
        }

        if !pendingData.isEmpty {
            guard let text = String(data: pendingData, encoding: .utf8) else {
                throw DictionaryCSVImporterError.invalidUTF8
            }
            try parser.consume(text)
        }

        try parser.finish()
        return try builder.validatedEntries()
    }
}

nonisolated private struct CSVStreamingParser {
    private var row: [String] = []
    private var field = ""
    private var isInsideQuotes = false
    private var pendingQuoteInQuotedField = false
    private var shouldSkipNextLineFeed = false
    private let onRow: ([String]) throws -> Void

    init(onRow: @escaping ([String]) throws -> Void) {
        self.onRow = onRow
    }

    mutating func consume(_ text: String) throws {
        for character in text {
            if pendingQuoteInQuotedField {
                if character == "\"" {
                    field.append("\"")
                    pendingQuoteInQuotedField = false
                    continue
                }

                isInsideQuotes = false
                pendingQuoteInQuotedField = false
            }

            if shouldSkipNextLineFeed {
                shouldSkipNextLineFeed = false
                if character == "\n" {
                    continue
                }
            }

            if character == "\"" {
                if isInsideQuotes {
                    pendingQuoteInQuotedField = true
                } else if field.isEmpty {
                    isInsideQuotes = true
                } else {
                    field.append("\"")
                }
            } else if character == ",", !isInsideQuotes {
                appendField()
            } else if character.isNewline, !isInsideQuotes {
                try appendRow()
                if character == "\r" {
                    shouldSkipNextLineFeed = true
                }
            } else {
                field.append(character)
            }
        }
    }

    mutating func finish() throws {
        if pendingQuoteInQuotedField {
            pendingQuoteInQuotedField = false
            isInsideQuotes = false
        }

        if isInsideQuotes {
            throw DictionaryCSVImporterError.unclosedQuote
        }

        if !field.isEmpty || !row.isEmpty {
            try appendRow()
        }
    }

    private mutating func appendField() {
        row.append(cleanField(field))
        field = ""
    }

    private mutating func appendRow() throws {
        appendField()
        try onRow(row)
        row = []
    }

    private func cleanField(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated private struct DictionaryCSVImportBuilder {
    private var hasProcessedHeaderDecision = false
    private var parsedEntries: [TermEntry] = []
    private var usedIDs = Set<String>()

    mutating func append(_ rawRow: [String]) throws {
        let row = rawRow
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard row.contains(where: { !$0.isEmpty }) else { return }

        if !hasProcessedHeaderDecision {
            hasProcessedHeaderDecision = true
            if Self.isHeader(row) {
                return
            }
        }

        let canonical = row.first ?? ""
        let variants = Self.uniquedCaseInsensitive(
            row.dropFirst()
                .flatMap(Self.splitVariants)
                .filter { $0 != canonical }
        )

        let id = Self.uniqueID(for: canonical, usedIDs: &usedIDs)
        parsedEntries.append(
            TermEntry(
                id: id,
                canonical: canonical,
                variants: variants
            )
        )
    }

    func validatedEntries() throws -> [TermEntry] {
        do {
            try DictionaryMerger.validateImportedEntries(parsedEntries)
        } catch DictionaryImportValidationError.emptyImport {
            throw DictionaryCSVImporterError.emptyFile
        } catch DictionaryImportValidationError.missingRequiredFields {
            throw DictionaryCSVImporterError.missingRequiredFields
        }

        return parsedEntries
    }

    private static func isHeader(_ row: [String]?) -> Bool {
        guard let row, let first = row.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return ["canonical", "term", "каноническая форма", "термин"].contains(first)
    }

    private static func splitVariants(_ field: String) -> [String] {
        field
            .components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func uniqueID(for canonical: String, usedIDs: inout Set<String>) -> String {
        let base = canonical
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9а-яё]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let fallback = base.isEmpty ? UUID().uuidString : base

        var candidate = fallback
        var suffix = 2
        while usedIDs.contains(candidate) {
            candidate = "\(fallback)-\(suffix)"
            suffix += 1
        }

        usedIDs.insert(candidate)
        return candidate
    }

    private static func uniquedCaseInsensitive(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }

        return result
    }
}

enum DictionaryCSVImporterError: LocalizedError, Equatable {
    case emptyFile
    case invalidUTF8
    case missingRequiredFields
    case readFailed
    case unableToOpenFile
    case unclosedQuote

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The CSV file does not contain dictionary terms."
        case .invalidUTF8:
            return "The CSV file must be saved as UTF-8."
        case .missingRequiredFields:
            return "Every imported dictionary term must include a canonical value and at least one variant."
        case .readFailed:
            return "VoicePen could not read the CSV file."
        case .unableToOpenFile:
            return "VoicePen could not open the CSV file."
        case .unclosedQuote:
            return "The CSV file contains an unclosed quoted field."
        }
    }
}
