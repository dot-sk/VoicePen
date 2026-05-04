import AppKit
import Combine
import Foundation

@MainActor
protocol UserPromptPresenter {
    func showAlert(
        messageText: String,
        informativeText: String,
        style: NSAlert.Style,
        buttons: [String],
        activateBeforeShowing: Bool
    ) -> NSApplication.ModalResponse
}

@MainActor
final class NSAlertUserPromptPresenter: UserPromptPresenter {
    func showAlert(
        messageText: String,
        informativeText: String,
        style: NSAlert.Style,
        buttons: [String],
        activateBeforeShowing: Bool = false
    ) -> NSApplication.ModalResponse {
        if activateBeforeShowing {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }
}

@MainActor
struct AppControllerStartTasks {
    let permissions: Task<Void, Never>?
    let modelWarmup: Task<Void, Never>?

    static let empty = AppControllerStartTasks(permissions: nil, modelWarmup: nil)
}

@MainActor
final class AppController: ObservableObject {
    @Published var appState: AppState = .starting
    @Published var lastRawText: String = ""
    @Published var lastFinalText: String = ""
    @Published var errorMessage: String?
    @Published var modelDownloadProgress: Double?
    @Published var modelRuntimeState: ModelRuntimeState = .notLoaded
    @Published private(set) var modelManifest: ModelManifest

    private let paths: AppPaths
    private let pipeline: DictationPipeline
    private let hotkey: PushToTalkHotkeyClient
    private let permissions: PermissionsClient
    let dictionaryStore: DictionaryStore
    private let inserter: TextInsertionClient
    private let clipboard: TextPasteboard
    private let overlay: OverlayPresenter
    private let transcriptionCancellationKeyMonitor: TranscriptionCancellationKeyMonitor
    private let modelDownloader: ModelDownloadClient
    private let modelWarmupClient: ModelWarmupClient?
    private let launchAtLogin: LaunchAtLoginClient
    private let userPrompts: UserPromptPresenter
    private let environmentSettingsStore: AppEnvironmentSettingsStore
    let historyStore: VoiceHistoryStore
    let settingsStore: AppSettingsStore

    private var didStart = false
    private var activeModelDownloadID: UUID?
    private var modelDownloadTask: Task<Void, Never>?
    private var modelWarmupTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var didHandleCurrentTranscriptionCancellation = false
    private var isWaitingForCustomShortcut = false
    private var accessibilityPermissionPollingTask: Task<Void, Never>?
    private var appActivationObserver: NSObjectProtocol?

    private static let microphonePermissionRequiredMessage = "Microphone permission is required to record dictation audio locally."
    private static let accessibilityPermissionRequiredMessage = "Text insertion permission is required so VoicePen can paste text into the active app."

    var recommendedModel: ModelManifestModel {
        modelManifest.recommendedModel
    }

    var selectedModel: ModelManifestModel {
        modelManifest.compatibleModels.first { $0.id == settingsStore.selectedModelId }
            ?? recommendedModel
    }

    var dictionaryURL: URL {
        paths.dictionaryURL
    }

    var historyURL: URL {
        paths.historyURL
    }

    var userConfigURL: URL {
        environmentSettingsStore.userConfigURL
    }

