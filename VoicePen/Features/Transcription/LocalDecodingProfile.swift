import Foundation

nonisolated enum LocalDecodingProfile: String, CaseIterable, Identifiable, Sendable {
    case standard
    case maximumQuality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .maximumQuality:
            return "Maximum quality"
        }
    }
}
