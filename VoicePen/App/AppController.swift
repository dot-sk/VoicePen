import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

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
    let meetingDiarizationModelWarmup: Task<Void, Never>?

    static let empty = AppControllerStartTasks(
        permissions: nil,
        modelWarmup: nil,
        meetingDiarizationModelWarmup: nil
    )
}

struct MainWindowNavigationRequest: Equatable {
    let id: UUID
    let destination: MainWindowDestination

    init(id: UUID = UUID(), destination: MainWindowDestination) {
        self.id = id
        self.destination = destination
    }
}

enum MainWindowDestination: Equatable {
    case meetings
}

enum DictationRuntimeState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
}

@MainActor
final class AppController: ObservableObject {
    @Published var appState: AppState = .starting
    @Published var lastRawText: String = ""
    @Published var lastFinalText: String = ""
    @Published var errorMessage: String?
    @Published var modelDownloadProgress: Double?
    @Published var meetingDiarizationModelDownloadProgress: Double?
    @Published var modelRuntimeState: ModelRuntimeState = .notLoaded
    @Published var meetingDiarizationModelRuntimeState: ModelRuntimeState = .notLoaded
    @Published var meetingElapsedTime: TimeInterval = 0
    @Published var meetingSourceStatus: MeetingSourceStatus = .idle
    @Published var meetingProcessingProgress: MeetingProcessingProgress?
    @Published private(set) var currentMicrophone: DefaultAudioInputDevice = .systemDefaultFallback
    @Published private(set) var mainWindowNavigationRequest: MainWindowNavigationRequest?
    @Published private(set) var userConfigLoadResult = UserConfigLoadResult(config: UserConfig())
    @Published private(set) var modelManifest: ModelManifest
    @Published private(set) var dictationRuntimeState: DictationRuntimeState = .idle

    private let paths: AppPaths
    private let pipeline: DictationPipeline
    private let meetingPipeline: MeetingPipeline?
    private let hotkey: PushToTalkHotkeyClient
    private let permissions: PermissionsClient
    let dictionaryStore: DictionaryStore
    private let inserter: TextInsertionClient
    private let clipboard: TextPasteboard
    private let overlay: OverlayPresenter
    private let transcriptionCancellationKeyMonitor: TranscriptionCancellationKeyMonitor
    private let modelDownloader: ModelDownloadClient
    private let modelWarmupClient: ModelWarmupClient?
    private let meetingDiarizationModelManager: MeetingDiarizationModelManaging?
    private let launchAtLogin: LaunchAtLoginClient
    private let userPrompts: UserPromptPresenter
    private let meetingRecordingReminderPresenter: MeetingRecordingReminderPresenter
    private let environmentSettingsStore: AppEnvironmentSettingsStore
    private let meetingRunningApplicationBundleIdentifiersProvider: () -> Set<String>
    private let dictationProcessingTimeout: Duration
    private let modelDownloadTimeout: Duration
    private let modelWarmupTimeout: Duration
    private let meetingCaptureStartTimeout: Duration
    private let meetingMaximumRecordingDuration: TimeInterval
    private let meetingProcessingTimeout: Duration
    private let defaultInputDeviceProvider: DefaultAudioInputDeviceProviding
    private let appVersionProvider: () -> String
    let historyStore: VoiceHistoryStore
    let meetingHistoryStore: MeetingHistoryStore?
    let settingsStore: AppSettingsStore

    private var didStart = false
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionTimeoutTask: Task<Void, Never>?
    private var recordingStartTask: Task<Void, Never>?
    private var activeRecordingStartID: UUID?
    private var pendingStopAfterRecordingStart = false
    private var recordingPrepareTask: Task<Void, Never>?
    private var activeTranscriptionID: UUID?
    private var activeTranscriptionHistoryEntryID: VoiceHistoryEntry.ID?
    private var didHandleCurrentTranscriptionCancellation = false
    private var isWaitingForCustomShortcut = false
    private var accessibilityPermissionPollingTask: Task<Void, Never>?
    private var defaultInputDeviceObservation: DefaultAudioInputDeviceObservation?
    private var appActivationObserver: AnyCancellable?
    private var workspaceWakeObserver: AnyCancellable?
    private lazy var modelRuntimeStore: AppModelRuntimeStore = {
        AppModelRuntimeStore(environment: modelRuntimeStoreEnvironment)
    }()

    private static let microphonePermissionRequiredMessage = "Microphone permission is required to record dictation audio locally."
    private static let accessibilityPermissionRequiredMessage = "Text insertion permission is required so VoicePen can paste text into the active app."

    private lazy var meetingStore = MeetingRecordingStore(
        environment: MeetingRecordingStore.Environment(
            meetingPipeline: meetingPipeline,
            meetingHistoryStore: meetingHistoryStore,
            permissions: permissions,
            settingsStore: settingsStore,
            userPrompts: userPrompts,
            recordingReminderPresenter: meetingRecordingReminderPresenter,
            captureStartTimeout: meetingCaptureStartTimeout,
            maximumRecordingDuration: meetingMaximumRecordingDuration,
            recordingReminderLeadTime: VoicePenConfig.meetingRecordingReminderLeadTime,
            processingTimeout: meetingProcessingTimeout,
            runningApplicationBundleIdentifiersProvider: meetingRunningApplicationBundleIdentifiersProvider,
            canStartMeetingRecording: { [weak self] in
                self?.canStartMeetingRecording ?? false
            },
            getAppState: { [weak self] in
                self?.appState ?? .starting
            },
            setAppState: { [weak self] state in
                self?.appState = state
            },
            setErrorMessage: { [weak self] message in
                self?.errorMessage = message
            },
            setElapsedTime: { [weak self] elapsedTime in
                self?.meetingElapsedTime = elapsedTime
            },
            setSourceStatus: { [weak self] status in
                self?.meetingSourceStatus = status
            },
            setProcessingProgress: { [weak self] progress in
                self?.meetingProcessingProgress = progress
            },
            presentError: { [weak self] error in
                self?.setError(error)
            },
            refreshBaseState: { [weak self] in
                self?.updateStateAfterModelChange()
            }
        )
    )

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