    var latestTranscriptionText: String {
        let candidates = [
            lastFinalText,
            lastRawText,
            historyStore.entries.first?.bestText ?? ""
        ]

        return
            candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    var hasLatestTranscriptionText: Bool {
        !latestTranscriptionText.isEmpty
    }

    var userModelsDirectory: URL {
        paths.userModelsDirectory
    }

    var userModelDirectory: URL {
        paths.userModelDirectory(for: selectedModel.id)
    }

    var isModelInstalled: Bool {
        switch selectedModel.backendKind {
        case .whisperCpp:
            selectedModel.isInstalled(paths: paths)
        case .fluidAudio:
            FluidAudioModelInstallation.isInstalled(model: selectedModel, paths: paths)
        case .unsupported:
            paths.existingModelDirectory(for: selectedModel.id) != nil
        }
    }

    var modelAccelerationStatus: ModelAccelerationStatus {
        ModelAccelerationStatus.inspect(model: selectedModel, paths: paths)
    }

    var modelDiagnosticsText: String {
        let status = modelAccelerationStatus
        var lines = [
            "VoicePen Model Diagnostics",
            "Model: \(selectedModel.displayName)",
            "Model ID: \(selectedModel.id)",
            "Backend: \(selectedModel.sourceKind)",
            "Version: \(selectedModel.version)",
            "Size: \(selectedModel.sizeLabel)",
            "Installed: \(isModelInstalled ? "yes" : "no")",
            "Acceleration: \(status.accelerationSummary)",
            "\(status.model.displayName): \(artifactDiagnostics(status.model))"
        ]

        lines += status.companionArtifacts.map { artifact in
            "\(artifact.displayName): \(artifactDiagnostics(artifact))"
        }

        if let timings = historyStore.entries.first?.timings {
            lines.append("Latest session timings:")
            lines += timingDiagnostics(timings)
        }

        return lines.joined(separator: "\n")
    }

    var hasDownloadedModelFiles: Bool {
        FileManager.default.fileExists(atPath: userModelDirectory.path)
    }

    var microphonePermissionTitle: String {
        switch permissions.microphonePermissionStatus {
        case .authorized:
            return "Allowed"
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied"
        }
    }

    var accessibilityPermissionTitle: String {
        permissions.hasAccessibilityPermission ? "Allowed" : "Missing"
    }

    var runningBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    var runningAppPath: String {
        Bundle.main.bundleURL.path
    }

    var menuBarSystemImage: String {
        switch appState {
        case .recording:
            "record.circle.fill"
        case .transcribing, .downloadingModel, .preparingModel:
            "waveform"
        case .missingMicrophonePermission, .missingAccessibilityPermission, .missingModel, .error:
            "exclamationmark.triangle.fill"
        default:
            "mic.fill"
        }
    }

    init(
        paths: AppPaths,
        pipeline: DictationPipeline,
        hotkey: PushToTalkHotkeyClient,
        permissions: PermissionsClient,
        dictionaryStore: DictionaryStore,
        inserter: TextInsertionClient,
        clipboard: TextPasteboard = NSPasteboard.general,
        overlay: OverlayPresenter,
        transcriptionCancellationKeyMonitor: TranscriptionCancellationKeyMonitor,
        modelDownloader: ModelDownloadClient,
        modelWarmupClient: ModelWarmupClient? = nil,
        launchAtLogin: LaunchAtLoginClient? = nil,
        userPrompts: UserPromptPresenter,
        environmentSettingsStore: AppEnvironmentSettingsStore? = nil,
        historyStore: VoiceHistoryStore,
        settingsStore: AppSettingsStore,
        modelManifest: ModelManifest
    ) {
        self.paths = paths
        self.pipeline = pipeline
        self.hotkey = hotkey
        self.permissions = permissions
        self.dictionaryStore = dictionaryStore
        self.inserter = inserter
        self.clipboard = clipboard
        self.overlay = overlay
        self.transcriptionCancellationKeyMonitor = transcriptionCancellationKeyMonitor
        self.modelDownloader = modelDownloader
        self.modelWarmupClient = modelWarmupClient
        self.launchAtLogin = launchAtLogin ?? NoOpLaunchAtLoginClient()
        self.userPrompts = userPrompts
        self.environmentSettingsStore = environmentSettingsStore ?? AppEnvironmentSettingsStore()
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.modelManifest = modelManifest
    }

    static func live() -> AppController {
        let paths = AppPaths()
        let modelManifest = LocalModelManifestStore().loadManifestOrDefault()
        let recommendedModel = modelManifest.recommendedModel
        let dictionaryStore = DictionaryStore(dictionaryURL: paths.dictionaryURL)
        let historyStore = VoiceHistoryStore(historyURL: paths.historyURL)
        let settingsStore = AppSettingsStore(databaseURL: paths.databaseURL)
        let overlay = BottomOverlayWindowController()
        let recorder = LiveAudioRecordingClient(tempDirectory: paths.tempAudioDirectory)
        let audioPreprocessor = LiveAudioPreprocessingClient(outputDirectory: paths.tempAudioDirectory)
        let whisperCppTranscriber = WhisperCppTranscriptionClient(paths: paths)
        let fluidAudioTranscriber = FluidAudioTranscriptionClient(paths: paths)
        let inserter = PasteboardTextInsertionClient(restoreDelay: VoicePenConfig.clipboardRestoreDelay)
        let userConfigStore = UserConfigStore()
        let transcriber = RoutingTranscriptionClient(
            modelProvider: {
                modelManifest.compatibleModels.first { $0.id == settingsStore.selectedModelId }
                    ?? recommendedModel
            },
            whisperCppClient: whisperCppTranscriber,
            fluidAudioClient: fluidAudioTranscriber
        )
        let pipeline = DictationPipeline(
            recorder: recorder,
            audioPreprocessor: audioPreprocessor,
            transcriber: transcriber,
            dictionaryStore: dictionaryStore,
            inserter: inserter,
            overlay: overlay,
            userConfigStore: userConfigStore,
            languageProvider: { settingsStore.transcriptionLanguage },
            speechPreprocessingModeProvider: { settingsStore.speechPreprocessingMode },
            developerModeOverrideProvider: { settingsStore.developerModeOverride },
            activeApplicationProvider: {
                guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
                return ActiveApplicationInfo(
                    bundleIdentifier: app.bundleIdentifier,
                    localizedName: app.localizedName
                )
            },
            minimumRecordingDuration: VoicePenConfig.minimumRecordingDuration
        )

        let controller = AppController(
            paths: paths,
            pipeline: pipeline,
            hotkey: LivePushToTalkHotkeyClient(settingsStore: settingsStore),
            permissions: LivePermissionsClient(),
            dictionaryStore: dictionaryStore,
            inserter: inserter,
            overlay: overlay,
            transcriptionCancellationKeyMonitor: LiveTranscriptionCancellationKeyMonitor(),
            modelDownloader: RoutingModelDownloadClient(
                whisperCppDownloader: WhisperCppModelDownloadClient(
                    paths: paths,
                    proxyProvider: {
                        ModelDownloadProxyConfiguration.fromEnvironment()
                    }
                ),
                fluidAudioDownloader: FluidAudioModelDownloadClient(paths: paths)
            ),
            modelWarmupClient: transcriber,
            launchAtLogin: LiveLaunchAtLoginClient(),
            userPrompts: NSAlertUserPromptPresenter(),
            environmentSettingsStore: userConfigStore,
            historyStore: historyStore,
            settingsStore: settingsStore,
            modelManifest: modelManifest
        )
        overlay.onCancelTranscription = { [weak controller] in
            controller?.cancelTranscription()
        }
        return controller
    }

    var isDownloadingModel: Bool {
        switch appState {
        case .downloadingModel:
            return true
        case .preparingModel:
            return activeModelDownloadID != nil
        default:
            return false
        }
    }

    @discardableResult
    func start() -> AppControllerStartTasks {
        guard !didStart else { return .empty }
        didStart = true

        let modelWarmup: Task<Void, Never>?
        do {
            try paths.createRequiredDirectories()
            try paths.cleanOldTemporaryAudioFiles()
            environmentSettingsStore.applyEnvironment()
            try dictionaryStore.load()
            try historyStore.load()
            try settingsStore.load(defaultModelId: recommendedModel.id)
            try syncOpenAtLoginState()
            modelWarmup = scheduleModelWarmupIfInstalled()
        } catch {
            setError(error)
            return .empty
        }

        let permissions = Task {
            await requestStartupPermissions()
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor [controller] in
                controller.refreshPermissionState()
                controller.refreshOpenAtLoginState()
            }
        }

        return AppControllerStartTasks(permissions: permissions, modelWarmup: modelWarmup)
    }

