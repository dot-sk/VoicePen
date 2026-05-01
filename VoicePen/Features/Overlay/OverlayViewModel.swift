import Combine
import Foundation

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    var onCancelTranscription: (() -> Void)?
}