    var savedAudioDirectory: URL {
        paths.savedAudioDirectory
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

    var canStartMeetingRecording: Bool {
        (appState == .ready || appState == .missingModel || appState == .missingAccessibilityPermission)
            && dictationRuntimeState == .idle
    }

    var canStartDictation: Bool {
        (appState == .ready || appState == .meetingRecording || appState == .meetingProcessing)
            && dictationRuntimeState == .idle
            && !isDownloadingModel
    }

    var isDictationStarting: Bool {
        dictationRuntimeState == .starting
    }

    var isDictationRecording: Bool {
        dictationRuntimeState == .recording
    }

    var isDictationTranscribing: Bool {
        dictationRuntimeState == .transcribing
    }

    var canCancelDictationTranscription: Bool {
        isDictationTranscribing
    }

    private var isMeetingCaptureActive: Bool {
        appState == .meetingRecording || appState == .meetingProcessing
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
            "Languages: \(selectedModel.languageSupportLabel)",
            "Backend: \(selectedModel.sourceKind)",
            "Version: \(selectedModel.version)",
            "Size: \(selectedModel.sizeLabel)",
            "Timestamps: \(selectedModel.supportsTimestamps ? "Supported" : "Unsupported")",
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

    var systemAudioPermissionTitle: String {
        if appState == .missingSystemAudioPermission || !permissions.hasSystemAudioRecordingPermission {
            return "Missing"
        }

        return "Requested on start"
    }

    var runningBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    var runningAppPath: String {
        Bundle.main.bundleURL.path
    }

    var currentMicrophoneStatusText: String {
        "Current microphone: \(currentMicrophone.systemDefaultDisplayText)"
    }

    var menuBarSystemImage: String {
        switch appState {
        case .meetingRecording:
            "record.circle.fill"
        case .meetingProcessing, .downloadingModel, .preparingModel:
            "waveform"
        case .missingMicrophonePermission, .missingAccessibilityPermission, .missingSystemAudioPermission, .missingModel, .error:
            "exclamationmark.triangle.fill"
        default:
            "mic.fill"
        }
    }

    init(
        paths: AppPaths,
        pipeline: DictationPipeline,
        meetingPipeline: MeetingPipeline? = nil,
        hotkey: PushToTalkHotkeyClient,
        permissions: PermissionsClient,
        dictionaryStore: DictionaryStore,
        inserter: TextInsertionClient,
        clipboard: TextPasteboard = NSPasteboard.general,
        overlay: OverlayPresenter,
        transcriptionCancellationKeyMonitor: TranscriptionCancellationKeyMonitor,
        modelDownloader: ModelDownloadClient,
        modelWarmupClient: ModelWarmupClient? = nil,
        meetingDiarizationModelManager: MeetingDiarizationModelManaging? = nil,
        launchAtLogin: LaunchAtLoginClient? = nil,
        userPrompts: UserPromptPresenter,
        meetingRecordingReminderPresenter: MeetingRecordingReminderPresenter = NoOpMeetingRecordingReminderPresenter(),
        environmentSettingsStore: AppEnvironmentSettingsStore? = nil,
        meetingRunningApplicationBundleIdentifiersProvider: @escaping () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        dictationProcessingTimeout: Duration = VoicePenConfig.dictationProcessingTimeout,
        modelDownloadTimeout: Duration = VoicePenConfig.modelDownloadTimeout,
        modelWarmupTimeout: Duration = VoicePenConfig.modelWarmupTimeout,
        meetingCaptureStartTimeout: Duration = VoicePenConfig.meetingCaptureStartTimeout,
        meetingMaximumRecordingDuration: TimeInterval = VoicePenConfig.meetingMaximumRecordingDuration,
        meetingProcessingTimeout: Duration = VoicePenConfig.meetingProcessingTimeout,
        defaultInputDeviceProvider: DefaultAudioInputDeviceProviding = CoreAudioDefaultInputDeviceProvider(),
        appVersionProvider: @escaping () -> String = { VoicePenConfig.appVersion },
        historyStore: VoiceHistoryStore,
        meetingHistoryStore: MeetingHistoryStore? = nil,
        settingsStore: AppSettingsStore,
        modelManifest: ModelManifest
    ) {
        self.paths = paths
        self.pipeline = pipeline
        self.meetingPipeline = meetingPipeline
        self.hotkey = hotkey
        self.permissions = permissions
        self.dictionaryStore = dictionaryStore
        self.inserter = inserter
        self.clipboard = clipboard
        self.overlay = overlay
        self.transcriptionCancellationKeyMonitor = transcriptionCancellationKeyMonitor
        self.modelDownloader = modelDownloader
        self.modelWarmupClient = modelWarmupClient
        self.meetingDiarizationModelManager = meetingDiarizationModelManager
        self.launchAtLogin = launchAtLogin ?? NoOpLaunchAtLoginClient()
        self.userPrompts = userPrompts
        self.meetingRecordingReminderPresenter = meetingRecordingReminderPresenter
        self.environmentSettingsStore = environmentSettingsStore ?? AppEnvironmentSettingsStore()
        self.meetingRunningApplicationBundleIdentifiersProvider = meetingRunningApplicationBundleIdentifiersProvider
        self.dictationProcessingTimeout = dictationProcessingTimeout
        self.modelDownloadTimeout = modelDownloadTimeout
        self.modelWarmupTimeout = modelWarmupTimeout
        self.meetingCaptureStartTimeout = meetingCaptureStartTimeout
        self.meetingMaximumRecordingDuration = meetingMaximumRecordingDuration
        self.meetingProcessingTimeout = meetingProcessingTimeout
        self.defaultInputDeviceProvider = defaultInputDeviceProvider
        self.appVersionProvider = appVersionProvider
        self.historyStore = historyStore
        self.meetingHistoryStore = meetingHistoryStore
        self.settingsStore = settingsStore
        self.modelManifest = modelManifest
        pipeline.setDictationInputGainEligibility { [weak self] in
            self?.appState != .meetingRecording
        }
        currentMicrophone = defaultInputDeviceProvider.currentDefaultInputDevice()
        self.meetingPipeline?.setProcessingProgressHandler { [weak self] progress in
            self?.meetingProcessingProgress = progress
        }
    }

    private var modelRuntimeStoreEnvironment: AppModelRuntimeStore.Environment {
        let modelManifest = modelManifest
        let settingsStore = settingsStore
        let modelDownloader = modelDownloader
        let modelWarmupClient = modelWarmupClient
        let meetingDiarizationModelManager = meetingDiarizationModelManager
        let paths = paths
        let modelDownloadTimeout = modelDownloadTimeout
        let modelWarmupTimeout = modelWarmupTimeout

        return AppModelRuntimeStore.Environment(
            selectedModel: { [settingsStore, modelManifest] in
                modelManifest.compatibleModels.first { $0.id == settingsStore.selectedModelId }
                    ?? modelManifest.recommendedModel
            },
            transcriptionLanguage: { [settingsStore] in
                TranscriptionLanguageResolver.resolve(settingsStore.transcriptionLanguage)
            },
            modelDownloader: { modelDownloader },
            modelWarmupClient: { modelWarmupClient },
            meetingDiarizationModelManager: { meetingDiarizationModelManager },
            isModelInstalled: { [weak self] in self?.isModelInstalled ?? false },
            isMeetingDiarizationModelInstalled: { [weak self] in self?.isMeetingDiarizationModelInstalled ?? false },
            isMeetingDiarizationEnabled: { [settingsStore] in settingsStore.meetingDiarizationEnabled },
            canStartDictationRuntime: { [weak self] in self?.dictationRuntimeState == .idle },
            canScheduleLifecycleModelWarmup: { [weak self] in
                guard let self else { return false }
                let isDownloadingModelState: Bool
                switch appState {
                case .downloadingModel, .preparingModel:
                    isDownloadingModelState = true
                default:
                    isDownloadingModelState = false
                }
                return appState != .meetingRecording && appState != .meetingProcessing && dictationRuntimeState == .idle && !isDownloadingModelState
            },
            canDeleteModelFiles: { [weak self] in
                guard let self else { return false }
                let isDownloadingModelState: Bool
                switch appState {
                case .downloadingModel, .preparingModel:
                    isDownloadingModelState = true
                default:
                    isDownloadingModelState = false
                }
                return !isDownloadingModelState && appState != .meetingRecording && appState != .meetingProcessing && dictationRuntimeState == .idle
            },
            canDeleteMeetingDiarizationModelFiles: { [weak self] in
                guard let self else { return false }
                let isDownloadingModelState: Bool
                switch appState {
                case .downloadingModel, .preparingModel:
                    isDownloadingModelState = true
                default:
                    isDownloadingModelState = false
                }
                return !isDownloadingModelState && appState != .meetingRecording && appState != .meetingProcessing && dictationRuntimeState == .idle
            },
            userModelDirectory: { [weak self, paths] in
                self?.userModelDirectory ?? paths.userModelDirectory
            },
            meetingDiarizationModelDirectory: { [meetingDiarizationModelManager, paths] in
                meetingDiarizationModelManager?.modelDirectory ?? paths.diarizationModelsDirectory
            },
            modelDownloadTimeout: { modelDownloadTimeout },
            modelWarmupTimeout: { modelWarmupTimeout },
            lifecycleWarmupCooldown: { VoicePenConfig.modelWarmupLifecycleCooldown },
            setAppState: { [weak self] in self?.appState = $0 },
            setModelRuntimeState: { [weak self] in self?.modelRuntimeState = $0 },
            setMeetingDiarizationModelRuntimeState: { [weak self] in self?.meetingDiarizationModelRuntimeState = $0 },
            setModelDownloadProgress: { [weak self] in self?.modelDownloadProgress = $0 },
            setMeetingDiarizationModelDownloadProgress: { [weak self] in
                self?.meetingDiarizationModelDownloadProgress = $0
            },
            setErrorMessage: { [weak self] in self?.errorMessage = $0 },
            showOverlay: { [weak self] in self?.overlay.show($0) },
            hideOverlayAfter: { [weak self] in self?.overlay.hide(after: $0) },
            updateStateAfterModelChange: { [weak self] in self?.updateStateAfterModelChange() },
            updateStateAfterIncompleteModelDownload: { [weak self] in self?.updateStateAfterIncompleteModelDownload() },
            setError: { [weak self] in self?.setError($0) }
        )
    }

    deinit {
        recordingPrepareTask?.cancel()
        defaultInputDeviceObservation?.cancel()
    }

    static func live() -> AppController {
        let paths = AppPaths()
        let modelManifest = LocalModelManifestStore().loadManifestOrDefault()
        let recommendedModel = modelManifest.recommendedModel
        let dictionaryStore = DictionaryStore(dictionaryURL: paths.dictionaryURL)
        let historyStore = VoiceHistoryStore(historyURL: paths.historyURL)
        let meetingHistoryStore = MeetingHistoryStore(databaseURL: paths.databaseURL)
        let settingsStore = AppSettingsStore(databaseURL: paths.databaseURL)
        let dictationMicrophoneCapture = CoreAudioMicrophoneCapture()
        let recorder = LiveAudioRecordingClient(
            tempDirectory: paths.tempAudioDirectory,
            microphoneCapture: dictationMicrophoneCapture
        )
        let overlay = BottomOverlayWindowController(recordingLevelProvider: {
            recorder.currentLevel()
        })
        let audioPreprocessor = LiveAudioPreprocessingClient(outputDirectory: paths.tempAudioDirectory)
        let savedAudioArchive = SavedAudioArchive(paths: paths)
        let savedAudioScheduler = AsyncSavedAudioArchiveScheduler(archiver: savedAudioArchive) { owner, archivedURL in
            Task { @MainActor in
                do {
                    switch owner {
                    case let .voiceHistory(id):
                        try historyStore.appendArchivedAudioURL(archivedURL, for: id)
                    case let .meetingHistory(id):
                        try meetingHistoryStore.appendArchivedAudioURL(archivedURL, for: id)
                    }
                } catch {
                    AppLogger.error("Failed to link archived audio to history: \(error.localizedDescription)")
                }
            }
        }
        let whisperCppTranscriber = WhisperCppTranscriptionClient(paths: paths)
        let inserter = PasteboardTextInsertionClient(restoreDelay: VoicePenConfig.clipboardRestoreDelay)
        let userConfigStore = UserConfigStore()
        let userPrompts = NSAlertUserPromptPresenter()
        let transcriber = RoutingTranscriptionClient(
            modelProvider: {
                modelManifest.compatibleModels.first { $0.id == settingsStore.selectedModelId }
                    ?? recommendedModel
            },
            whisperCppClient: whisperCppTranscriber
        )
        let pipeline = DictationPipeline(
            recorder: recorder,
            audioPreprocessor: audioPreprocessor,
            transcriber: transcriber,
            dictionaryStore: dictionaryStore,
            inserter: inserter,
            overlay: overlay,
            userConfigStore: userConfigStore,
            inputGainController: CoreAudioDefaultInputGainController(),
            savedAudioScheduler: savedAudioScheduler,
            languageProvider: { settingsStore.transcriptionLanguage },
            speechPreprocessingModeProvider: { settingsStore.speechPreprocessingMode },
            boostDictationInputGainProvider: { settingsStore.boostDictationInputGain },
            saveDictationAudioEnabledProvider: { settingsStore.saveDictationAudioEnabled },
            savedAudioStorageLimitGBProvider: { settingsStore.savedAudioStorageLimitGB },
            developerModesEnabledProvider: { VoicePenConfig.modesFeatureEnabled },
            llmIntentParserEnabledProvider: { VoicePenConfig.aiFeatureEnabled },
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
        let meetingAudioFileIO = AVFoundationMeetingAudioFileIO()
        let meetingDiarizationClient = SpeakerKitMeetingDiarizationClient(
            cacheDirectory: paths.diarizationModelsDirectory,
            selectedBackendProvider: { settingsStore.meetingDiarizationBackend },
            audioFileIO: meetingAudioFileIO
        )
        let meetingPipeline = MeetingPipeline(
            recorder: CompositeMeetingRecordingClient(
                microphoneSource: CoreAudioMicrophoneMeetingAudioSource(
                    tempDirectory: paths.tempAudioDirectory,
                    audioFileIO: meetingAudioFileIO
                ),
                systemAudioSource: CoreAudioSystemOutputSource(
                    tempDirectory: paths.tempAudioDirectory,
                    settingsProvider: {
                        MeetingSystemAudioSourceSettings(
                            mode: settingsStore.meetingSystemAudioSourceMode,
                            selectedApps: settingsStore.meetingAudioAppSelections
                        )
                    },
                    audioFileIO: meetingAudioFileIO
                )
            ),
            audioPreprocessor: audioPreprocessor,
            voiceLevelingProcessor: SystemVoiceLevelingProcessor(outputDirectory: paths.tempAudioDirectory),
            chunker: AVFoundationMeetingAudioChunker(
                outputDirectory: paths.tempAudioDirectory,
                audioFileIO: meetingAudioFileIO
            ),
            audioFileIO: meetingAudioFileIO,
            transcriber: transcriber,
            diarizer: meetingDiarizationClient,
            historyStore: meetingHistoryStore,
            recoveryAudioStore: MeetingRecoveryAudioStore(directory: paths.meetingRecoveryDirectory),
            savedAudioScheduler: savedAudioScheduler,
            languageProvider: { settingsStore.transcriptionLanguage },
            speechPreprocessingModeProvider: { settingsStore.speechPreprocessingMode },
            meetingVoiceLevelingEnabledProvider: { settingsStore.meetingVoiceLevelingEnabled },
            saveMeetingAudioEnabledProvider: { settingsStore.saveMeetingAudioEnabled },
            savedAudioStorageLimitGBProvider: { settingsStore.savedAudioStorageLimitGB },
            meetingTranscriptTimecodesEnabledProvider: {
                settingsStore.meetingTranscriptTimecodesEnabled
            },
            meetingDiarizationEnabledProvider: {
                settingsStore.meetingDiarizationEnabled
            },
            meetingDiarizationBackendProvider: {
                settingsStore.meetingDiarizationBackend
            }
        )

        let controller = AppController(
            paths: paths,
            pipeline: pipeline,
            meetingPipeline: meetingPipeline,
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
                )
            ),
            modelWarmupClient: transcriber,
            meetingDiarizationModelManager: meetingDiarizationClient,
            launchAtLogin: LiveLaunchAtLoginClient(),
            userPrompts: userPrompts,
            meetingRecordingReminderPresenter: UserNotificationMeetingRecordingReminderPresenter.shared,
            environmentSettingsStore: userConfigStore,
            historyStore: historyStore,
            meetingHistoryStore: meetingHistoryStore,
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
            return modelRuntimeStore.isDownloadingModel
        default:
            return false
        }
    }

    var isDownloadingMeetingDiarizationModel: Bool {
        modelRuntimeStore.isDownloadingMeetingDiarizationModel
    }

    var isMeetingDiarizationModelInstalled: Bool {
        meetingDiarizationModelManager?.isModelInstalled ?? false
    }

    var meetingDiarizationModelDirectory: URL {
        meetingDiarizationModelManager?.modelDirectory ?? paths.diarizationModelsDirectory
    }

    var meetingDiarizationModelStatusTitle: String {
        if isDownloadingMeetingDiarizationModel {
            return "Downloading"
        }
        switch meetingDiarizationModelRuntimeState {
        case .warming:
            return "Warming up"
        case .failed:
            return "Failed"
        case .ready, .notLoaded:
            break
        }
        if isMeetingDiarizationModelInstalled {
            return "Installed"
        }
        return "Missing"
    }

    @discardableResult
    func start() -> AppControllerStartTasks {
        guard !didStart else { return .empty }
        didStart = true

        let modelWarmup: Task<Void, Never>?
        let meetingDiarizationModelWarmup: Task<Void, Never>?
        do {
            try paths.createRequiredDirectories()
            try paths.cleanOldTemporaryAudioFiles()
            reloadUserConfig()
            try dictionaryStore.load()
            try historyStore.load()
            try meetingHistoryStore?.load()
            try meetingHistoryStore?.cleanupExpiredRecoveryAudio()
            try settingsStore.load(defaultModelId: recommendedModel.id)
            applyAppAppearanceMode(settingsStore.appAppearanceMode)
            try syncOpenAtLoginState()
            refreshCurrentMicrophone()
            startDefaultInputDeviceObservation()
            modelWarmup = modelRuntimeStore.scheduleModelWarmupIfInstalled()
            meetingDiarizationModelWarmup = modelRuntimeStore.scheduleMeetingDiarizationModelWarmupIfNeeded()
        } catch {
            setError(error)
            return .empty
        }

        let permissions = Task {
            await requestStartupPermissions()
        }

        appActivationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let controller = self else { return }
                Task { @MainActor [controller] in
                    controller.refreshPermissionState()
                    controller.refreshOpenAtLoginState()
                    controller.scheduleLifecycleModelWarmupIfPossible()
                    controller.schedulePrepareRecordingIfPossible()
                }
            }

        workspaceWakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let controller = self else { return }
                Task { @MainActor [controller] in
                    controller.scheduleLifecycleModelWarmupIfPossible()
                    controller.invalidatePreparedRecordingAndPrepareIfPossible()
                }
            }