    private func requestStartupPermissions() async {
        var microphoneGranted = permissions.microphonePermissionStatus == .authorized
        if !microphoneGranted {
            microphoneGranted = await permissions.requestMicrophonePermission()
            if !microphoneGranted {
                appState = .missingMicrophonePermission
                errorMessage = Self.microphonePermissionRequiredMessage
            }
            showMicrophoneDeniedNoticeIfNeeded(granted: microphoneGranted)
        }

        if !permissions.hasAccessibilityPermission {
            permissions.requestAccessibilityPermission()
            startAccessibilityPermissionPolling()
        }

        guard microphoneGranted else {
            appState = .missingMicrophonePermission
            return
        }

        guard permissions.hasAccessibilityPermission else {
            appState = .missingAccessibilityPermission
            errorMessage = Self.accessibilityPermissionRequiredMessage
            startAccessibilityPermissionPolling()
            return
        }

        installHotkey()
        appState = .ready
    }

    private func showMicrophoneDeniedNoticeIfNeeded(granted: Bool) {
        guard !granted else { return }

        _ = userPrompts.showAlert(
            messageText: "Microphone permission is needed",
            informativeText: """
                VoicePen records only while you hold the hotkey, and transcription happens locally on this Mac.

                You can enable Microphone permission later in System Settings > Privacy & Security > Microphone.
                """,
            style: .warning,
            buttons: ["OK"],
            activateBeforeShowing: true
        )
    }

