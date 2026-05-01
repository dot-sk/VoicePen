import AppKit
import Foundation

protocol TextPasteboard: AnyObject {
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    @discardableResult
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: TextPasteboard {}

protocol PasteCommandSender: AnyObject {
    func sendPasteCommand()
}

protocol DelayedActionScheduler: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void)
}

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

    func insert(_ text: String) {
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return }

        let previousString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        _ = pasteboard.setString(finalText, forType: .string)

        pasteCommandSender.sendPasteCommand()

        scheduler.schedule(after: restoreDelay) { [pasteboard] in
            pasteboard.clearContents()
            if let previousString {
                _ = pasteboard.setString(previousString, forType: .string)
            }
        }
    }
}

final class CGEventPasteCommandSender: PasteCommandSender {
    func sendPasteCommand() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCodeForV: CGKeyCode = 9

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

final class MainQueueDelayedActionScheduler: DelayedActionScheduler {
    func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
}
