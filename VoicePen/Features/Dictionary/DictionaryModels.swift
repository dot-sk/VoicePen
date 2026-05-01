import Foundation

struct DictionaryFile: Codable, Equatable {
    var entries: [TermEntry]
}

struct TermEntry: Codable, Identifiable, Equatable {
    var id: String
    var canonical: String
    var variants: [String]
}