    @discardableResult
    func startRecording() -> Task<Void, Never>? {
        guard appState != .recording, appState != .transcribing, !isDownloadingModel else { return nil }

        cancelModelWarmup()
        let task = Task {
            do {
                appState = .recording
                errorMessage = nil
                try await pipeline.start()
            } catch {
                setError(error)
            }
        }
        return task
    }

    @discardableResult
    func stopRecordingAndProcess() -> Task<Void, Never>? {
        guard appState == .recording, transcriptionTask == nil else { return nil }

        didHandleCurrentTranscriptionCancellation = false
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                transcriptionCancellationKeyMonitor.uninstall()
                transcriptionTask = nil
            }

            do {
                appState = .transcribing
                transcriptionCancellationKeyMonitor.install { [weak self] in
                    self?.cancelTranscription()
                }
                let result = try await pipeline.stopAndProcess()
                try Task.checkCancellation()
                lastRawText = result.rawText
                lastFinalText = result.finalText
                recordHistory(for: result)
                appState = .ready
            } catch is CancellationError {
                handleTranscriptionCancellation()
            } catch let error as TranscriptionError {
                handleTranscriptionError(error)
            } catch {
                setError(error)
            }
        }
        transcriptionTask = task
        return task
    }

    func cancelTranscription() {
        guard appState == .transcribing else { return }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        handleTranscriptionCancellation()
    }

    func insertTestText() {
        inserter.insert("VoicePen test text")
    }

    func showRecordingOverlay() {
        overlay.show(.recording(startedAt: Date(), level: nil))
    }

    func showTranscribingOverlay() {
        overlay.show(.transcribing(stage: .transcribing, progress: nil))
    }

    func showDoneOverlay() {
        overlay.show(.done(message: "Inserted"))
        overlay.hide(after: 0.7)
    }

    func showErrorOverlay() {
        overlay.show(.error(message: "Test error"))
        overlay.hide(after: 1.2)
    }

    func openDictionaryFile() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.dictionaryURL])
    }

    func openHistoryFile() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.historyURL])
    }

    func openUserConfigFile() {
        do {
            try environmentSettingsStore.ensureUserConfigFileExists()
            NSWorkspace.shared.open(environmentSettingsStore.userConfigURL)
        } catch {
            setError(error)
        }
    }

    func copyToClipboard(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        clipboard.clearContents()
        _ = clipboard.setString(trimmedText, forType: .string)
    }

    func copyLastTranscription() {
        copyToClipboard(latestTranscriptionText)
    }

    func copyModelDiagnostics() {
        copyToClipboard(modelDiagnosticsText)
    }

    func copyDictionaryReviewPrompt(
        preset: DictionaryReviewPromptPreset,
        historyLimit: HistoryReviewLimit
    ) {
        let prompt = DictionaryReviewPromptBuilder().build(
            preset: preset,
            dictionaryEntries: dictionaryStore.entries,
            historyEntries: historyStore.entries,
            historyLimit: historyLimit
        )
        copyToClipboard(prompt)
    }

    func prepareDictionaryImportPreview(
        csvText: String,
        historyLimit: HistoryReviewLimit
    ) throws -> DictionaryImportPreview {
        let entries = try DictionaryCSVImporter.parse(csvText)
        return try DictionaryImportPreviewBuilder().build(
            currentEntries: dictionaryStore.entries,
            pendingEntries: entries,
            historyEntries: historyStore.entries,
            limit: historyLimit.rawValue
        )
    }

    func prepareDictionaryImportPreview(
        fileURL: URL,
        historyLimit: HistoryReviewLimit
    ) throws -> DictionaryImportPreview {
        let entries = try DictionaryCSVImporter.parse(fileURL: fileURL)
        return try DictionaryImportPreviewBuilder().build(
            currentEntries: dictionaryStore.entries,
            pendingEntries: entries,
            historyEntries: historyStore.entries,
            limit: historyLimit.rawValue
        )
    }

    func prepareDictionaryImportPreviewFromClipboard(
        historyLimit: HistoryReviewLimit
    ) throws -> DictionaryImportPreview {
        guard let text = clipboard.string(forType: .string) else {
            throw DictionaryCSVImporterError.emptyFile
        }

        return try prepareDictionaryImportPreview(
            csvText: text,
            historyLimit: historyLimit
        )
    }

    func confirmDictionaryImportPreview(_ preview: DictionaryImportPreview) throws {
        let expectedPostImportEntries = try DictionaryMerger.mergedEntries(
            existingEntries: dictionaryStore.entries,
            importedEntries: preview.importedEntries
        )
        guard expectedPostImportEntries == preview.postImportEntries else {
            throw AppControllerDictionaryImportError.stalePreview
        }

        try dictionaryStore.importEntries(preview.importedEntries)
    }

    func insertText(_ text: String) {
        let trimmedText = TextOutputNormalizer.normalize(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        inserter.insert(trimmedText)
    }

    func retryInsertLastTranscription() {
        insertText(latestTranscriptionText)
    }

    func confirmAndDownloadModel() {
        guard !isDownloadingModel else { return }

        if isModelInstalled {
            overlay.show(.done(message: "Model ready"))
            overlay.hide(after: 1.0)
            return
        }

        let response = userPrompts.showAlert(
            messageText: "Download transcription model?",
            informativeText: """
                VoicePen will download the local transcription model:

                \(selectedModel.displayName)
                \(selectedModel.id)

                The model is stored in:
                \(userModelDirectory.path)
                """,
            style: .informational,
            buttons: ["Download", "Cancel"],
            activateBeforeShowing: false
        )

        guard response == .alertFirstButtonReturn else { return }
        downloadModel()
    }

    func openModelFolder() {
        do {
            try paths.createRequiredDirectories()
            NSWorkspace.shared.open(paths.userModelsDirectory)
        } catch {
            setError(error)
        }
    }

    func requestMicrophonePermission() {
        Task {
            let granted = await permissions.requestMicrophonePermission()
            guard granted else {
                appState = .missingMicrophonePermission
                return
            }

            updateReadyStateFromAccessibilityPermission()
        }
    }

    func requestAccessibilityPermission() {
        openAccessibilitySettings()
        refreshPermissionState()
        startAccessibilityPermissionPolling()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refreshPermissionState() {
        guard appState != .recording, appState != .transcribing, !isDownloadingModel else { return }

        guard permissions.microphonePermissionStatus == .authorized else {
            appState = .missingMicrophonePermission
            errorMessage = Self.microphonePermissionRequiredMessage
            return
        }

        updateReadyStateFromAccessibilityPermission()
    }

    private func startAccessibilityPermissionPolling() {
        accessibilityPermissionPollingTask?.cancel()

        accessibilityPermissionPollingTask = Task { @MainActor [weak self] in
            for _ in 0..<30 {
                guard let self, !Task.isCancelled else { return }

                if self.permissions.hasAccessibilityPermission {
                    self.refreshPermissionState()
                    return
                }

                try? await Task.sleep(for: VoicePenConfig.accessibilityPermissionPollInterval)
            }
        }
    }

    private func installHotkey() {
        do {
            try hotkey.install(
                onKeyDown: { [weak self] in
                    Task { @MainActor in
                        self?.startRecording()
                    }
                },
                onKeyUp: { [weak self] in
                    Task { @MainActor in
                        self?.stopRecordingAndProcess()
                    }
                }
            )
            isWaitingForCustomShortcut = false
            errorMessage = nil
        } catch HotkeyError.shortcutMissing where settingsStore.hotkeyPreference == .custom {
            isWaitingForCustomShortcut = true
            errorMessage = HotkeyError.shortcutMissing.localizedDescription
        } catch {
            isWaitingForCustomShortcut = false
            setError(error)
        }
    }

    private func reinstallHotkeyIfReady() {
        guard appState == .ready || appState == .missingModel else { return }
        installHotkey()
    }

    @discardableResult
    func downloadModel() -> Task<Void, Never>? {
        guard !isDownloadingModel else { return nil }

        let downloadID = UUID()
        activeModelDownloadID = downloadID
        modelDownloadProgress = nil
        appState = .downloadingModel(progress: nil)
        errorMessage = nil
        overlay.show(.transcribing(stage: .loadingModel, progress: nil))
        let model = selectedModel

        let task = Task {
            do {
                let modelURL = try await modelDownloader.downloadModel(model) { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard self?.activeModelDownloadID == downloadID else { return }
                        self?.handleModelDownloadEvent(event)
                    }
                }

                guard activeModelDownloadID == downloadID else { return }
                clearActiveModelDownload()
                AppLogger.info("Downloaded model to \(modelURL.path)")
                overlay.show(.done(message: "Model ready"))
                overlay.hide(after: 1.0)

                updateStateAfterModelChange()
                scheduleModelWarmupIfInstalled()
            } catch is CancellationError {
                guard activeModelDownloadID == downloadID else { return }
                clearActiveModelDownload()
                overlay.show(.done(message: "Download canceled"))
                overlay.hide(after: 1.0)
                updateStateAfterModelChange()
            } catch {
                guard activeModelDownloadID == downloadID else { return }
                clearActiveModelDownload()
                setError(error)
            }
        }
        modelDownloadTask = task
        return task
    }

    @discardableResult
    func cancelModelDownload() -> Task<Void, Never>? {
        guard isDownloadingModel else { return nil }

        let task = modelDownloadTask
        clearActiveModelDownload()
        task?.cancel()
        overlay.show(.done(message: "Download canceled"))
        overlay.hide(after: 1.0)
        updateStateAfterIncompleteModelDownload()

        let cleanupTask = Task { [weak self] in
            guard let self else { return }
            updateStateAfterIncompleteModelDownload()
        }
        return cleanupTask
    }

    private func handleModelDownloadEvent(_ event: ModelDownloadEvent) {
        switch event {
        case let .downloadingArtifact(_, progress):
            modelDownloadProgress = progress
            appState = .downloadingModel(progress: progress)
        case let .extractingArtifact(name):
            modelDownloadProgress = nil
            appState = .preparingModel("Extracting \(name)")
        case .validating:
            modelDownloadProgress = nil
            appState = .preparingModel("Validating model")
        case .completed:
            modelDownloadProgress = nil
            appState = .preparingModel("Model ready")
        }
    }

    private func clearActiveModelDownload() {
        activeModelDownloadID = nil
        modelDownloadTask = nil
        modelDownloadProgress = nil
    }

    func deleteDownloadedModelFiles() {
        guard !isDownloadingModel, appState != .recording, appState != .transcribing else { return }

        do {
            let modelDirectory = userModelDirectory
            if FileManager.default.fileExists(atPath: modelDirectory.path) {
                try FileManager.default.removeItem(at: modelDirectory)
            }

            modelDownloadProgress = nil
            errorMessage = nil
            overlay.show(.done(message: "Model removed"))
            overlay.hide(after: 1.0)

            updateStateAfterModelChange()
        } catch {
            setError(error)
        }
    }

    func reloadDictionary() throws {
        try dictionaryStore.load()
    }

    func clearHistory() {
        do {
            try historyStore.clear()
        } catch {
            setError(error)
        }
    }

    func deleteHistoryEntry(id: VoiceHistoryEntry.ID) {
        do {
            try historyStore.delete(id: id)
        } catch {
            setError(error)
        }
    }

    func updateTranscriptionLanguage(_ language: String) {
        do {
            try settingsStore.updateTranscriptionLanguage(language)
        } catch {
            setError(error)
        }
    }

    func updateSelectedModelId(_ modelId: String) {
        do {
            guard modelManifest.compatibleModels.contains(where: { $0.id == modelId }) else {
                throw TranscriptionError.unsupportedModel(modelId)
            }
            try settingsStore.updateSelectedModelId(modelId)
            scheduleModelWarmupIfInstalled()
        } catch {
            setError(error)
        }
    }

    @discardableResult
    private func scheduleModelWarmupIfInstalled() -> Task<Void, Never>? {
        guard isModelInstalled, let modelWarmupClient else {
            modelRuntimeState = .notLoaded
            return nil
        }

        let model = selectedModel
        let language = TranscriptionLanguageResolver.resolve(settingsStore.transcriptionLanguage)
        modelWarmupTask?.cancel()
        modelRuntimeState = .warming(modelId: model.id)
        let task = Task { @MainActor [weak self, modelWarmupClient] in
            do {
                AppLogger.info("Warming up model \(model.id)")
                try await modelWarmupClient.warmUp(model: model, language: language)
                guard !Task.isCancelled else { return }
                self?.modelRuntimeState = .ready(modelId: model.id)
                AppLogger.info("Model warmup completed for \(model.id)")
            } catch is CancellationError {
                AppLogger.info("Model warmup canceled for \(model.id)")
            } catch {
                guard !Task.isCancelled else { return }
                self?.modelRuntimeState = .failed(modelId: model.id, message: error.localizedDescription)
                AppLogger.error("Model warmup failed for \(model.id): \(error.localizedDescription)")
            }

            self?.modelWarmupTask = nil
        }
        modelWarmupTask = task
        return task
    }

    private func cancelModelWarmup() {
        guard modelWarmupTask != nil else { return }
        AppLogger.info("Canceling model warmup because recording started")
        modelWarmupTask?.cancel()
        modelWarmupTask = nil
    }

    func updateSpeechPreprocessingMode(_ mode: SpeechPreprocessingMode) {
        do {
            try settingsStore.updateSpeechPreprocessingMode(mode)
        } catch {
            setError(error)
        }
    }

    func updateHotkeyPreference(_ preference: HotkeyPreference) {
        do {
            try settingsStore.updateHotkeyPreference(preference)
            reinstallHotkeyIfReady()
        } catch {
            setError(error)
        }
    }

    func customHotkeyDidChange() {
        guard settingsStore.hotkeyPreference == .custom else { return }
        guard permissions.hasAccessibilityPermission else { return }
        guard appState == .ready || appState == .missingModel || isWaitingForCustomShortcut else { return }
        installHotkey()
    }

    func updateHotkeyHoldDuration(_ duration: TimeInterval) {
        do {
            try settingsStore.updateHotkeyHoldDuration(duration)
            reinstallHotkeyIfReady()
        } catch {
            setError(error)
        }
    }

    func updateDeveloperModeOverride(_ mode: DeveloperMode) {
        do {
            try settingsStore.updateDeveloperModeOverride(mode)
        } catch {
            setError(error)
        }
    }

    func updateOpenAtLogin(_ isEnabled: Bool) {
        do {
            try launchAtLogin.setEnabled(isEnabled)
            try settingsStore.updateOpenAtLogin(launchAtLogin.isEnabled)
        } catch {
            setError(error)
        }
    }

    func refreshOpenAtLoginState() {
        do {
            try syncOpenAtLoginState()
        } catch {
            setError(error)
        }
    }

    private func syncOpenAtLoginState() throws {
        let systemIsEnabled = launchAtLogin.isEnabled
        guard settingsStore.openAtLogin != systemIsEnabled else { return }
        try settingsStore.updateOpenAtLogin(systemIsEnabled)
    }

    private func handleTranscriptionError(_ error: TranscriptionError) {
        switch error {
        case .modelMissing:
            appState = .missingModel
        default:
            appState = .error(error.localizedDescription)
        }

        errorMessage = error.localizedDescription
        recordHistory(
            rawText: "",
            finalText: "",
            status: .failed,
            errorMessage: error.localizedDescription,
            recording: nil,
            timings: nil
        )
        overlay.show(.error(message: error.shortMessage))
        overlay.hide(after: 2.0)
    }

    private func handleTranscriptionCancellation() {
        guard !didHandleCurrentTranscriptionCancellation else { return }

        didHandleCurrentTranscriptionCancellation = true
        overlay.show(.done(message: "Canceled"))
        overlay.hide(after: 0.7)
        updateStateAfterModelChange()
    }

    private func setError(_ error: Error) {
        appState = .error(error.localizedDescription)
        errorMessage = error.localizedDescription
        overlay.show(.error(message: error.localizedDescription))
        overlay.hide(after: 2.0)
    }

    private func recordHistory(for result: DictationPipelineResult) {
        let status: VoiceHistoryStatus
        if result.didAttemptInsertion {
            status = .insertAttempted
        } else {
            status = .empty
        }

        recordHistory(
            rawText: result.rawText,
            finalText: result.finalText,
            status: status,
            errorMessage: nil,
            recording: result.recording,
            timings: result.timings,
            modelMetadata: result.modelMetadata,
            diagnosticNotes: result.diagnosticNotes
        )
    }

    private func recordHistory(
        rawText: String,
        finalText: String,
        status: VoiceHistoryStatus,
        errorMessage: String?,
        recording: RecordingResult?,
        timings: VoicePipelineTimings?,
        modelMetadata: VoiceTranscriptionModelMetadata? = nil,
        diagnosticNotes: [String] = []
    ) {
        let trimmedRawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFinalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsefulContent = !trimmedRawText.isEmpty || !trimmedFinalText.isEmpty || errorMessage != nil
        guard hasUsefulContent else { return }

        let entry = VoiceHistoryEntry(
            id: UUID(),
            createdAt: recording?.endedAt ?? Date(),
            duration: recording?.duration,
            rawText: rawText,
            finalText: finalText,
            status: status,
            errorMessage: errorMessage,
            timings: timings,
            modelMetadata: modelMetadata ?? VoiceTranscriptionModelMetadata(model: selectedModel),
            diagnosticNotes: diagnosticNotes
        )

        do {
            try historyStore.append(entry)
        } catch {
            AppLogger.error("Failed to save voice history: \(error.localizedDescription)")
        }
    }

    private func updateReadyStateFromAccessibilityPermission() {
        guard permissions.hasAccessibilityPermission else {
            appState = .missingAccessibilityPermission
            errorMessage = Self.accessibilityPermissionRequiredMessage
            return
        }

        accessibilityPermissionPollingTask?.cancel()
        accessibilityPermissionPollingTask = nil
        errorMessage = nil
        installHotkey()
        appState = .ready
    }

    private func artifactDiagnostics(_ artifact: ModelArtifactStatus) -> String {
        let state = artifact.isPresent ? "OK" : "missing"
        guard let expectedURL = artifact.expectedURL else {
            return state
        }
        return "\(state) at \(expectedURL.path)"
    }

    private func timingDiagnostics(_ timings: VoicePipelineTimings) -> [String] {
        [
            ("Recording", timings.recording),
            ("Preprocessing", timings.preprocessing),
            ("Transcription", timings.transcription),
            ("Normalization", timings.normalization),
            ("Insertion", timings.insertion)
        ]
        .compactMap { row in
            guard let duration = row.1 else { return nil }
            return "\(row.0): \(String(format: "%.3f", duration))s"
        }
    }

    private func updateStateAfterModelChange() {
        guard permissions.microphonePermissionStatus == .authorized else {
            appState = .missingMicrophonePermission
            errorMessage = Self.microphonePermissionRequiredMessage
            return
        }

        guard permissions.hasAccessibilityPermission else {
            appState = .missingAccessibilityPermission
            errorMessage = Self.accessibilityPermissionRequiredMessage
            return
        }

        errorMessage = nil
        appState = isModelInstalled ? .ready : .missingModel
    }

    private func updateStateAfterIncompleteModelDownload() {
        guard permissions.microphonePermissionStatus == .authorized else {
            appState = .missingMicrophonePermission
            errorMessage = Self.microphonePermissionRequiredMessage
            return
        }

        guard permissions.hasAccessibilityPermission else {
            appState = .missingAccessibilityPermission
            errorMessage = Self.accessibilityPermissionRequiredMessage
            return
        }

        errorMessage = nil
        appState = .missingModel
    }
}

nonisolated enum AppControllerDictionaryImportError: LocalizedError, Equatable, Sendable {
    case stalePreview

    var errorDescription: String? {
        switch self {
        case .stalePreview:
            return "The dictionary changed after the import preview was created. Preview the import again before applying it."
        }
    }
}
