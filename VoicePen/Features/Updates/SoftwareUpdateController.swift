import AppKit
import Combine
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

nonisolated enum SoftwareUpdateConfiguration {
    static let feedURLString = "https://dot-sk.github.io/VoicePen/appcast.xml"
    static let publicEDKey = "rN+1ra0hPvraHjMo7fKOWWHlnoaCPMeASVCoaPEoNJU="
    static let privateKeyEnvironmentName = "SPARKLE_PRIVATE_KEY"
}

@MainActor
final class SoftwareUpdateController: ObservableObject {
#if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController?
#endif

    init(startingUpdater: Bool = true) {
#if canImport(Sparkle)
        if Self.hasRequiredConfiguration {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: startingUpdater,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
#endif
    }

    func checkForUpdates() {
#if canImport(Sparkle)
        guard let updaterController else {
            showMissingConfigurationAlert()
            return
        }

        updaterController.checkForUpdates(nil)
#else
        showMissingConfigurationAlert()
#endif
    }

    private static var hasRequiredConfiguration: Bool {
        guard
            let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let publicEDKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else {
            return false
        }

        return !feedURL.isEmpty
            && !publicEDKey.isEmpty
            && publicEDKey == SoftwareUpdateConfiguration.publicEDKey
    }

    private func showMissingConfigurationAlert() {
        let alert = NSAlert()
        alert.messageText = "Updates are not configured for this build."
        alert.informativeText = "Install a release build of VoicePen to check for updates."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
