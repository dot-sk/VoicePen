import Foundation

@MainActor
final class HotkeyPressStateTracker {
    private let cooldown: TimeInterval
    private let now: () -> Date
    private var isPressed = false
    private var lastReleaseDate: Date?

    init(
        cooldown: TimeInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.cooldown = cooldown
        self.now = now
    }

    func keyDown(onStart: () -> Void) {
        guard !isPressed else { return }
        if let lastReleaseDate,
            now().timeIntervalSince(lastReleaseDate) < cooldown
        {
            return
        }

        isPressed = true
        onStart()
    }

    func keyUp(onStop: () -> Void) {
        guard isPressed else { return }
        isPressed = false
        lastReleaseDate = now()
        onStop()
    }

    func cancel() {
        isPressed = false
        lastReleaseDate = now()
    }
}
