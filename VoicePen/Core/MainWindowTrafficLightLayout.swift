import CoreGraphics
import Foundation

struct MainWindowTrafficLightButtonOrigins: Equatable, Sendable {
    let close: CGPoint
    let miniaturize: CGPoint
    let zoom: CGPoint
}

struct MainWindowTrafficLightContainerLayout: Equatable, Sendable {
    let containerHeight: CGFloat
    let buttonOrigins: MainWindowTrafficLightButtonOrigins
}

enum MainWindowTrafficLightLayout {
    static func layout(
        buttonHeight: CGFloat,
        buttonSpacing: CGFloat,
        leadingInset: CGFloat,
        topInset: CGFloat
    ) -> MainWindowTrafficLightContainerLayout {
        let containerHeight = buttonHeight + (topInset * 2)
        let originY = containerHeight - topInset - buttonHeight
        let closeX = leadingInset
        let miniaturizeX = closeX + buttonSpacing
        let zoomX = closeX + (buttonSpacing * 2)

        return MainWindowTrafficLightContainerLayout(
            containerHeight: containerHeight,
            buttonOrigins: MainWindowTrafficLightButtonOrigins(
                close: CGPoint(x: closeX, y: originY),
                miniaturize: CGPoint(x: miniaturizeX, y: originY),
                zoom: CGPoint(x: zoomX, y: originY)
            )
        )
    }
}
