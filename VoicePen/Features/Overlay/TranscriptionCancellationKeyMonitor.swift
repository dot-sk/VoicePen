import AppKit

@MainActor
protocol TranscriptionCancellationKeyMonitor {
    func install(onCancel: @escaping @MainActor () -> Void)
    func uninstall()
}

@MainActor
final class LiveTranscriptionCancellationKeyMonitor: TranscriptionCancellationKeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func install(onCancel: @escaping @MainActor () -> Void) {
        uninstall()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == Self.escapeKeyCode else { return }
            Task { @MainActor in
                onCancel()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            Task { @MainActor in
                onCancel()
            }
            return nil
        }
    }

    func uninstall() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }

        globalMonitor = nil
        localMonitor = nil
    }

    private static let escapeKeyCode: UInt16 = 53
}
