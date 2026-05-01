import Foundation

enum SpeechPreprocessingMode: String, CaseIterable, Identifiable, Equatable {
    case off
    case slower09
    case slower08

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .slower09:
            return "Slightly slower, 0.9x"
        case .slower08:
            return "Slower, 0.8x"
        }
    }

    var speedRate: Double {
        switch self {
        case .off:
            return 1.0
        case .slower09:
            return 0.9
        case .slower08:
            return 0.8
        }
    }
}
