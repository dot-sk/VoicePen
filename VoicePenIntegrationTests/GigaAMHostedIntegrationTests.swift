import AppKit
import CryptoKit
import Darwin
import SwiftUI
import XCTest

@testable import VoicePen

final class GigaAMHostedIntegrationTests: XCTestCase {
    @MainActor
    func testBundledGigaAMModelCanBeSelected() throws {
        let manifest = try LocalModelManifestStore().loadManifest()
        let model = try XCTUnwrap(manifest.compatibleModels.first { $0.backendKind == .gigaAM })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voicepen-bundled-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = AppController.live(
            paths: AppPaths(applicationSupportDirectory: root),
            modelManifest: manifest,
            userConfigStore: UserConfigStore(configURL: root.appendingPathComponent("config.toml")))
        let settingsView = NSHostingController(rootView: ModelSettingsView(controller: controller, settingsStore: controller.settingsStore))
        _ = settingsView.view

        controller.updateSelectedModelId(model.id)

        XCTAssertEqual(controller.settingsStore.selectedModelId, model.id)
        XCTAssertEqual(controller.selectedModel.remoteFile, model.remoteFile)
        XCTAssertNotNil(model.remoteFile)
        XCTAssertEqual(controller.recognitionCapabilities, .gigaAM)
        XCTAssertEqual(manifest.recommendedModel.backendKind, .whisperCpp)
    }

    @MainActor
    func testModelInstallationAndEffectiveCapabilitiesInAppHost() throws {
        var model = ModelManifestModel.fallback
        model.id = "hosted-gigaam"
        model.backend = "gigaAM"
        model.companionArtifacts = []
        model.byteSize = 4
        model.capabilities = ModelManifestModelCapabilities(timestamps: false)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voicepen-hosted-install-\(UUID().uuidString)")
        let paths = AppPaths(applicationSupportDirectory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = ModelManifest(schemaVersion: 2, recommendedModel: .fallback, compatibleModels: [.fallback, model])
        let controller = AppController.live(paths: paths, modelManifest: manifest, userConfigStore: UserConfigStore(configURL: root.appendingPathComponent("config.toml")))
        let settingsView = NSHostingController(rootView: ModelSettingsView(controller: controller, settingsStore: controller.settingsStore))
        _ = settingsView.view
        controller.updateSelectedModelId(model.id)
        XCTAssertEqual(controller.settingsStore.selectedModelId, model.id)
        XCTAssertEqual(controller.recognitionCapabilities, .gigaAM)
        XCTAssertFalse(model.isInstalled(paths: paths))
        try FileManager.default.createDirectory(at: paths.userModelDirectory(for: model.id), withIntermediateDirectories: true)
        try Data([1, 2, 3, 4]).write(to: paths.userModelFile(for: model.id, fileName: model.localArtifactFileName))
        XCTAssertFalse(model.isInstalled(paths: paths))
        try JSONEncoder().encode(GigaAMInstallationIdentity(model: model)).write(to: paths.userModelCompletionMarker(for: model.id))
        XCTAssertTrue(model.isInstalled(paths: paths))
        XCTAssertEqual(RecognitionCapabilities(model: model), .gigaAM)
        let images = (0..<_dyld_image_count()).compactMap { _dyld_get_image_name($0) }.map { String(cString: $0) }
        XCTAssertTrue(images.contains { $0.contains("VoicePenGigaAM.framework/") })
        XCTAssertTrue(images.contains { $0.contains("whisper.framework/") })
        let appPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path + "/"
        for image in images where image.contains("VoicePenGigaAM.framework/") {
            let embedded = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/VoicePenGigaAM.framework/VoicePenGigaAM")
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: image))), SHA256.hash(data: try Data(contentsOf: embedded)))
            if ProcessInfo.processInfo.environment["VOICEPEN_GIGAAM_REQUIRE_APP_BUNDLE"] == "1" {
                XCTAssertTrue(URL(fileURLWithPath: image).resolvingSymlinksInPath().path.hasPrefix(appPath), "GigaAM image: \(image); app: \(appPath)")
            }
        }
    }

    @MainActor
    func testBothNativeBackendsInBothLoadOrders() async throws {
        let configURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["VOICEPEN_GIGAAM_HOSTED_CONFIG"] ?? "/private/tmp/voicepen-gigaam-hosted/config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else { throw XCTSkip("Real model fixtures were not configured") }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
        let giga = try JSONDecoder().decode(ModelManifestModel.self, from: Data(contentsOf: URL(fileURLWithPath: config.modelEntry)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("voicepen-hosted-native-\(UUID().uuidString)")
        let paths = AppPaths(applicationSupportDirectory: root)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: paths.userModelDirectory(for: giga.id), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: URL(fileURLWithPath: config.gigaAMModel), to: paths.userModelFile(for: giga.id, fileName: giga.localArtifactFileName))
        try JSONEncoder().encode(GigaAMInstallationIdentity(model: giga)).write(to: paths.userModelCompletionMarker(for: giga.id))
        let request = TranscriptionRequest(audioURL: URL(fileURLWithPath: config.audio), glossaryPrompt: "", language: "auto")
        var gigaOutputs: [String] = []
        var whisperOutputs: [String] = []
        for gigaFirst in [true, false] {
            let adapter = GigaAMTranscriptionClient(paths: paths)
            if gigaFirst {
                gigaOutputs.append(try await adapter.transcribe(request, model: giga, decodingProfile: .standard).text)
                let whisper = try await Task.detached { try WhisperCppContext(modelPath: config.whisperModel) }.value
                whisperOutputs.append(try await whisper.transcribe(request, decodingProfile: .standard, voiceActivityDetectionModelPath: nil).text)
            } else {
                let whisper = try await Task.detached { try WhisperCppContext(modelPath: config.whisperModel) }.value
                whisperOutputs.append(try await whisper.transcribe(request, decodingProfile: .standard, voiceActivityDetectionModelPath: nil).text)
                gigaOutputs.append(try await adapter.transcribe(request, model: giga, decodingProfile: .standard).text)
            }
            await adapter.releaseResources(except: nil)
        }
        XCTAssertEqual(gigaOutputs.count, 2)
        XCTAssertEqual(gigaOutputs.first, gigaOutputs.last)
        XCTAssertFalse(gigaOutputs[0].isEmpty)
        XCTAssertEqual(whisperOutputs.first, whisperOutputs.last)
        XCTAssertFalse(whisperOutputs[0].isEmpty)
    }

    private struct Configuration: Decodable, Sendable {
        let modelEntry: String
        let gigaAMModel: String
        let whisperModel: String
        let audio: String
    }
}
