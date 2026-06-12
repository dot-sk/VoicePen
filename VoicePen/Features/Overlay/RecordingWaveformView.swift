import SwiftUI

struct ListeningMicrophoneIndicatorView: View {
    let levelProvider: @Sendable () -> Double?

    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemPink).opacity(0.64),
                            Color(nsColor: .systemRed).opacity(0.96),
                            Color(nsColor: .systemPink).opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 26, height: 54)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(alignment: .topLeading) {
                    Capsule()
                        .fill(Color(nsColor: .systemPink).opacity(0.34))
                        .frame(width: 7, height: 28)
                        .blur(radius: 3)
                        .offset(x: 6, y: 6)
                }
                .overlay(alignment: .bottomTrailing) {
                    Capsule()
                        .fill(Color(nsColor: .systemPink).opacity(0.35))
                        .frame(width: 12, height: 22)
                        .blur(radius: 5)
                        .offset(x: -4, y: -5)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                        .padding(0.5)
                }
                .overlay {
                    RecordingLevelBarLayerView(levelProvider: levelProvider)
                        .frame(width: 26, height: 54)
                }
        }
        .frame(width: 112, height: 88)
        .accessibilityLabel("VoicePen is listening")
    }
}

private struct RecordingLevelBarLayerView: NSViewRepresentable {
    let levelProvider: @Sendable () -> Double?

    func makeCoordinator() -> Coordinator {
        Coordinator(levelProvider: levelProvider)
    }

    func makeNSView(context: Context) -> RecordingLevelBarNSView {
        let view = RecordingLevelBarNSView()
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ nsView: RecordingLevelBarNSView, context: Context) {
        context.coordinator.levelProvider = levelProvider
        context.coordinator.attach(nsView)
    }

    @MainActor
    final class Coordinator {
        var levelProvider: @Sendable () -> Double?
        private weak var view: RecordingLevelBarNSView?

        init(levelProvider: @escaping @Sendable () -> Double?) {
            self.levelProvider = levelProvider
        }

        func attach(_ view: RecordingLevelBarNSView) {
            self.view = view
            view.levelProvider = levelProvider
            view.startAnimating()
        }
    }
}

@MainActor
private final class RecordingLevelBarNSView: NSView {
    private let barLayer = CALayer()
    private var displayLink: CADisplayLink?
    private var displayedLevel = fallbackLevel
    private var lastFrameTime: CFTimeInterval?
    var levelProvider: (@Sendable () -> Double?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func layout() {
        super.layout()
        updateBarGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimating()
        } else {
            startAnimating()
        }
    }

    func startAnimating() {
        guard displayLink == nil, window != nil else { return }

        let displayLink = displayLink(target: self, selector: #selector(displayFrame(_:)))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTime = nil
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = false

        barLayer.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        barLayer.cornerRadius = 1.5
        barLayer.shadowColor = NSColor.white.cgColor
        barLayer.shadowOpacity = 0.24
        barLayer.shadowRadius = 3
        barLayer.shadowOffset = .zero
        layer?.addSublayer(barLayer)
    }

    @objc
    private func displayFrame(_ displayLink: CADisplayLink) {
        let previousFrameTime = lastFrameTime ?? (displayLink.timestamp - displayLink.duration)
        let measuredDelta = displayLink.timestamp - previousFrameTime
        let deltaTime = max(
            1.0 / 240.0,
            min(1.0 / 30.0, measuredDelta > 0 ? measuredDelta : displayLink.duration)
        )
        lastFrameTime = displayLink.timestamp

        let targetLevel = min(1, max(0, levelProvider?() ?? Self.fallbackLevel))
        let timeConstant = Self.levelSmoothingTimeConstant
        let response = 1 - exp(-deltaTime / timeConstant)
        displayedLevel += (targetLevel - displayedLevel) * response

        if abs(displayedLevel - targetLevel) < 0.002 {
            displayedLevel = targetLevel
        }

        let barHeight = Self.barHeight(for: displayedLevel, trembleTime: displayLink.timestamp)
        updateBarTransform(height: barHeight)
    }

    private func updateBarGeometry() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayer.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.maximumBarHeight)
        barLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let barHeight = Self.barHeight(for: displayedLevel)
        applyBarTransform(height: barHeight)
        CATransaction.commit()
    }

    private func updateBarTransform(height: CGFloat? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyBarTransform(height: height)
        CATransaction.commit()
    }

    private static func tremble(for level: Double, at trembleTime: CFTimeInterval) -> CGFloat {
        let trembleIntensity = min(1, max(0, (level - 0.12) / 0.88))
        let tremble = sin(trembleTime * 48) * 2.2 + sin(trembleTime * 83) * 1.1
        return CGFloat(tremble * trembleIntensity)
    }

    private static func barHeight(for level: Double, trembleTime: CFTimeInterval? = nil) -> CGFloat {
        let baseHeight = Self.minimumBarHeight + CGFloat(level) * Self.barTravel
        guard let trembleTime else {
            return baseHeight
        }

        let liveHeight = baseHeight + tremble(for: level, at: trembleTime)
        return min(Self.maximumBarHeight, max(Self.minimumBarHeight, liveHeight))
    }

    private func applyBarTransform(height: CGFloat? = nil) {
        let height = min(Self.maximumBarHeight, max(Self.minimumBarHeight, height ?? Self.barHeight(for: displayedLevel)))
        let scaleY = height / Self.maximumBarHeight
        barLayer.transform = CATransform3DMakeScale(1, scaleY, 1)
    }

    private static let fallbackLevel = 0.18
    private static let barWidth: CGFloat = 3.2
    private static let minimumBarHeight: CGFloat = 12
    private static let maximumBarHeight: CGFloat = 48
    private static let barTravel = maximumBarHeight - minimumBarHeight
    private static let levelSmoothingTimeConstant = 0.045
}

struct RecordingWaveformView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .frame(
                        width: 4,
                        height: animate ? CGFloat(14 + index * 3) : CGFloat(8 + index)
                    )
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(index) * 0.08),
                        value: animate
                    )
            }
        }
        .frame(height: 30)
        .onAppear {
            animate = true
        }
    }
}
