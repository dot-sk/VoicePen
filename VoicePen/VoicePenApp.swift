import Combine
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
            VoicePenMenuBarLabel(controller: controller)
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

private struct VoicePenMenuBarLabel: View {
    @ObservedObject var controller: AppController
    @State private var meetingPulseVisible = true

    private let pulseTimer = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Label("VoicePen", systemImage: systemImage)
            .foregroundStyle(controller.appState == .meetingRecording ? .red : .primary)
            .id("\(controller.appState.menuTitle)-\(systemImage)-\(meetingPulseVisible)")
            .onReceive(pulseTimer) { _ in
                guard controller.appState == .meetingRecording else {
                    meetingPulseVisible = true
                    return
                }

                meetingPulseVisible.toggle()
            }
            .onChange(of: controller.appState) { _, newState in
                if newState != .meetingRecording {
                    meetingPulseVisible = true
                }
            }
    }

    private var systemImage: String {
        guard controller.appState == .meetingRecording else {
            return controller.menuBarSystemImage
        }

        return meetingPulseVisible ? "record.circle.fill" : "record.circle"
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

        if showsMeetingCommands {
            if controller.appState.canStartMeetingRecording {
                Button("Start Meeting Recording") {
                    controller.startMeetingRecording()
                }
            }

            if controller.appState.isMeetingCaptureActive {
                Button("Stop Meeting Recording") {
                    controller.stopMeetingRecording()
                }

                Button("Cancel Meeting Recording", role: .cancel) {
                    controller.cancelMeetingRecording()
                }
            }
        }

        if (showsDictationCommands || showsMeetingCommands) && controller.hasLatestTranscriptionText {
            Divider()
        }

        if controller.hasLatestTranscriptionText {
            Button("Copy Last Dictation") {
                controller.copyLastTranscription()
            }

            Button("Insert Last Dictation") {
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

    private var showsMeetingCommands: Bool {
        controller.appState.canStartMeetingRecording || controller.appState.isMeetingCaptureActive
    }

    private var pushToTalkHotkeyHint: String {
        controller.settingsStore.hotkeyPreference.menuBarHint()
    }

    private func dictationCommandTitle(_ title: String) -> String {
        "\(title) (\(pushToTalkHotkeyHint))"
    }
}
