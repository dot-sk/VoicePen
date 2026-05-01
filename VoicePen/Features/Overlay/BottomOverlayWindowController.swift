import AppKit
import SwiftUI

@MainActor
final class BottomOverlayWindowController: OverlayPresenter {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<VoicePenOverlayView>?
    private let viewModel = OverlayViewModel()
    private var hideToken = UUID()
    var onCancelTranscription: (() -> Void)? {
        get { viewModel.onCancelTranscription }
        set { viewModel.onCancelTranscription = newValue }
    }

    func show(_ state: OverlayState) {
        update(state)
    }

    func update(_ state: OverlayState) {
        hideToken = UUID()
        let shouldAnimateIn = panel?.isVisible != true || panel?.alphaValue == 0

        ensurePanel()
        viewModel.state = state
        positionPanel()
        panel?.ignoresMouseEvents = !state.isInteractive

        guard shouldAnimateIn else { return }

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel?.animator().alphaValue = 1
        }
    }

    func hide(after delay: TimeInterval) {
        let token = UUID()
        hideToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.hideToken == token else { return }
            guard let panel = self.panel else { return }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    self.viewModel.state = .hidden
                }
            }
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let hostingController = NSHostingController(rootView: VoicePenOverlayView(viewModel: viewModel))
        hostingController.view.frame = NSRect(origin: .zero, size: Self.panelSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: hostingController.view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        self.panel = panel
        self.hostingController = hostingController
    }

    private func positionPanel() {
        guard let panel else { return }

        let screen = screenForOverlay()
        let frame = screen.visibleFrame
        let size = Self.panelSize
        let x = frame.midX - size.width / 2
        let y = frame.minY + 28

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    private func screenForOverlay() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static let panelSize = NSSize(width: 360, height: 128)
}
