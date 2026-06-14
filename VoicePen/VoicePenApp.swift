import AppKit
import Combine
import Foundation
import SwiftUI

@main
struct VoicePenApp: App {
    @NSApplicationDelegateAdaptor(VoicePenAppDelegate.self) private var appDelegate
    private let controller: AppController
    private let statusItemController: VoicePenStatusItemController
    @StateObject private var softwareUpdateController: SoftwareUpdateController
    @Environment(\.openWindow) private var openWindow

    init() {
        let controller = AppController.live()
        let statusItemController = VoicePenStatusItemController(controller: controller)
        self.controller = controller
        self.statusItemController = statusItemController
        _softwareUpdateController = StateObject(wrappedValue: SoftwareUpdateController())
        appDelegate.installStatusItemWhenReady {
            statusItemController.installStatusItemIfNeeded()
        }

        if !Self.isRunningTests {
            controller.start()
        }
    }

    var body: some Scene {
        Window("VoicePen", id: "voicepen-main") {
            VoicePenMainWindow(controller: controller)
                .onAppear {
                    configureStatusItemActions()
                    configureMeetingRecordingReminderClickAction()
                }
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Open Config File") {
                    controller.openUserConfigFile()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(after: .appInfo) {
                Button("Open VoicePen Window") {
                    openVoicePenWindow()
                }

                Button("Check for Updates...") {
                    softwareUpdateController.checkForUpdates()
                }
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func configureStatusItemActions() {
        statusItemController.setActions(
            openMainWindow: { openVoicePenWindow() },
            checkForUpdates: { softwareUpdateController.checkForUpdates() }
        )
    }

    private func configureMeetingRecordingReminderClickAction() {
        controller.setMeetingRecordingReminderClickAction { [weak controller] in
            controller?.requestMainWindowNavigation(.meetings)
            openVoicePenWindow()
        }
    }

    private func openVoicePenWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "voicepen-main")
    }
}

@MainActor
private final class VoicePenAppDelegate: NSObject, NSApplicationDelegate {
    private var installStatusItem: (@MainActor () -> Void)?
    private var didFinishLaunching = false

