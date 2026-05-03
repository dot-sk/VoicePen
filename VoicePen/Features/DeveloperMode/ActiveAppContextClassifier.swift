import Foundation

nonisolated enum ActiveAppContextClassifier {
    static func context(for app: ActiveApplicationInfo?) -> ActiveAppContext {
        guard let app else { return .plain }

        let bundleID = app.bundleIdentifier?.lowercased() ?? ""
        let name = app.localizedName?.lowercased() ?? ""

        if isTerminal(bundleID: bundleID, name: name) {
            return .terminal
        }

        if isDeveloperApp(bundleID: bundleID, name: name) {
            return .developer
        }

        return .plain
    }

    static func resolve(
        uiOverride: DeveloperMode?,
        configMode: DeveloperMode,
        activeApplication: ActiveApplicationInfo?
    ) -> ActiveAppContext {
        switch uiOverride ?? configMode {
        case .plain:
            return .plain
        case .developer:
            return .developer
        case .terminal:
            return .terminal
        case .auto:
            return context(for: activeApplication)
        }
    }

    private static func isTerminal(bundleID: String, name: String) -> Bool {
        let terminalBundleIDs = [
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "dev.warp.warp-stable",
            "dev.warp.warp",
            "com.mitchellh.ghostty"
        ]

        if terminalBundleIDs.contains(bundleID) {
            return true
        }

        let terminalNames = ["terminal", "iterm", "iterm2", "warp", "ghostty"]
        if terminalNames.contains(where: { name == $0 || name.contains($0) }) {
            return true
        }

        return bundleID == "com.microsoft.vscode" && name.contains("terminal")
    }

    private static func isDeveloperApp(bundleID: String, name: String) -> Bool {
        if bundleID == "com.apple.dt.xcode" {
            return true
        }

        if bundleID == "com.microsoft.vscode"
            || bundleID == "com.todesktop.230313mzl4w4u92"
            || bundleID.hasPrefix("com.jetbrains.")
        {
            return true
        }

        let developerNames = [
            "xcode",
            "visual studio code",
            "vscode",
            "cursor",
            "intellij",
            "webstorm",
            "pycharm",
            "goland",
            "rubymine",
            "clion",
            "phpstorm",
            "rider",
            "android studio"
        ]
        return developerNames.contains { name.contains($0) }
    }
}
