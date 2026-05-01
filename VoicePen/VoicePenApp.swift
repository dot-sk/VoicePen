import Foundation
import SwiftUI

@main
struct VoicePenApp: App {
    @StateObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow

    init() {
        let controller = AppController.live()
        _controller = StateObject(wrappedValue: controller)

        if !Self.isRunningTests {
            controller.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            VoicePenMenuView(controller: controller)
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
            }
        }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private struct VoicePenMenuView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Status: \(controller.appState.menuTitle)")

        if let errorMessage = controller.errorMessage {
            Text(errorMessage)
        }

        Divider()

        Button("Start Test Recording") {
            controller.startRecording()
        }
        .disabled(controller.appState == .recording || controller.appState == .transcribing)

        Button("Stop Test Recording") {
            controller.stopRecordingAndProcess()
        }
        .disabled(controller.appState != .recording)

        if controller.appState == .transcribing {
            Button("Cancel Transcription", role: .cancel) {
                controller.cancelTranscription()
            }
        }

        Button("Insert Test Text") {
            controller.insertTestText()
        }

        Divider()

        Button("Show Recording Overlay") {
            controller.showRecordingOverlay()
        }

        Button("Show Transcribing Overlay") {
            controller.showTranscribingOverlay()
        }

        Button("Show Done Overlay") {
            controller.showDoneOverlay()
        }

        Button("Show Error Overlay") {
            controller.showErrorOverlay()
        }

        Divider()

        Button("Open VoicePen Window") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "voicepen-main")
        }

        Button("Open Model Folder") {
            controller.openModelFolder()
        }

        Divider()

        Button("Request Microphone Permission") {
            controller.requestMicrophonePermission()
        }

        Button("Open Accessibility Settings") {
            controller.requestAccessibilityPermission()
        }

        Button("Refresh Permissions") {
            controller.refreshPermissionState()
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