    func installStatusItemWhenReady(_ install: @escaping @MainActor () -> Void) {
        installStatusItem = install

        if didFinishLaunching {
            install()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        installStatusItem?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private final class VoicePenStatusItemController: NSObject, NSMenuDelegate {
    private let controller: AppController
    private let menu: NSMenu
    private var state: VoicePenStatusMenuModel
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var openMainWindow: () -> Void = {}
    private var checkForUpdates: () -> Void = {}

    init(controller: AppController) {
        self.controller = controller
        self.menu = NSMenu(title: "VoicePen")
        self.state = Self.makeStatusMenuModel(controller: controller)

        super.init()

        observeState()
    }

    func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        configureStatusItem(statusItem)
        updateStatusItemIcon()
    }

    func setActions(
        openMainWindow: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.openMainWindow = openMainWindow
        self.checkForUpdates = checkForUpdates
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshState()
        rebuildMenu()
    }

    private func configureStatusItem(_ statusItem: NSStatusItem) {
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.isVisible = true
        statusItem.menu = menu

        if let button = statusItem.button {
            button.toolTip = "VoicePen"
        }
    }

    private func observeState() {
        observeStateChange(controller.$appState)
        observeStateChange(controller.$dictationRuntimeState)
        observeStateChange(controller.$lastRawText)
        observeStateChange(controller.$lastFinalText)
        observeStateChange(controller.settingsStore.$hotkeyPreference)
        observeStateChange(controller.settingsStore.$transcriptionLanguage)
        observeStateChange(controller.historyStore.$entries)
    }

    private func observeStateChange<P: Publisher>(_ publisher: P) where P.Failure == Never {
        publisher
            .dropFirst()
            .sink { [weak self] _ in
                self?.refreshState()
            }
            .store(in: &cancellables)
    }

    private func refreshState() {
        let nextState = Self.makeStatusMenuModel(controller: controller)
        guard nextState != state else {
            return
        }
        state = nextState
        updateStatusItemIcon()
    }

    private static func makeStatusMenuModel(controller: AppController) -> VoicePenStatusMenuModel {
        VoicePenStatusMenuModel(
            appState: controller.appState.menuStatusAppState,
            showsStartDictation: controller.canStartDictation,
            showsStopDictation: controller.isDictationRecording,
            showsCancelTranscription: controller.canCancelDictationTranscription,
            showsStartMeetingRecording: controller.canStartMeetingRecording,
            showsStopMeetingRecording: controller.appState.isMeetingCaptureActive,
            hasLatestTranscriptionText: controller.hasLatestTranscriptionText,
            pushToTalkHotkeyHint: controller.settingsStore.hotkeyPreference.menuBarHint(),
            selectedTranscriptionLanguageCode: controller.settingsStore.transcriptionLanguage,
            languageOptions: availableLanguageOptions,
            isDictationStarting: controller.isDictationStarting,
            isDictationRecording: controller.isDictationRecording,
            isDictationTranscribing: controller.isDictationTranscribing
        )
    }

    private static let availableLanguageOptions = AppSettingsStore.supportedLanguages.map {
        VoicePenMenuLanguageOption(code: $0.code, name: $0.name)
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else {
            return
        }

        let image = makeTemplateStatusImage(
            systemSymbolName: state.menuBarSystemImage,
            accessibilityDescription: "VoicePen"
        )
        button.image = image
        button.contentTintColor = state.usesMeetingRecordingTint ? .systemRed : nil
    }

    private func makeTemplateStatusImage(
        systemSymbolName: String,
        accessibilityDescription: String
    ) -> NSImage? {
        let image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if state.showsDictationCommands {
            if state.showsStartDictation {
                addMenuItem(title: dictationCommandTitle("Start Dictation"), action: #selector(startDictation(_:)))
            }

            if state.showsStopDictation {
                addMenuItem(title: dictationCommandTitle("Stop Dictation"), action: #selector(stopDictation(_:)))
            }

            if state.showsCancelTranscription {
                addMenuItem(title: "Cancel Transcription", action: #selector(cancelTranscription(_:)))
            }
        }

        if state.showsMeetingCommands {
            if state.showsStartMeetingRecording {
                addMenuItem(title: "Start Meeting Recording", action: #selector(startMeetingRecording(_:)))
            }

            if state.showsStopMeetingRecording {
                addMenuItem(title: "Stop Meeting Recording", action: #selector(stopMeetingRecording(_:)))
                addMenuItem(title: "Cancel Meeting Recording", action: #selector(cancelMeetingRecording(_:)))
            }
        }

        menu.addItem(makeLanguageMenuItem())

        if state.hasLatestTranscriptionText {
            menu.addItem(.separator())
            addMenuItem(title: "Copy Last Dictation", action: #selector(copyLastTranscription(_:)))
            addMenuItem(title: "Insert Last Dictation", action: #selector(insertLastTranscription(_:)))
        }

        menu.addItem(.separator())
        addMenuItem(title: "Open VoicePen Window", action: #selector(openVoicePenWindow(_:)))
        addMenuItem(title: "Open Config File", action: #selector(openConfigFile(_:)))
        addMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates(_:)))
        menu.addItem(.separator())
        addMenuItem(title: "Quit", action: #selector(quit(_:)))
    }

    private func makeLanguageMenuItem() -> NSMenuItem {
        let parentItem = NSMenuItem(title: "Recognition Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu(title: "Recognition Language")
        languageMenu.autoenablesItems = false

        for language in state.languageOptions {
            let item = NSMenuItem(
                title: language.name,
                action: #selector(selectTranscriptionLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.code
            item.state = state.selectedTranscriptionLanguageCode == language.code ? .on : .off
            languageMenu.addItem(item)
        }

        parentItem.submenu = languageMenu
        return parentItem
    }

    @discardableResult
    private func addMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func dictationCommandTitle(_ title: String) -> String {
        "\(title) (\(state.pushToTalkHotkeyHint))"
    }

    @objc private func startDictation(_ sender: NSMenuItem) {
        controller.startRecording()
    }

    @objc private func stopDictation(_ sender: NSMenuItem) {
        controller.stopRecordingAndProcess()
    }

    @objc private func cancelTranscription(_ sender: NSMenuItem) {
        controller.cancelTranscription()
    }

    @objc private func startMeetingRecording(_ sender: NSMenuItem) {
        controller.startMeetingRecording()
    }

    @objc private func stopMeetingRecording(_ sender: NSMenuItem) {
        controller.stopMeetingRecording()
    }

    @objc private func cancelMeetingRecording(_ sender: NSMenuItem) {
        controller.cancelMeetingRecording()
    }

    @objc private func copyLastTranscription(_ sender: NSMenuItem) {
        controller.copyLastTranscription()
    }

    @objc private func insertLastTranscription(_ sender: NSMenuItem) {
        controller.retryInsertLastTranscription()
    }

    @objc private func openVoicePenWindow(_ sender: NSMenuItem) {
        openMainWindow()
    }

    @objc private func openConfigFile(_ sender: NSMenuItem) {
        controller.openUserConfigFile()
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        checkForUpdates()
    }

    @objc private func selectTranscriptionLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else {
            return
        }

        controller.updateTranscriptionLanguage(language)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}

private extension AppState {
    var menuStatusAppState: VoicePenMenuStatusAppState {
        switch self {
        case .starting:
            .starting
        case .ready:
            .ready
        case .meetingRecording:
            .meetingRecording
        case .meetingProcessing:
            .meetingProcessing
        case let .downloadingModel(progress):
            .downloadingModel(progress: progress)
        case let .preparingModel(message):
            .preparingModel(message)
        case .missingMicrophonePermission:
            .missingMicrophonePermission
        case .missingAccessibilityPermission:
            .missingAccessibilityPermission
        case .missingSystemAudioPermission:
            .missingSystemAudioPermission
        case .missingModel:
            .missingModel
        case let .error(message):
            .error(message)
        }
    }
}
