import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let window: GlassMainWindow

    init(controller: AppController) {
        let contentRect = NSRect(x: 0, y: 0, width: 920, height: 560)
        window = GlassMainWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VoicePen"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 920, height: 560)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentViewController = NSHostingController(
            rootView: VoicePenMainWindow(controller: controller)
        )

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = MainWindowGlassSidebarMetrics.windowCornerRadius
            contentView.layer?.masksToBounds = true
        }

        super.init()

        window.delegate = self
        window.center()
        window.installTrafficLightLayoutObserverIfNeeded()
    }

    func show() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.repositionTrafficLightsIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func windowDidResize(_ notification: Notification) {
        window.repositionTrafficLightsIfNeeded()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        window.repositionTrafficLightsIfNeeded()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window.repositionTrafficLightsIfNeeded()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window.repositionTrafficLightsIfNeeded()
    }
}
