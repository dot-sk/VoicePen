import Foundation

nonisolated protocol SavedAudioArchiving: AnyObject, Sendable {
    @discardableResult
    func archive(_ request: SavedAudioArchiveRequest, storageLimitGB: Int) throws -> URL
}

nonisolated protocol SavedAudioArchiveScheduling: AnyObject, Sendable {
    func archiveBestEffort(_ request: SavedAudioArchiveRequest, storageLimitGB: Int)
}

nonisolated struct SavedAudioArchiveRequest: Equatable, Sendable {
    var sourceURL: URL
    var kind: SavedAudioRecordingKind
    var capturedAt: Date
    var sourceLabel: String?
    var sequenceIndex: Int?

    init(
        sourceURL: URL,
        kind: SavedAudioRecordingKind,
        capturedAt: Date,
        sourceLabel: String? = nil,
        sequenceIndex: Int? = nil
    ) {
        self.sourceURL = sourceURL
        self.kind = kind
        self.capturedAt = capturedAt
        self.sourceLabel = sourceLabel
        self.sequenceIndex = sequenceIndex
    }
}

nonisolated enum SavedAudioRecordingKind: String, Sendable {
    case dictation
    case meeting

    var directoryKind: SavedAudioDirectoryKind {
        switch self {
        case .dictation:
            return .dictation
        case .meeting:
            return .meeting
        }
    }

    var fileComponent: String {
        switch self {
        case .dictation:
            return "dictation"
        case .meeting:
            return "meeting"
        }
    }
}

nonisolated enum SavedAudioDirectoryKind: Sendable {
    case dictation
    case meeting
}

nonisolated final class SavedAudioArchive: SavedAudioArchiving, @unchecked Sendable {
    private let dictationDirectory: URL
    private let meetingDirectory: URL
    private let fileManager: FileManager
    private let bytesPerGigabyte: Int64

    init(
        dictationDirectory: URL,
        meetingDirectory: URL,
        fileManager: FileManager = .default,
        bytesPerGigabyte: Int64 = 1024 * 1024 * 1024
    ) {
        self.dictationDirectory = dictationDirectory
        self.meetingDirectory = meetingDirectory
        self.fileManager = fileManager
        self.bytesPerGigabyte = max(1, bytesPerGigabyte)
    }

    convenience init(paths: AppPaths, fileManager: FileManager = .default) {
        self.init(
            dictationDirectory: paths.savedDictationAudioDirectory,
            meetingDirectory: paths.savedMeetingAudioDirectory,
            fileManager: fileManager
        )
    }

    @discardableResult
    func archive(_ request: SavedAudioArchiveRequest, storageLimitGB: Int) throws -> URL {
        let directory = directory(for: request.kind.directoryKind)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = uniqueDestination(
            in: directory,
            baseName: fileBaseName(for: request),
            pathExtension: request.sourceURL.pathExtension
        )
        try fileManager.copyItem(at: request.sourceURL, to: destination)
        try fileManager.setAttributes(
            [
                .creationDate: request.capturedAt,
                .modificationDate: request.capturedAt
            ],
            ofItemAtPath: destination.path
        )
        try pruneIfNeeded(storageLimitGB: storageLimitGB)
        return destination
    }

    private func directory(for kind: SavedAudioDirectoryKind) -> URL {
        switch kind {
        case .dictation:
            return dictationDirectory
        case .meeting:
            return meetingDirectory
        }
    }

    private func fileBaseName(for request: SavedAudioArchiveRequest) -> String {
        var components = [
            timestamp(for: request.capturedAt),
            request.kind.fileComponent
        ]

        if let sourceLabel = sanitizedComponent(request.sourceLabel), !sourceLabel.isEmpty {
            components.append(sourceLabel)
        }

        if let sequenceIndex = request.sequenceIndex {
            components.append(String(format: "chunk-%03d", sequenceIndex + 1))
        }

        return components.joined(separator: "-")
    }

    private func uniqueDestination(in directory: URL, baseName: String, pathExtension: String) -> URL {
        var candidate = destination(in: directory, baseName: baseName, pathExtension: pathExtension)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = destination(
                in: directory,
                baseName: "\(baseName)-\(suffix)",
                pathExtension: pathExtension
            )
            suffix += 1
        }
        return candidate
    }

    private func destination(in directory: URL, baseName: String, pathExtension: String) -> URL {
        let url = directory.appendingPathComponent(baseName)
        guard !pathExtension.isEmpty else { return url }
        return url.appendingPathExtension(pathExtension)
    }

    private func pruneIfNeeded(storageLimitGB: Int) throws {
        let limitBytes = storageLimitBytes(for: storageLimitGB)
        var files = try savedAudioFiles()
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.sizeBytes }

        guard totalBytes > limitBytes else { return }

        files.sort { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt < rhs.modifiedAt
            }
            return lhs.url.path < rhs.url.path
        }

        for file in files where totalBytes > limitBytes {
            try fileManager.removeItem(at: file.url)
            totalBytes -= file.sizeBytes
        }
    }

    private func savedAudioFiles() throws -> [SavedAudioFile] {
        var files: [SavedAudioFile] = []
        for directory in [dictationDirectory, meetingDirectory] where fileManager.fileExists(atPath: directory.path) {
            let urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .creationDateKey
                ],
                options: [.skipsHiddenFiles]
            )

            for url in urls {
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .creationDateKey
                ])
                guard values.isRegularFile == true else { continue }
                files.append(
                    SavedAudioFile(
                        url: url,
                        sizeBytes: Int64(values.fileSize ?? 0),
                        modifiedAt: values.contentModificationDate ?? values.creationDate ?? .distantPast
                    ))
            }
        }
        return files
    }

    private func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private func sanitizedComponent(_ value: String?) -> String? {
        guard let value else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let normalized =
            value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let scalars = normalized.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        return scalars.joined()
            .split(separator: "-")
            .joined(separator: "-")
    }

    private func storageLimitBytes(for storageLimitGB: Int) -> Int64 {
        let normalizedLimit = min(
            max(storageLimitGB, VoicePenConfig.minimumSavedAudioStorageLimitGB),
            VoicePenConfig.maximumSavedAudioStorageLimitGB
        )
        return Int64(normalizedLimit) * bytesPerGigabyte
    }
}

