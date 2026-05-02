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
            CommandGroup(after: .appInfo) {
                Button("Open VoicePen Window") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "voicepen-main")
                }
                .keyboardShortcut(",", modifiers: [.command])

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
        Text("Status: \(controller.appState.menuTitle)")

        if let errorMessage = controller.errorMessage {
            Text(errorMessage)
        }

        Divider()

        Button("Start Dictation") {
            controller.startRecording()
        }
        .disabled(controller.appState != .ready)

        Button("Stop Dictation") {
            controller.stopRecordingAndProcess()
        }
        .disabled(controller.appState != .recording)

        if controller.appState == .transcribing {
            Button("Cancel Transcription", role: .cancel) {
                controller.cancelTranscription()
            }
        }

        Divider()

        Button("Copy Last Transcription") {
            controller.copyLastTranscription()
        }
        .disabled(!controller.hasLatestTranscriptionText)

        Button("Retry Insert Last Text") {
            controller.retryInsertLastTranscription()
        }
        .disabled(!controller.hasLatestTranscriptionText)

        Divider()

        Button("Open VoicePen Window") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "voicepen-main")
        }

        Button("Check for Updates...") {
            softwareUpdateController.checkForUpdates()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
