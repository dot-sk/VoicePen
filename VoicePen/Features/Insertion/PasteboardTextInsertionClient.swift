import AppKit
import Foundation

@MainActor
protocol TextPasteboard: AnyObject {
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    @discardableResult
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: TextPasteboard {}

@MainActor
protocol PasteCommandSender: AnyObject {
    func sendPasteCommand()
    func sendReturnCommand()
}

@MainActor
protocol DelayedActionScheduler: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void)
}

@MainActor
final class PasteboardTextInsertionClient: TextInsertionClient {
    private let pasteboard: TextPasteboard
    private let pasteCommandSender: PasteCommandSender
    private let scheduler: DelayedActionScheduler
    private let restoreDelay: TimeInterval

    init(
        pasteboard: TextPasteboard = NSPasteboard.general,
        pasteCommandSender: PasteCommandSender = CGEventPasteCommandSender(),
        scheduler: DelayedActionScheduler = MainQueueDelayedActionScheduler(),
        restoreDelay: TimeInterval
    ) {
        self.pasteboard = pasteboard
        self.pasteCommandSender = pasteCommandSender
        self.scheduler = scheduler
        self.restoreDelay = restoreDelay
    }

    func insert(_ text: String, action: TextInsertionAction = .paste) {
        let finalText = TextOutputNormalizer.normalize(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return }

        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        _ = pasteboard.setString(finalText, forType: .string)

        pasteCommandSender.sendPasteCommand()
        if action == .pasteAndSubmit {
            pasteCommandSender.sendReturnCommand()
        }

        scheduler.schedule(after: restoreDelay) { [weak self] in
            self?.restorePreviousPlainText(previousString)
        }
    }

    private func restorePreviousPlainText(_ previousString: String?) {
        pasteboard.clearContents()
        if let previousString {
            _ = pasteboard.setString(previousString, forType: .string)
        }
    }
}

@MainActor
final class CGEventPasteCommandSender: PasteCommandSender {
    func sendPasteCommand() {
        sendKeyCommand(keyCode: 9, flags: .maskCommand)
    }

    func sendReturnCommand() {
        sendKeyCommand(keyCode: 36, flags: [])
    }

    private func sendKeyCommand(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

final class MainQueueDelayedActionScheduler: DelayedActionScheduler {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                action()
            }
        }
    }
}
