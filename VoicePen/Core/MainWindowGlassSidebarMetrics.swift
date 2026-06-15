import AppKit
import SwiftUI

enum MainWindowGlassSidebarMetrics {
    static let sidebarWidth: CGFloat = 82
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 10
    static let iconSpacing: CGFloat = 6

    static let islandTopInset: CGFloat = 8
    static let islandLeadingInset: CGFloat = 8
    static let islandBottomInset: CGFloat = 8
    static let islandTrailingGap: CGFloat = 8

    static let trafficLightLeadingInset: CGFloat = 19
    static let trafficLightTopInset: CGFloat = 20

    static var columnWidth: CGFloat {
        islandLeadingInset + sidebarWidth + islandTrailingGap
    }

    static let cornerRadius: CGFloat = 16
    static let windowCornerRadius: CGFloat = 20
    static let material: NSVisualEffectView.Material = .sidebar
    static let topContentInset: CGFloat = 96

    static func topPadding(for safeAreaTopInset: CGFloat) -> CGFloat {
        let contentInsetFromWindowTop = max(
            topContentInset,
            safeAreaTopInset + verticalPadding
        )
        return max(
            verticalPadding,
            contentInsetFromWindowTop - islandTopInset
        )
    }
}

struct MainWindowGlassSidebarBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
    }
}
