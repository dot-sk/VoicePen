import Foundation
import XCTest

@testable import VoicePen

@MainActor
final class VoicePenStatusItemControllerTests: XCTestCase {
    func testSnapshotReturnsToReadyWithoutOpeningMenu() async {
        await withStatusItemController { controller, statusItem in
            let readyState = statusItem.state

            for _ in 0..<3 {
                controller.appState = .preparingModel("test")
                let processingState = VoicePenStatusItemController(controller: controller).state
                await finishPendingStatusUpdates()
                XCTAssertEqual(statusItem.state, processingState)

                controller.appState = .ready
                await finishPendingStatusUpdates()
                XCTAssertEqual(statusItem.state, readyState)
            }
        }
    }

    func testSnapshotReflectsWarningAndMeetingStatesWithoutOpeningMenu() async {
        await withStatusItemController { controller, statusItem in
            let finalStates: [AppState] = [
                .error("test"), .missingModel, .meetingRecording, .meetingProcessing
            ]

            for finalState in finalStates {
                controller.appState = .preparingModel("test")
                await finishPendingStatusUpdates()

                controller.appState = finalState
                let expectedState = VoicePenStatusItemController(controller: controller).state
                await finishPendingStatusUpdates()
                XCTAssertEqual(statusItem.state, expectedState)
            }
        }
    }

    func testRapidChangesRefreshToLatestCommittedSnapshot() async {
        await withStatusItemController { controller, statusItem in
            controller.appState = .preparingModel("test")
            controller.appState = .meetingRecording
            controller.appState = .meetingProcessing
            controller.appState = .ready
            controller.lastFinalText = "Dictation result"
            let expectedState = VoicePenStatusItemController(controller: controller).state

            await finishPendingStatusUpdates()

            XCTAssertEqual(statusItem.state, expectedState)
            XCTAssertTrue(statusItem.state.showsStartDictation)
            XCTAssertTrue(statusItem.state.hasLatestTranscriptionText)
        }
    }

    private func withStatusItemController(
        _ body: @MainActor (AppController, VoicePenStatusItemController) async -> Void
    ) async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicepen-status-item-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = AppController.live(
            paths: AppPaths(applicationSupportDirectory: root, temporaryDirectory: root),
            userConfigStore: UserConfigStore(configURL: root.appendingPathComponent("config.toml"))
        )
        controller.appState = .ready
        let statusItem = VoicePenStatusItemController(controller: controller)

        await body(controller, statusItem)
    }

    private func finishPendingStatusUpdates() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