        return AppControllerStartTasks(
            permissions: permissions,
            modelWarmup: modelWarmup,
            meetingDiarizationModelWarmup: meetingDiarizationModelWarmup
        )
    }

    private func refreshCurrentMicrophone() {
        currentMicrophone = defaultInputDeviceProvider.currentDefaultInputDevice()
    }

    private func startDefaultInputDeviceObservation() {
        defaultInputDeviceObservation?.cancel()
        defaultInputDeviceObservation = defaultInputDeviceProvider.observeDefaultInputDeviceChanges { [weak self] device in
            self?.currentMicrophone = device
            self?.invalidatePreparedRecordingAndPrepareIfPossible()
        }
    }

    private func schedulePrepareRecordingIfPossible() {
        guard permissions.microphonePermissionStatus == .authorized,
            appState != .meetingRecording,
            appState != .meetingProcessing,
            dictationRuntimeState == .idle
        else {
            return
        }

        let pipeline = pipeline
        recordingPrepareTask?.cancel()
        recordingPrepareTask = Task { [pipeline, weak self] in
            await pipeline.prepareForRecording()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.recordingPrepareTask = nil
            }
        }
    }

    private func invalidatePreparedRecordingAndPrepareIfPossible() {
        let pipeline = pipeline
        recordingPrepareTask?.cancel()
        recordingPrepareTask = Task { [pipeline, weak self] in
            await pipeline.invalidatePreparedRecording()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.recordingPrepareTask = nil
                self.schedulePrepareRecordingIfPossible()
            }
        }
    }

    private func scheduleLifecycleModelWarmupIfPossible() {
        modelRuntimeStore.scheduleLifecycleModelWarmupIfPossible()
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
        appState = isModelInstalled ? .ready : .missingModel
        schedulePrepareRecordingIfPossible()
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
        guard canStartDictation else { return nil }

        cancelModelWarmup()
        let startID = UUID()
        activeRecordingStartID = startID
        pendingStopAfterRecordingStart = false
        dictationRuntimeState = .starting
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await pipeline.start()
                guard activeRecordingStartID == startID else { return }
                dictationRuntimeState = .recording
                recordingStartTask = nil
                activeRecordingStartID = nil

                if pendingStopAfterRecordingStart {
                    pendingStopAfterRecordingStart = false
                    stopRecordingAndProcess()
                }
            } catch {
                guard activeRecordingStartID == startID else { return }
                recordingStartTask = nil
                activeRecordingStartID = nil
                pendingStopAfterRecordingStart = false
                dictationRuntimeState = .idle
                presentDictationErrorPreservingMeetingState(error)
            }
        }
        recordingStartTask = task
        return task
    }

    @discardableResult
    func stopRecordingAndProcess() -> Task<Void, Never>? {
        if dictationRuntimeState == .starting, let recordingStartTask {
            pendingStopAfterRecordingStart = true
            return Task { @MainActor [weak self] in
                await recordingStartTask.value
                await self?.transcriptionTask?.value
            }
        }

        guard dictationRuntimeState == .recording, transcriptionTask == nil else { return nil }
        if let recordingStartTask {
            pendingStopAfterRecordingStart = true
            return Task { @MainActor [weak self] in
                await recordingStartTask.value
                await self?.transcriptionTask?.value
            }
        }

        return beginStopRecordingAndProcess()
    }

    @discardableResult
    private func beginStopRecordingAndProcess() -> Task<Void, Never>? {
        didHandleCurrentTranscriptionCancellation = false
        let transcriptionID = UUID()
        let historyEntryID = UUID()
        activeTranscriptionID = transcriptionID
        activeTranscriptionHistoryEntryID = historyEntryID
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                finishTranscriptionProcessing(id: transcriptionID)
                schedulePrepareRecordingIfPossible()
            }

            do {
                dictationRuntimeState = .transcribing
                transcriptionCancellationKeyMonitor.install { [weak self] in
                    self?.cancelTranscription()
                }
                startTranscriptionTimeoutMonitor(id: transcriptionID)
                let result = try await pipeline.stopAndProcess(archiveOwner: .voiceHistory(historyEntryID))
                try Task.checkCancellation()
                guard activeTranscriptionID == transcriptionID else { return }
                lastRawText = result.rawText
                lastFinalText = result.finalText
                recordHistory(for: result, id: historyEntryID)
                if !isMeetingCaptureActive {
                    updateStateAfterModelChange()
                }
            } catch is CancellationError {
                handleTranscriptionCancellation()
            } catch let error as TranscriptionError {
                handleTranscriptionError(error, historyEntryID: historyEntryID)
            } catch {
                presentDictationErrorPreservingMeetingState(error)
            }
        }
        transcriptionTask = task
        return task
    }

    func cancelTranscription() {
        guard dictationRuntimeState == .transcribing else { return }
        transcriptionTask?.cancel()
        finishTranscriptionProcessing(id: activeTranscriptionID)
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

    func openUserConfigFile() {
        do {
            try environmentSettingsStore.ensureUserConfigFileExists()
            NSWorkspace.shared.open(environmentSettingsStore.userConfigURL)
        } catch {
            setError(error)
        }
    }

    func setMeetingRecordingReminderClickAction(_ action: @escaping @MainActor () -> Void) {
        meetingRecordingReminderPresenter.setReminderClickAction(action)
    }

    func requestMainWindowNavigation(_ destination: MainWindowDestination) {
        mainWindowNavigationRequest = MainWindowNavigationRequest(destination: destination)
    }

    @discardableResult
    func reloadUserConfig() -> UserConfigLoadResult {
        let result = environmentSettingsStore.loadConfig()
        applyEnvironment(result.config.env)
        userConfigLoadResult = result
        return result
    }

    func updateDeveloperIntentParserSettings(_ update: (inout DeveloperIntentParserConfig) -> Void) throws {
        var config = userConfigLoadResult.config
        update(&config.developer.intentParser)
        try saveLLMAndIntentParserSettings(config)
    }

    private func saveLLMAndIntentParserSettings(_ config: UserConfig) throws {
        let result = try environmentSettingsStore.saveLLMAndIntentParserSettings(
            llm: config.llm,
            intentParser: config.developer.intentParser
        )
        applyEnvironment(result.config.env)
        userConfigLoadResult = result
    }

    func copyToClipboard(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        clipboard.clearContents()
        _ = clipboard.setString(trimmedText, forType: .string)
    }

    private func applyEnvironment(_ environment: [String: String]) {
        for (key, value) in environment {
            setenv(key, value, 1)
        }
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
        guard let text = clipboard.string(forType: .string)?.trimmed, !text.isEmpty else {
            throw AppControllerDictionaryImportError.invalidClipboard
        }
        guard Self.isPlausibleDictionaryCSV(text) else {
            throw AppControllerDictionaryImportError.invalidClipboard
        }

        do {
            return try prepareDictionaryImportPreview(
                csvText: text,
                historyLimit: historyLimit
            )
        } catch is DictionaryCSVImporterError {
            throw AppControllerDictionaryImportError.invalidClipboard
        } catch {
            throw error
        }
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

    private static func isPlausibleDictionaryCSV(_ text: String) -> Bool {
        let maximumClipboardBytes = 512 * 1024
        guard text.utf8.prefix(maximumClipboardBytes + 1).count <= maximumClipboardBytes else {
            return false
        }

        let sample = text.prefix(16 * 1024)
        var checkedRows = 0
        for rawLine in sample.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            if checkedRows == 0, Self.isDictionaryCSVHeader(fields) {
                checkedRows += 1
                continue
            }

            checkedRows += 1
            guard fields.count >= 2 else {
                if checkedRows >= 10 { break }
                continue
            }

            let canonical = fields.first ?? ""
            let variants = fields.dropFirst().joined(separator: ",").trimmed
            if !canonical.isEmpty, !variants.isEmpty {
                return true
            }

            if checkedRows >= 10 {
                break
            }
        }

        return false
    }

    private static func isDictionaryCSVHeader(_ fields: [String]) -> Bool {
        guard let first = fields.first?.lowercased() else {
            return false
        }
        return ["canonical", "term", "каноническая форма", "термин"].contains(first)
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

    func openSavedRecordingsFolder() {
        do {
            try paths.createRequiredDirectories()
            NSWorkspace.shared.open(paths.savedAudioDirectory)
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

    func requestSystemAudioRecordingPermission() {
        permissions.requestSystemAudioRecordingPermission()
        openSystemAudioRecordingSettings()
        refreshPermissionState()
    }

    func openSystemAudioRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func refreshPermissionState() {
        guard dictationRuntimeState == .idle,
            appState != .meetingRecording,
            appState != .meetingProcessing,
            !isDownloadingModel
        else { return }

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
        modelRuntimeStore.downloadModel()
    }

    @discardableResult
    func cancelModelDownload() -> Task<Void, Never>? {
        modelRuntimeStore.cancelModelDownload()
    }

    @discardableResult
    func downloadMeetingDiarizationModel() -> Task<Void, Never>? {
        modelRuntimeStore.downloadMeetingDiarizationModel()
    }

    @discardableResult
    func warmUpMeetingDiarizationModel() -> Task<Void, Never>? {
        modelRuntimeStore.warmUpMeetingDiarizationModel()
    }

    @discardableResult
    func cancelMeetingDiarizationModelDownload() -> Task<Void, Never>? {
        modelRuntimeStore.cancelMeetingDiarizationModelDownload()
    }

    func deleteMeetingDiarizationModelFiles() {
        modelRuntimeStore.deleteMeetingDiarizationModelFiles()
    }

    func deleteDownloadedModelFiles() {
        modelRuntimeStore.deleteDownloadedModelFiles()
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

    @discardableResult
    func startMeetingRecording() -> Task<Void, Never>? {
        meetingStore.start()
    }

    @discardableResult
    func stopMeetingRecording() -> Task<Void, Never>? {
        meetingStore.stop()
    }

    @discardableResult
    func cancelMeetingRecording() -> Task<Void, Never>? {
        meetingStore.cancel()
    }

    @discardableResult
    func cancelMeetingProcessing() -> Task<Void, Never>? {
        meetingStore.cancelProcessing()
    }

    func copyMeetingTranscript(_ entry: MeetingHistoryEntry) {
        do {
            let resolvedEntry = try meetingHistoryStore?.loadEntry(id: entry.id) ?? entry
            copyToClipboard(resolvedEntry.transcriptText)
        } catch {
            setError(error)
        }
    }

    func cleanupExpiredMeetingRecoveryAudio() {
        do {
            try meetingHistoryStore?.cleanupExpiredRecoveryAudio()
        } catch {
            setError(error)
        }
    }

    @discardableResult
    func retryMeetingProcessing(_ entry: MeetingHistoryEntry) -> Task<Void, Never>? {
        do {
            let resolvedEntry = try meetingHistoryStore?.loadEntry(id: entry.id) ?? entry
            return meetingStore.retry(resolvedEntry)
        } catch {
            setError(error)
            return nil
        }
    }

    func deleteMeetingEntry(id: MeetingHistoryEntry.ID) {
        meetingStore.deleteEntry(id: id)
    }

    func deleteHistoryEntry(id: VoiceHistoryEntry.ID) {
        do {
            try historyStore.delete(id: id)
        } catch {
            setError(error)
        }
    }

    func existingArchivedAudioURLs(for entry: VoiceHistoryEntry) -> [URL] {
        existingArchivedAudioURLs(in: entry.archivedAudioURLs)
    }

    func existingArchivedAudioURLs(for entry: MeetingHistoryEntry) -> [URL] {
        existingArchivedAudioURLs(in: entry.archivedAudioURLs)
    }

    func revealArchivedAudio(for entry: VoiceHistoryEntry) {
        revealArchivedAudio(entry.archivedAudioURLs)
    }

    func revealArchivedAudio(for entry: MeetingHistoryEntry) {
        revealArchivedAudio(entry.archivedAudioURLs)
    }

    private func revealArchivedAudio(_ urls: [URL]) {
        let existingURLs = existingArchivedAudioURLs(in: urls)
        guard !existingURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existingURLs)
    }

    private func existingArchivedAudioURLs(in urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
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
            guard dictationRuntimeState == .idle else { return }

            guard modelManifest.compatibleModels.contains(where: { $0.id == modelId }) else {
                throw TranscriptionError.unsupportedModel(modelId)
            }
            try settingsStore.updateSelectedModelId(modelId)
            _ = modelRuntimeStore.scheduleModelWarmupIfInstalled()
        } catch {
            setError(error)
        }
    }

    @discardableResult
    private func scheduleModelWarmupIfInstalled() -> Task<Void, Never>? {
        modelRuntimeStore.scheduleModelWarmupIfInstalled()
    }

    private func cancelModelWarmup() {
        modelRuntimeStore.cancelModelWarmup()
    }

    @discardableResult
    private func scheduleMeetingDiarizationModelWarmupIfNeeded() -> Task<Void, Never>? {
        modelRuntimeStore.scheduleMeetingDiarizationModelWarmupIfNeeded()
    }

    func updateSpeechPreprocessingMode(_ mode: SpeechPreprocessingMode) {
        do {
            try settingsStore.updateSpeechPreprocessingMode(mode)
        } catch {
            setError(error)
        }
    }

    func updateBoostDictationInputGain(_ isEnabled: Bool) {
        do {
            try settingsStore.updateBoostDictationInputGain(isEnabled)
        } catch {
            setError(error)
        }
    }

    func updateMeetingVoiceLevelingEnabled(_ isEnabled: Bool) {
        do {
            try settingsStore.updateMeetingVoiceLevelingEnabled(isEnabled)
        } catch {
            setError(error)
        }
    }

    func updateSaveDictationAudioEnabled(_ isEnabled: Bool) {
        do {
            try settingsStore.updateSaveDictationAudioEnabled(isEnabled)
        } catch {
            setError(error)
        }
    }

    func updateSaveMeetingAudioEnabled(_ isEnabled: Bool) {
        do {
            try settingsStore.updateSaveMeetingAudioEnabled(isEnabled)
        } catch {
            setError(error)
        }
    }

    func updateSavedAudioStorageLimitGB(_ limit: Int) {
        do {
            try settingsStore.updateSavedAudioStorageLimitGB(limit)
        } catch {
            setError(error)
        }
    }

    func updateMeetingTranscriptTimecodesEnabled(_ isEnabled: Bool) {
        do {
            try settingsStore.updateMeetingTranscriptTimecodesEnabled(isEnabled)
        } catch {
            setError(error)
        }
    }

    func updateMeetingSystemAudioSourceMode(_ mode: MeetingSystemAudioSourceMode) {
        do {
            try settingsStore.updateMeetingSystemAudioSourceMode(mode)
        } catch {
            setError(error)
        }
    }

    @discardableResult
    func updateMeetingDiarizationEnabled(_ isEnabled: Bool) -> Task<Void, Never>? {
        do {
            try settingsStore.updateMeetingDiarizationEnabled(isEnabled)
            if isEnabled {
                return modelRuntimeStore.scheduleMeetingDiarizationModelWarmupIfNeeded()
            } else {
                modelRuntimeStore.cancelMeetingDiarizationModelWarmup()
                meetingDiarizationModelRuntimeState = .notLoaded
            }
        } catch {
            setError(error)
        }
        return nil
    }

    func chooseMeetingSystemAudioApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = "Choose apps to include or exclude from Meeting system audio."
        guard panel.runModal() == .OK else { return }
        addMeetingSystemAudioApps(at: panel.urls)
    }

    func addMeetingSystemAudioApp(at appURL: URL) {
        addMeetingSystemAudioApps(at: [appURL])
    }

    func addMeetingSystemAudioApps(at appURLs: [URL]) {
        let selections = appURLs.compactMap(meetingAudioAppSelection)
        guard !selections.isEmpty else {
            errorMessage = "Choose a valid macOS app with a bundle identifier."
            return
        }
        addMeetingSystemAudioApps(selections)
    }

    func addMeetingSystemAudioApp(_ selection: MeetingAudioAppSelection) {
        addMeetingSystemAudioApps([selection])
    }

    func addMeetingSystemAudioApps(_ selections: [MeetingAudioAppSelection]) {
        do {
            try settingsStore.updateMeetingAudioAppSelections(settingsStore.meetingAudioAppSelections + selections)
        } catch {
            setError(error)
        }
    }

    func removeMeetingSystemAudioApp(bundleIdentifier: String) {
        do {
            try settingsStore.updateMeetingAudioAppSelections(
                settingsStore.meetingAudioAppSelections.filter { $0.bundleIdentifier != bundleIdentifier }
            )
        } catch {
            setError(error)
        }
    }

    private func meetingAudioAppSelection(at appURL: URL) -> MeetingAudioAppSelection? {
        guard let bundle = Bundle(url: appURL), let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }
        let displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let selection = MeetingAudioAppSelection(displayName: displayName, bundleIdentifier: bundleIdentifier)
        return selection.isValid ? selection : nil
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

    func updateAppAppearanceMode(_ mode: AppAppearanceMode) {
        do {
            try settingsStore.updateAppAppearanceMode(mode)
            applyAppAppearanceMode(mode)
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

    private func applyAppAppearanceMode(_ mode: AppAppearanceMode) {
        switch mode {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func handleTranscriptionError(
        _ error: TranscriptionError,
        historyEntryID: VoiceHistoryEntry.ID = UUID()
    ) {
        switch error {
        case .modelMissing:
            if !isMeetingCaptureActive {
                appState = .missingModel
            }
            errorMessage = error.localizedDescription
            overlay.show(.error(message: error.shortMessage))
            overlay.hide(after: 2.0)
        default:
            presentDictationErrorPreservingMeetingState(error)
        }
        recordHistory(
            rawText: "",
            finalText: "",
            status: .failed,
            errorMessage: error.localizedDescription,
            recording: nil,
            timings: nil,
            id: historyEntryID
        )
    }

    private func handleTranscriptionCancellation() {
        guard !didHandleCurrentTranscriptionCancellation else { return }

        didHandleCurrentTranscriptionCancellation = true
        overlay.show(.done(message: "Canceled"))
        overlay.hide(after: 0.7)
        if !isMeetingCaptureActive {
            updateStateAfterModelChange()
        }
        dictationRuntimeState = .idle
    }

    private func startTranscriptionTimeoutMonitor(id: UUID) {
        transcriptionTimeoutTask?.cancel()
        let timeout = dictationProcessingTimeout
        transcriptionTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            self?.handleTranscriptionTimeout(id: id)
        }
    }

    private func handleTranscriptionTimeout(id: UUID) {
        guard activeTranscriptionID == id,
            dictationRuntimeState == .transcribing
        else { return }

        AppLogger.error("Dictation processing timed out")
        didHandleCurrentTranscriptionCancellation = true
        transcriptionTask?.cancel()
        let historyEntryID = activeTranscriptionHistoryEntryID ?? UUID()
        finishTranscriptionProcessing(id: id)
        handleTranscriptionError(.transcriptionTimedOut, historyEntryID: historyEntryID)
    }

    private func finishTranscriptionProcessing(id: UUID?) {
        guard activeTranscriptionID == id else { return }

        transcriptionCancellationKeyMonitor.uninstall()
        transcriptionTimeoutTask?.cancel()
        transcriptionTimeoutTask = nil
        transcriptionTask = nil
        activeTranscriptionID = nil
        activeTranscriptionHistoryEntryID = nil
        dictationRuntimeState = .idle
    }

    private func presentDictationErrorPreservingMeetingState(_ error: Error) {
        let overlayMessage = (error as? TranscriptionError)?.shortMessage ?? error.localizedDescription
        if isMeetingCaptureActive {
            errorMessage = error.localizedDescription
            overlay.show(.error(message: overlayMessage))
            overlay.hide(after: 2.0)
            return
        }

        if let transcriptionError = error as? TranscriptionError {
            appState = .error(transcriptionError.localizedDescription)
            errorMessage = transcriptionError.localizedDescription
            overlay.show(.error(message: transcriptionError.shortMessage))
            overlay.hide(after: 2.0)
            return
        }

        setError(error)
    }

    private func setError(_ error: Error) {
        appState = .error(error.localizedDescription)
        errorMessage = error.localizedDescription
        overlay.show(.error(message: error.localizedDescription))
        overlay.hide(after: 2.0)
    }

    private func recordHistory(for result: DictationPipelineResult, id: VoiceHistoryEntry.ID = UUID()) {
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
            diagnosticNotes: result.diagnosticNotes,
            id: id
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
        diagnosticNotes: [String] = [],
        id: VoiceHistoryEntry.ID = UUID()
    ) {
        let trimmedRawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFinalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUsefulContent = !trimmedRawText.isEmpty || !trimmedFinalText.isEmpty || errorMessage != nil
        guard hasUsefulContent else { return }

        let entry = VoiceHistoryEntry(
            id: id,
            createdAt: recording?.endedAt ?? Date(),
            duration: recording?.duration,
            rawText: rawText,
            finalText: finalText,
            status: status,
            errorMessage: errorMessage,
            timings: timings,
            modelMetadata: (modelMetadata ?? VoiceTranscriptionModelMetadata(model: selectedModel))
                .withAppVersion(appVersionProvider()),
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
        appState = isModelInstalled ? .ready : .missingModel
        schedulePrepareRecordingIfPossible()
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
    case invalidClipboard
    case stalePreview

    var errorDescription: String? {
        switch self {
        case .invalidClipboard:
            return "Clipboard does not contain valid dictionary CSV."
        case .stalePreview:
            return "The dictionary changed after the import preview was created. Preview the import again before applying it."
        }
    }
}
