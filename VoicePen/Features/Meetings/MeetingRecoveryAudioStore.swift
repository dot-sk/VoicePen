import Foundation

final class MeetingRecoveryAudioStore {
    private let directory: URL
    private let retentionDuration: TimeInterval
    private let fileManager: FileManager

    init(
        directory: URL,
        retentionDuration: TimeInterval = VoicePenConfig.meetingRecoveryAudioTTL,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.retentionDuration = retentionDuration
        self.fileManager = fileManager
    }

    func retain(recording: MeetingRecordingResult, entryID: UUID, createdAt: Date) throws -> MeetingRecoveryAudioManifest {
        let entryDirectory = directory.appendingPathComponent(entryID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: entryDirectory.path) {
            try fileManager.removeItem(at: entryDirectory)
        }
        try fileManager.createDirectory(at: entryDirectory, withIntermediateDirectories: true)

        let retainedChunks = try recording.chunks.enumerated().map { index, chunk in
            let destination = entryDirectory.appendingPathComponent(fileName(for: chunk, index: index))
            try fileManager.copyItem(at: chunk.url, to: destination)
            return MeetingAudioChunk(
                url: destination,
                source: chunk.source,
                startOffset: chunk.startOffset,
                duration: chunk.duration
            )
        }

        return MeetingRecoveryAudioManifest(
            createdAt: createdAt,
            expiresAt: createdAt.addingTimeInterval(retentionDuration),
            duration: recording.duration,
            sourceFlags: recording.sourceFlags,
            chunks: retainedChunks
        )
    }

    func remove(_ manifest: MeetingRecoveryAudioManifest?) throws {
        guard let manifest else { return }
        let directories = Set(manifest.chunks.map { $0.url.deletingLastPathComponent() })
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    func validate(_ manifest: MeetingRecoveryAudioManifest, now: Date = Date()) throws {
        guard !manifest.isExpired(at: now) else {
            throw MeetingRecordingError.recoveryAudioExpired
        }
        guard manifest.hasAvailableAudio(fileManager: fileManager) else {
            throw MeetingRecordingError.recoveryAudioUnavailable
        }
    }

    private func fileName(for chunk: MeetingAudioChunk, index: Int) -> String {
        "\(index)-\(chunk.source.rawValue)-\(chunk.url.lastPathComponent)"
    }
}
