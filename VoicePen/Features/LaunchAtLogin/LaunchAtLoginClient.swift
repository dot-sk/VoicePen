import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginClient: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ isEnabled: Bool) throws
}

@MainActor
final class LiveLaunchAtLoginClient: LaunchAtLoginClient {
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ isEnabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }

        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class NoOpLaunchAtLoginClient: LaunchAtLoginClient {
    private(set) var isEnabled = false

    func setEnabled(_ isEnabled: Bool) throws {
        self.isEnabled = isEnabled
    }
}
