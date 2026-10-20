import Foundation
import XCTest

@testable import VoicePen

final class WhisperMetalHostedIntegrationTests: XCTestCase {
    @MainActor
    func testPinnedWhisperMetalInAppBundleWithLegacyCompanions() async throws {
        guard let configPath = ProcessInfo.processInfo.environment["VOICEPEN_WHISPER_NATIVE_CONFIG"] else {
            throw XCTSkip("Whisper Q5/Q8 fixtures were not configured")
        }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
        let manifest = try LocalModelManifestStore().loadManifest()
        for sourcePath in [config.q5, config.q8] {
            for legacy in [false, true] {
                let source = URL(fileURLWithPath: sourcePath)
                let model = try XCTUnwrap(manifest.compatibleModels.first { $0.localArtifactFileName == source.lastPathComponent })
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("voicepen-whisper-hosted-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: root) }
                let paths = AppPaths(applicationSupportDirectory: root)
                try FileManager.default.createDirectory(at: paths.userModelDirectory(for: model.id), withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: paths.userModelFile(for: model.id, fileName: model.localArtifactFileName), withDestinationURL: source)
                try Data("complete".utf8).write(to: paths.userModelCompletionMarker(for: model.id))
                let companion = paths.userModelDirectory(for: model.id).appendingPathComponent("ggml-large-v3-turbo-encoder.mlmodelc")
                if legacy {
                    try FileManager.default.createDirectory(at: companion, withIntermediateDirectories: true)
                    try Data("legacy fixture".utf8).write(to: companion.appendingPathComponent("model.mil"))
                }
                let client = WhisperCppTranscriptionClient(paths: paths)
                var prepared: PreparedTranscription? = try await client.prepareTranscription(model: model, decodingProfile: .standard)
                let result = try await XCTUnwrap(prepared).transcribe(TranscriptionRequest(audioURL: URL(fileURLWithPath: config.audio), glossaryPrompt: "", language: "ru"))
                XCTAssertFalse(result.text.isEmpty)
                XCTAssertTrue(try XCTUnwrap(result.executionDiagnostics).nativeBackend.hasPrefix("Metal encoder + Metal decoder"))
                XCTAssertEqual(ModelAccelerationStatus.inspect(model: model, paths: paths).actualWhisperAcceleration?.decoder, "Metal")
                if legacy { XCTAssertTrue(FileManager.default.fileExists(atPath: companion.path)) }
                prepared = nil
                await client.releaseResources(except: nil)
                XCTAssertNil(ModelAccelerationStatus.inspect(model: model, paths: paths).actualWhisperAcceleration)
            }
        }
    }

    private struct Configuration: Decodable {
        let q5: String
        let q8: String
        let audio: String
    }
}
