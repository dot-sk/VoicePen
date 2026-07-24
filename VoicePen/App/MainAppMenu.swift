import AppKit

@MainActor
enum MainAppMenu {
    static func install(
        controller: AppController,
        openMainWindow: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        let mainMenu = NSMenu()
        let target = MainAppMenuTarget.shared

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            withTitle: "About VoicePen",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())

        target.addItem(
            to: appMenu,
            withTitle: "Open VoicePen Window",
            action: #selector(MainAppMenuTarget.openMainWindow(_:)),
            keyEquivalent: ""
        )

        target.addItem(
            to: appMenu,
            withTitle: "Check for Updates...",
            action: #selector(MainAppMenuTarget.checkForUpdates(_:)),
            keyEquivalent: ""
        )

        target.addItem(
            to: appMenu,
            withTitle: "Open Config File",
            action: #selector(MainAppMenuTarget.openConfigFile(_:)),
            keyEquivalent: ","
        )

        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide VoicePen",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthersItem = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit VoicePen",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editMenuItem)
        editMenuItem.submenu = makeEditMenu()

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowMenuItem)
        windowMenuItem.submenu = makeWindowMenu()

        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu

        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu

        target.configure(
            controller: controller,
            openMainWindow: openMainWindow,
            checkForUpdates: checkForUpdates
        )
    }

    private static func makeEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return editMenu
    }

    private static func makeWindowMenu() -> NSMenu {
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        return windowMenu
    }
}

@MainActor
private final class MainAppMenuTarget: NSObject {
    static let shared = MainAppMenuTarget()

    private var controller: AppController?
    private var openMainWindow: () -> Void = {}
    private var checkForUpdates: () -> Void = {}

    func configure(
        controller: AppController,
        openMainWindow: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.controller = controller
        self.openMainWindow = openMainWindow
        self.checkForUpdates = checkForUpdates
    }

    @discardableResult
    func addItem(
        to menu: NSMenu,
        withTitle title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc func openMainWindow(_ sender: Any?) {
        openMainWindow()
    }

    @objc func openConfigFile(_ sender: Any?) {
        controller?.openUserConfigFile()
    }

    @objc func checkForUpdates(_ sender: Any?) {
        checkForUpdates()
    }
}
