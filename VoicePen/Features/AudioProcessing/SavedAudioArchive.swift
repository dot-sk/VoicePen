import Foundation

protocol SavedAudioArchiving: AnyObject {
    @discardableResult
    func archive(_ request: SavedAudioArchiveRequest, storageLimitGB: Int) throws -> URL
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

final class SavedAudioArchive: SavedAudioArchiving {
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

final class NoOpSavedAudioArchive: SavedAudioArchiving {
    @discardableResult
    func archive(_ request: SavedAudioArchiveRequest, storageLimitGB _: Int) throws -> URL {
        request.sourceURL
    }
}

private struct SavedAudioFile {
    var url: URL
    var sizeBytes: Int64
    var modifiedAt: Date
}
