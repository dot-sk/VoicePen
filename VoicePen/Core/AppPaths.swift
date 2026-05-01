import Foundation

nonisolated struct AppPaths: @unchecked Sendable {
    private let fileManager: FileManager
    private let customApplicationSupportDirectory: URL?
    private let customTemporaryDirectory: URL?

    init(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.customApplicationSupportDirectory = applicationSupportDirectory
        self.customTemporaryDirectory = temporaryDirectory
    }

    var applicationSupportDirectory: URL {
        if let customApplicationSupportDirectory {
            return customApplicationSupportDirectory
        }

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(VoicePenConfig.appSupportFolderName, isDirectory: true)
    }

    var dictionaryURL: URL {
        databaseURL
    }

    var historyURL: URL {
        databaseURL
    }

    var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("VoicePen.sqlite")
    }

    var userModelsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    var userModelDirectory: URL {
        userModelDirectory(for: VoicePenConfig.modelId)
    }

    var bundledModelDirectory: URL? {
        bundledModelDirectory(for: VoicePenConfig.modelId)
    }

    func userModelDirectory(for modelId: String) -> URL {
        userModelsDirectory.appendingPathComponent(modelId, isDirectory: true)
    }

    func userModelFile(for modelId: String, fileName: String) -> URL {
        userModelDirectory(for: modelId).appendingPathComponent(fileName)
    }

    func userModelArtifact(for modelId: String, localPath: String) -> URL {
        userModelDirectory(for: modelId).appendingPathComponent(localPath)
    }

    func bundledModelDirectory(for modelId: String) -> URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(modelId, isDirectory: true)
    }

    func bundledModelFile(for modelId: String, fileName: String) -> URL? {
        bundledModelDirectory(for: modelId)?.appendingPathComponent(fileName)
    }

    func bundledModelArtifact(for modelId: String, localPath: String) -> URL? {
        bundledModelDirectory(for: modelId)?.appendingPathComponent(localPath)
    }

    var tempAudioDirectory: URL {
        (customTemporaryDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(VoicePenConfig.appSupportFolderName, isDirectory: true)
    }

    var expectedModelDirectories: [URL] {
        [bundledModelDirectory, userModelDirectory].compactMap { $0 }
    }

    func expectedModelDirectories(for modelId: String) -> [URL] {
        [bundledModelDirectory(for: modelId), userModelDirectory(for: modelId)].compactMap { $0 }
    }

    func expectedModelFiles(for modelId: String, fileName: String) -> [URL] {
        [bundledModelFile(for: modelId, fileName: fileName), userModelFile(for: modelId, fileName: fileName)].compactMap { $0 }
    }

    func expectedModelArtifacts(for modelId: String, localPath: String) -> [URL] {
        [bundledModelArtifact(for: modelId, localPath: localPath), userModelArtifact(for: modelId, localPath: localPath)].compactMap { $0 }
    }

    func createRequiredDirectories() throws {
        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: userModelsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tempAudioDirectory, withIntermediateDirectories: true)
    }

    func existingModelDirectory() -> URL? {
        expectedModelDirectories.first { fileManager.fileExists(atPath: $0.path) }
    }

    func existingModelDirectory(for modelId: String) -> URL? {
        expectedModelDirectories(for: modelId).first { fileManager.fileExists(atPath: $0.path) }
    }

    func existingModelFile(for modelId: String, fileName: String) -> URL? {
        expectedModelFiles(for: modelId, fileName: fileName).first { fileManager.fileExists(atPath: $0.path) }
    }

    func existingModelArtifact(for modelId: String, localPath: String) -> URL? {
        expectedModelArtifacts(for: modelId, localPath: localPath).first { fileManager.fileExists(atPath: $0.path) }
    }

    func cleanOldTemporaryAudioFiles(olderThan maxAge: TimeInterval = 24 * 60 * 60) throws {
        guard fileManager.fileExists(atPath: tempAudioDirectory.path) else { return }

        let now = Date()
        let urls = try fileManager.contentsOfDirectory(
            at: tempAudioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension.lowercased() == "wav" {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modifiedAt) > maxAge else { continue }
            try fileManager.removeItem(at: url)
        }
    }
}
