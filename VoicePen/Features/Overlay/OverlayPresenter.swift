import Foundation

protocol OverlayPresenter: AnyObject {
    @MainActor func show(_ state: OverlayState)
    @MainActor func update(_ state: OverlayState)
    @MainActor func hide(after delay: TimeInterval)
}
