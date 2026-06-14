#if DEBUG
    import Foundation
    import SwiftUI

    private struct HistoryViewPreviewHost: View {
        let historyStore: VoiceHistoryStore
        let colorScheme: ColorScheme

        @MainActor
        init(entries: [VoiceHistoryEntry], colorScheme: ColorScheme = .dark) {
            self.historyStore = HistoryViewPreviewFactory.makeHistoryStore(entries: entries)
            self.colorScheme = colorScheme
        }

        var body: some View {
            let theme = VoicePenTheme.resolve(colorScheme)

            HistoryView(
                historyStore: historyStore,
                actions: .preview
            )
            .frame(width: 1_180, height: 720)
            .environment(\.colorScheme, colorScheme)
            .environment(\.voicePenTheme, theme)
            .voicePenThemedScreen(theme)
        }
    }

    @MainActor
    private enum HistoryViewPreviewFactory {
        static func makeHistoryStore(entries: [VoiceHistoryEntry]) -> VoiceHistoryStore {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoicePenHistoryPreview-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let store = VoiceHistoryStore(historyURL: rootURL.appendingPathComponent("History.sqlite"))
            entries.forEach { entry in
                try? store.append(entry)
            }
            return store
        }

        static var populatedEntries: [VoiceHistoryEntry] {
            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            let archivedAudioURL = previewArchivedAudioURL()
            let metadata = VoiceTranscriptionModelMetadata(
                id: "ggml-large-v3-turbo-q5_0",
                displayName: "Whisper Large v3 Turbo",
                sourceKind: "whisper.cpp GGML",
                version: "q5_0",
                appVersion: "1.8.0-preview"
            )

            return [
                VoiceHistoryEntry(
                    id: UUID(),
                    createdAt: calendar.date(byAdding: .minute, value: -28, to: now) ?? now,
                    duration: 38.6,
                    rawText: "Quickly summarize the client feedback and send the action items to the team.",
                    finalText: """
                        Quickly summarize the client feedback and send the action items to the team.

                        Main points:
                        - tighten onboarding copy
                        - move billing notes into the admin guide
                        - prepare a short release note for Monday
                        """,
                    status: .insertAttempted,
                    errorMessage: nil,
                    timings: VoicePipelineTimings(
                        recording: 38.6,
                        preprocessing: 0.18,
                        transcription: 2.42,
                        normalization: 0.11,
                        insertion: 0.07
                    ),
                    modelMetadata: metadata,
                    diagnosticNotes: [
                        "Preview note: normalization adjusted capitalization."
                    ],
                    recognizedWordCount: 37,
                    archivedAudioURLs: [archivedAudioURL]
                ),
                VoiceHistoryEntry(
                    id: UUID(),
                    createdAt: calendar.date(byAdding: .hour, value: -3, to: now) ?? now,
                    duration: 9.4,
                    rawText: "",
                    finalText: "",
                    status: .empty,
                    errorMessage: nil,
                    timings: VoicePipelineTimings(recording: 9.4, preprocessing: 0.08),
                    modelMetadata: metadata,
                    diagnosticNotes: [],
                    recognizedWordCount: 0
                ),
                VoiceHistoryEntry(
                    id: UUID(),
                    createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                    duration: 14.2,
                    rawText: "",
                    finalText: "",
                    status: .failed,
                    errorMessage: "No speech detected after preprocessing.",
                    timings: VoicePipelineTimings(recording: 14.2, preprocessing: 0.15),
                    modelMetadata: nil,
                    diagnosticNotes: [
                        "Input level stayed below speech threshold."
                    ],
                    recognizedWordCount: 0
                )
            ]
        }

        private static func previewArchivedAudioURL() -> URL {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoicePenHistoryPreviewAudio", isDirectory: true)
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let audioURL = rootURL.appendingPathComponent("sample-session.wav")
            if !FileManager.default.fileExists(atPath: audioURL.path) {
                FileManager.default.createFile(atPath: audioURL.path, contents: Data(), attributes: nil)
            }
            return audioURL
        }
    }

    #Preview("Sessions - Populated") {
        HistoryViewPreviewHost(entries: HistoryViewPreviewFactory.populatedEntries)
    }

    #Preview("Sessions - Empty") {
        HistoryViewPreviewHost(entries: [], colorScheme: .light)
    }
#endif