nonisolated final class AsyncSavedAudioArchiveScheduler: SavedAudioArchiveScheduling, @unchecked Sendable {
    private let queue = SavedAudioArchiveJobQueue()
    private let worker: SavedAudioArchiveWorker

    init(archiver: SavedAudioArchiving) {
        self.worker = SavedAudioArchiveWorker(archiver: archiver)
    }

    func archiveBestEffort(_ request: SavedAudioArchiveRequest, storageLimitGB: Int) {
        let job = SavedAudioArchiveJob(request: request, storageLimitGB: storageLimitGB)
        guard queue.enqueueAndStartDrainingIfNeeded(job) else { return }

        Task.detached(priority: .utility) { [queue, worker] in
            await worker.drain(queue)
        }
    }
}

nonisolated final class NoOpSavedAudioArchiveScheduler: SavedAudioArchiveScheduling {
    func archiveBestEffort(_: SavedAudioArchiveRequest, storageLimitGB _: Int) {}
}

nonisolated final class NoOpSavedAudioArchive: SavedAudioArchiving {
    @discardableResult
    func archive(_ request: SavedAudioArchiveRequest, storageLimitGB _: Int) throws -> URL {
        request.sourceURL
    }
}

private actor SavedAudioArchiveWorker {
    private let archiver: SavedAudioArchiving

    init(archiver: SavedAudioArchiving) {
        self.archiver = archiver
    }

    func drain(_ queue: SavedAudioArchiveJobQueue) {
        while let job = queue.next() {
            archive(job)
        }
    }

    private func archive(_ job: SavedAudioArchiveJob) {
        do {
            try archiver.archive(job.request, storageLimitGB: job.storageLimitGB)
        } catch {
            AppLogger.info("Saved \(job.request.kind.fileComponent) audio skipped: \(error.localizedDescription)")
        }
    }
}

nonisolated private struct SavedAudioArchiveJob: Sendable {
    let request: SavedAudioArchiveRequest
    let storageLimitGB: Int
}

nonisolated private final class SavedAudioArchiveJobQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [SavedAudioArchiveJob] = []
    private var isDraining = false

    func enqueueAndStartDrainingIfNeeded(_ job: SavedAudioArchiveJob) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        jobs.append(job)
        guard !isDraining else { return false }
        isDraining = true
        return true
    }

    func next() -> SavedAudioArchiveJob? {
        lock.lock()
        defer { lock.unlock() }

        guard !jobs.isEmpty else {
            isDraining = false
            return nil
        }
        return jobs.removeFirst()
    }
}

nonisolated private struct SavedAudioFile: Sendable {
    var url: URL
    var sizeBytes: Int64
    var modifiedAt: Date
}
