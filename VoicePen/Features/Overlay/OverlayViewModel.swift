import Combine
import Foundation

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    let recordingLevelProvider: @Sendable () -> Double?
    var onCancelTranscription: (() -> Void)?

    init(recordingLevelProvider: @escaping @Sendable () -> Double? = { nil }) {
        self.recordingLevelProvider = recordingLevelProvider
    }

    func apply(_ state: OverlayState) {
        self.state = state
    }
}
