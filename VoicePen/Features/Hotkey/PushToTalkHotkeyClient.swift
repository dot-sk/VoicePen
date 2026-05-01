import Foundation

protocol PushToTalkHotkeyClient: AnyObject {
    func install(
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) throws

    func uninstall()
}
