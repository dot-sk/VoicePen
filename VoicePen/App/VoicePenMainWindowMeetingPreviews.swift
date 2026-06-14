#if DEBUG
    import Foundation
    import SwiftUI

    private struct MeetingsViewPreviewHost: View {
        let meetingHistoryStore: MeetingHistoryStore
        let recordingState: MeetingRecordingControlsState
        let colorScheme: ColorScheme

        @MainActor
        init(
            entries: [MeetingHistoryEntry],
            recordingState: MeetingRecordingControlsState = MeetingRecordingControlsState(),
            colorScheme: ColorScheme = .dark
        ) {
            self.meetingHistoryStore = MeetingsViewPreviewFactory.makeMeetingHistoryStore(entries: entries)
            self.recordingState = recordingState
            self.colorScheme = colorScheme
        }

        var body: some View {
            let theme = VoicePenTheme.resolve(colorScheme)

            MeetingsView(
                meetingHistoryStore: meetingHistoryStore,
                recordingState: recordingState,
                actions: .preview
            )
            .frame(width: 1_180, height: 720)
            .environment(\.colorScheme, colorScheme)
            .environment(\.voicePenTheme, theme)
            .voicePenThemedScreen(theme)
        }
    }

    @MainActor
    private enum MeetingsViewPreviewFactory {
        static func makeMeetingHistoryStore(entries: [MeetingHistoryEntry]) -> MeetingHistoryStore {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoicePenMeetingsPreview-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let store = MeetingHistoryStore(databaseURL: rootURL.appendingPathComponent("Meetings.sqlite"))
            entries.forEach { entry in
                try? store.append(entry)
            }
            return store
        }

        static var populatedEntries: [MeetingHistoryEntry] {
            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            let recoveryAudioURL = previewAudioURL(filename: "meeting-recovery.wav")
            let archivedAudioURL = previewAudioURL(filename: "meeting-archive.wav")
            let metadata = VoiceTranscriptionModelMetadata(
                id: "ggml-large-v3-turbo-q5_0",
                displayName: "Whisper Large v3 Turbo",
                sourceKind: "whisper.cpp GGML",
                version: "q5_0",
                appVersion: "1.8.0-preview"
            )

            return [
                MeetingHistoryEntry(
                    id: UUID(),
                    createdAt: calendar.date(byAdding: .minute, value: -42, to: now) ?? now,
                    duration: 1_826,
                    transcriptText: """
                        [00:00:04 - 00:00:12] Speaker 1: Let's start with the release checklist and the open onboarding items.
                        [00:00:15 - 00:00:24] Speaker 2: Billing copy is ready, but the admin guide still needs one pass.
                        [00:00:29 - 00:00:39] Speaker 1: Good. Please move the risky migration notes into a separate section.
                        [00:00:41 - 00:00:53] Speaker 3: I can take the release note and have a draft before the afternoon review.
                        """,
                    status: .completed,
                    sourceFlags: MeetingSourceFlags(microphoneCaptured: true, systemAudioCaptured: true),
                    errorMessage: nil,
                    timings: MeetingPipelineTimings(
                        recording: 1_826,
                        preprocessing: 0.42,
                        transcription: 8.65,
                        diarization: 2.34
                    ),
                    modelMetadata: metadata,
                    recognizedWordCount: 82,
                    speakerCount: 3,
                    archivedAudioURLs: [archivedAudioURL]
                ),
                MeetingHistoryEntry(
                    id: UUID(),
                    createdAt: calendar.date(byAdding: .hour, value: -5, to: now) ?? now,
                    duration: 612,
                    transcriptText: "Speaker 1: Partial transcript survived after the system audio stream stopped.",
                    status: .partial,
                    sourceFlags: MeetingSourceFlags(
                        microphoneCaptured: true,
                        systemAudioCaptured: false,
                        partial: true
                    ),
                    errorMessage: "System audio capture ended before recording stopped.",
                    timings: MeetingPipelineTimings(recording: 612, preprocessing: 0.31, transcription: 3.2),
                    modelMetadata: metadata,
                    recognizedWordCount: 10,
                    speakerCount: 1,
                    recoveryAudio: MeetingRecoveryAudioManifest(
                        createdAt: now,
                        expiresAt: calendar.date(byAdding: .day, value: 2, to: now) ?? now,
                        duration: 612,
                        sourceFlags: MeetingSourceFlags(microphoneCaptured: true, systemAudioCaptured: false),
                        chunks: [
                            MeetingAudioChunk(
                                url: recoveryAudioURL,
                                source: .microphone,
                                startOffset: 0,
                                duration: 612
                            )
                        ]
                    )
                ),
                MeetingHistoryEntry(
                    id: UUID(),
                    createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                    duration: 74,
                    transcriptText: "",
                    status: .failed,
                    sourceFlags: MeetingSourceFlags(microphoneCaptured: true, systemAudioCaptured: true),
                    errorMessage: "No speech detected after preprocessing.",
                    timings: MeetingPipelineTimings(recording: 74, preprocessing: 0.18),
                    modelMetadata: nil,
                    recognizedWordCount: 0,
                    speakerCount: nil
                )
            ]
        }

        private static func previewAudioURL(filename: String) -> URL {
            let rootURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoicePenMeetingsPreviewAudio", isDirectory: true)
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

            let audioURL = rootURL.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: audioURL.path) {
                FileManager.default.createFile(atPath: audioURL.path, contents: Data(), attributes: nil)
            }
            return audioURL
        }
    }

    #Preview("Meetings - Populated") {
        MeetingsViewPreviewHost(entries: MeetingsViewPreviewFactory.populatedEntries)
    }

    #Preview("Meetings - Recording") {
        MeetingsViewPreviewHost(
            entries: MeetingsViewPreviewFactory.populatedEntries,
            recordingState: MeetingRecordingControlsState(isCaptureActive: true, canStartRecording: true)
        )
    }

    #Preview("Meetings - Empty") {
        MeetingsViewPreviewHost(entries: [], colorScheme: .light)
    }
#endif
