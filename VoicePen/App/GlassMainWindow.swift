import AppKit

@MainActor
final class GlassMainWindow: NSWindow {
    private var layoutObserver: TrafficLightLayoutObserver?

    func installTrafficLightLayoutObserverIfNeeded() {
        guard layoutObserver == nil, let contentView else {
            return
        }

        let observer = TrafficLightLayoutObserver { [weak self] in
            self?.repositionTrafficLightsIfNeeded()
        }
        observer.frame = contentView.bounds
        observer.autoresizingMask = [.width, .height]
        contentView.addSubview(observer, positioned: .below, relativeTo: nil)
        layoutObserver = observer
        repositionTrafficLightsIfNeeded()
    }

    func repositionTrafficLightsIfNeeded() {
        guard !styleMask.contains(.fullScreen) else {
            return
        }

        guard
            let close = standardWindowButton(.closeButton),
            let miniaturize = standardWindowButton(.miniaturizeButton),
            let zoom = standardWindowButton(.zoomButton)
        else {
            return
        }

        let titleBarContainer = close.superview?.superview ?? close.superview
        guard let titleBarContainer, titleBarContainer.bounds.height > 0 else {
            return
        }

        let spacing = max(
            miniaturize.frame.minX - close.frame.minX,
            zoom.frame.minX - miniaturize.frame.minX
        )
        guard spacing > 0 else {
            return
        }

        let layout = MainWindowTrafficLightLayout.layout(
            buttonHeight: close.frame.height,
            buttonSpacing: spacing,
            leadingInset: MainWindowGlassSidebarMetrics.trafficLightLeadingInset,
            topInset: MainWindowGlassSidebarMetrics.trafficLightTopInset
        )

        var containerFrame = titleBarContainer.frame
        containerFrame.size.height = layout.containerHeight
        if let superview = titleBarContainer.superview {
            containerFrame.origin.y = superview.bounds.height - layout.containerHeight
        }
        titleBarContainer.frame = containerFrame

        close.setFrameOrigin(layout.buttonOrigins.close)
        miniaturize.setFrameOrigin(layout.buttonOrigins.miniaturize)
        zoom.setFrameOrigin(layout.buttonOrigins.zoom)
    }
}

@MainActor
private final class TrafficLightLayoutObserver: NSView {
    private let onLayout: () -> Void

    init(onLayout: @escaping () -> Void) {
        self.onLayout = onLayout
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        onLayout()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
