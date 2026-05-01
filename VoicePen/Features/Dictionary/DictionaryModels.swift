import Foundation

nonisolated struct DictionaryFile: Codable, Equatable, Sendable {
    var entries: [TermEntry]
}

nonisolated struct TermEntry: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var canonical: String
    var variants: [String]
}
