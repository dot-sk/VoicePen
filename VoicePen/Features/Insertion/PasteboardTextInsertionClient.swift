import AppKit
import Foundation

@MainActor
protocol TextPasteboard: AnyObject {
    var pasteboardItems: [NSPasteboardItem]? { get }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    @discardableResult
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
    @discardableResult
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
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

        let previousSnapshot = PasteboardSnapshot(pasteboardItems: pasteboard.pasteboardItems)
        pasteboard.clearContents()
        _ = pasteboard.setString(finalText, forType: .string)

        pasteCommandSender.sendPasteCommand()
        if action == .pasteAndSubmit {
            pasteCommandSender.sendReturnCommand()
        }

        scheduler.schedule(after: restoreDelay) { [weak self] in
            self?.restorePreviousPasteboard(previousSnapshot)
        }
    }

    private func restorePreviousPasteboard(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        let restoredItems = snapshot.restoredItems()
        if !restoredItems.isEmpty {
            _ = pasteboard.writeObjects(restoredItems)
        }
    }
}

private struct PasteboardSnapshot: Sendable {
    private struct Item: Sendable {
        let representations: [Representation]
    }

    private struct Representation: Sendable {
        let typeRawValue: String
        let data: Data
    }

    private let items: [Item]

    init(pasteboardItems: [NSPasteboardItem]?) {
        items =
            pasteboardItems?.compactMap { item in
                let representations = item.types.compactMap { type -> Representation? in
                    guard let data = item.data(forType: type) else { return nil }
                    return Representation(typeRawValue: type.rawValue, data: data)
                }

                guard !representations.isEmpty else { return nil }
                return Item(representations: representations)
            } ?? []
    }

    func restoredItems() -> [NSPasteboardItem] {
        items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for representation in item.representations {
                _ = pasteboardItem.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.typeRawValue)
                )
            }
            return pasteboardItem
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
