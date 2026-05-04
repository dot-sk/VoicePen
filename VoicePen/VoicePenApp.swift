import Foundation
import SwiftUI

@main
struct VoicePenApp: App {
    @StateObject private var controller: AppController
    @StateObject private var softwareUpdateController: SoftwareUpdateController
    @Environment(\.openWindow) private var openWindow

    init() {
        let controller = AppController.live()
        _controller = StateObject(wrappedValue: controller)
        _softwareUpdateController = StateObject(wrappedValue: SoftwareUpdateController())

        if !Self.isRunningTests {
            controller.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            VoicePenMenuView(controller: controller, softwareUpdateController: softwareUpdateController)
        } label: {
            Label("VoicePen", systemImage: controller.menuBarSystemImage)
        }
        .menuBarExtraStyle(.menu)

        Window("VoicePen", id: "voicepen-main") {
            VoicePenMainWindow(controller: controller)
        }
        .windowResizability(.contentMinSize)
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
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "voicepen-main")
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
}

private struct VoicePenMenuView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var softwareUpdateController: SoftwareUpdateController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if showsDictationCommands {
            if controller.appState == .ready {
                Button(dictationCommandTitle("Start Dictation")) {
                    controller.startRecording()
                }
            }

            if controller.appState == .recording {
                Button(dictationCommandTitle("Stop Dictation")) {
                    controller.stopRecordingAndProcess()
                }
            }

            if controller.appState == .transcribing {
                Button("Cancel Transcription", role: .cancel) {
                    controller.cancelTranscription()
                }
            }
        }

        if showsDictationCommands && controller.hasLatestTranscriptionText {
            Divider()
        }

        if controller.hasLatestTranscriptionText {
            Button("Copy Last Transcription") {
                controller.copyLastTranscription()
            }

            Button("Retry Insert Last Text") {
                controller.retryInsertLastTranscription()
            }
        }

        if showsDictationCommands || controller.hasLatestTranscriptionText {
            Divider()
        }

        Button("Open VoicePen Window") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "voicepen-main")
        }

        Button("Open Config File") {
            controller.openUserConfigFile()
        }

        Button("Check for Updates...") {
            softwareUpdateController.checkForUpdates()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var showsDictationCommands: Bool {
        controller.appState == .ready
            || controller.appState == .recording
            || controller.appState == .transcribing
    }

    private var pushToTalkHotkeyHint: String {
        controller.settingsStore.hotkeyPreference.menuBarHint()
    }

    private func dictationCommandTitle(_ title: String) -> String {
        "\(title) (\(pushToTalkHotkeyHint))"
    }
}
