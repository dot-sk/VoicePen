import Foundation

@MainActor
final class AppModelRuntimeStore {
    static let meetingDiarizationModelId = "meeting-diarization"

    struct State {
        var activeModelDownloadID: UUID?
        var activeMeetingDiarizationModelDownloadID: UUID?
        var modelDownloadTask: Task<Void, Never>?
        var meetingDiarizationModelDownloadTask: Task<Void, Never>?
        var modelWarmupTask: Task<Void, Never>?
        var meetingDiarizationModelWarmupTask: Task<Void, Never>?
        var lastLifecycleModelWarmupDate: Date?

        var isModelDownloadInProgress: Bool {
            activeModelDownloadID != nil
        }

        var isMeetingDiarizationModelDownloadInProgress: Bool {
            activeMeetingDiarizationModelDownloadID != nil
        }
    }

    enum Action {
        case modelDownloadStarted(UUID)
        case modelDownloadTask(Task<Void, Never>?)
        case modelDownloadFinished
        case meetingDiarizationModelDownloadStarted(UUID)
        case meetingDiarizationModelDownloadTask(Task<Void, Never>?)
        case meetingDiarizationModelDownloadFinished
        case modelWarmupTask(Task<Void, Never>?)
        case modelWarmupFinished
        case meetingDiarizationModelWarmupTask(Task<Void, Never>?)
        case meetingDiarizationModelWarmupFinished
        case setModelDownloadProgress(Double?)
        case setMeetingDiarizationModelDownloadProgress(Double?)
        case setLifecycleWarmupDate(Date?)
    }

    struct Environment {
        let selectedModel: () -> ModelManifestModel
        let transcriptionLanguage: () -> String
        let modelDownloader: () -> ModelDownloadClient
        let modelWarmupClient: () -> ModelWarmupClient?
        let meetingDiarizationModelManager: () -> MeetingDiarizationModelManaging?
        let isModelInstalled: () -> Bool
        let isMeetingDiarizationModelInstalled: () -> Bool
        let isMeetingDiarizationEnabled: () -> Bool
        let canStartDictationRuntime: () -> Bool
        let canScheduleLifecycleModelWarmup: () -> Bool
        let canDeleteModelFiles: () -> Bool
        let canDeleteMeetingDiarizationModelFiles: () -> Bool
        let userModelDirectory: () -> URL
        let meetingDiarizationModelDirectory: () -> URL
        let modelDownloadTimeout: () -> Duration
        let modelWarmupTimeout: () -> Duration
        let lifecycleWarmupCooldown: () -> TimeInterval

        let setAppState: @MainActor (AppState) -> Void
        let setModelRuntimeState: @MainActor (ModelRuntimeState) -> Void
        let setMeetingDiarizationModelRuntimeState: @MainActor (ModelRuntimeState) -> Void
        let setModelDownloadProgress: @MainActor (Double?) -> Void
        let setMeetingDiarizationModelDownloadProgress: @MainActor (Double?) -> Void
        let setErrorMessage: @MainActor (String?) -> Void
        let showOverlay: @MainActor (OverlayState) -> Void
        let hideOverlayAfter: @MainActor (TimeInterval) -> Void
        let updateStateAfterModelChange: @MainActor () -> Void
        let updateStateAfterIncompleteModelDownload: @MainActor () -> Void
        let setError: @MainActor (Error) -> Void
    }

    private(set) var state: State
    private let environment: Environment
    private var warmupGeneration = UUID()

    init(state: State = State(), environment: Environment) {
        self.state = state
        self.environment = environment
    }

    var isDownloadingModel: Bool {
        state.isModelDownloadInProgress
    }

    var isDownloadingMeetingDiarizationModel: Bool {
        state.isMeetingDiarizationModelDownloadInProgress
    }

    @discardableResult
    func downloadModel() -> Task<Void, Never>? {
        guard environment.canStartDictationRuntime(),
            !state.isModelDownloadInProgress
        else { return nil }

        let downloadID = UUID()
        let model = environment.selectedModel()
        let downloader = environment.modelDownloader()
        let modelDownloadTimeout = environment.modelDownloadTimeout()

        send(.modelDownloadStarted(downloadID))
        send(.setModelDownloadProgress(nil))
        environment.setAppState(.downloadingModel(progress: nil))
        environment.setErrorMessage(nil)
        environment.showOverlay(.transcribing(stage: .loadingModel, progress: nil))

        let task = Task { [self] in
            do {
                let modelURL = try await AsyncOperationTimeout.run(
                    timeout: modelDownloadTimeout,
                    timeoutError: { ModelDownloadError.downloadTimedOut(model.id) },
                    operation: {
                        try await downloader.downloadModel(model) { [weak self, downloadID] event in
                            Task { @MainActor [weak self] in
                                guard self?.state.activeModelDownloadID == downloadID else { return }
                                self?.handleModelDownloadEvent(event)
                            }
                        }
                    }
                )

                guard state.activeModelDownloadID == downloadID else { return }
                clearActiveModelDownload()
                AppLogger.info("Downloaded model to \(modelURL.path)")
                environment.showOverlay(.done(message: "Model ready"))
                environment.hideOverlayAfter(1.0)

                environment.updateStateAfterModelChange()
                _ = scheduleModelWarmupIfInstalled()
            } catch is CancellationError {
                guard state.activeModelDownloadID == downloadID else { return }
                clearActiveModelDownload()
                environment.showOverlay(.done(message: "Download canceled"))
                environment.hideOverlayAfter(1.0)
                environment.updateStateAfterIncompleteModelDownload()
            } catch {
                guard state.activeModelDownloadID == downloadID else { return }
                clearActiveModelDownload()
                environment.setError(error)
            }
        }
        send(.modelDownloadTask(task))
        return task
    }

    @discardableResult
    func cancelModelDownload() -> Task<Void, Never>? {
        guard state.isModelDownloadInProgress else { return nil }

        let task = state.modelDownloadTask
        clearActiveModelDownload()
        task?.cancel()
        environment.showOverlay(.done(message: "Download canceled"))
        environment.hideOverlayAfter(1.0)
        environment.updateStateAfterIncompleteModelDownload()

        return Task {
            environment.updateStateAfterIncompleteModelDownload()
        }
    }

    @discardableResult
    func downloadMeetingDiarizationModel() -> Task<Void, Never>? {
        guard let meetingDiarizationModelManager = environment.meetingDiarizationModelManager(),
            !state.isMeetingDiarizationModelDownloadInProgress
        else {
            return nil
        }

        let downloadID = UUID()
        let modelDownloadTimeout = environment.modelDownloadTimeout()

        send(.meetingDiarizationModelDownloadStarted(downloadID))
        send(.setMeetingDiarizationModelDownloadProgress(nil))
        environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
        environment.setErrorMessage(nil)
        AppLogger.info("Starting meeting diarization model download to \(meetingDiarizationModelManager.modelDirectory.path)")

        let task = Task { [self] in
            do {
                try await AsyncOperationTimeout.run(
                    timeout: modelDownloadTimeout,
                    timeoutError: { ModelDownloadError.downloadTimedOut(Self.meetingDiarizationModelId) },
                    operation: {
                        try await meetingDiarizationModelManager.download { [weak self, downloadID] event in
                            Task { @MainActor [weak self] in
                                guard self?.state.activeMeetingDiarizationModelDownloadID == downloadID else { return }
                                self?.handleMeetingDiarizationModelDownloadEvent(event)
                            }
                        }
                    }
                )

                guard state.activeMeetingDiarizationModelDownloadID == downloadID else { return }
                clearActiveMeetingDiarizationModelDownload()
                environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
                AppLogger.info("Downloaded meeting diarization model to \(meetingDiarizationModelManager.modelDirectory.path)")
            } catch is CancellationError {
                guard state.activeMeetingDiarizationModelDownloadID == downloadID else { return }
                clearActiveMeetingDiarizationModelDownload()
                environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
                AppLogger.info("Meeting diarization model download canceled")
            } catch {
                guard state.activeMeetingDiarizationModelDownloadID == downloadID else { return }
                clearActiveMeetingDiarizationModelDownload()
                environment.setMeetingDiarizationModelRuntimeState(
                    .failed(modelId: Self.meetingDiarizationModelId, message: error.localizedDescription)
                )
                AppLogger.error("Meeting diarization model download failed: \(error.localizedDescription)")
                environment.setError(error)
            }
        }
        send(.meetingDiarizationModelDownloadTask(task))
        return task
    }

    @discardableResult
    func warmUpMeetingDiarizationModel() -> Task<Void, Never>? {
        guard let meetingDiarizationModelManager = environment.meetingDiarizationModelManager() else { return nil }
        guard environment.isMeetingDiarizationModelInstalled() else {
            environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
            AppLogger.info(
                "Meeting diarization model warmup skipped because model files are missing at \(environment.meetingDiarizationModelDirectory().path)"
            )
            return nil
        }

        if let existingTask = state.meetingDiarizationModelWarmupTask {
            existingTask.cancel()
        }
        send(.meetingDiarizationModelWarmupTask(nil))
        environment.setMeetingDiarizationModelRuntimeState(.warming(modelId: Self.meetingDiarizationModelId))

        let task = Task {
            do {
                AppLogger.info("Warming up meeting diarization model")
                try await meetingDiarizationModelManager.warmUp()
                guard !Task.isCancelled else { return }
                environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
                AppLogger.info("Meeting diarization model warmup completed")
            } catch is CancellationError {
                environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
                AppLogger.info("Meeting diarization model warmup canceled")
            } catch {
                environment.setMeetingDiarizationModelRuntimeState(
                    .failed(modelId: Self.meetingDiarizationModelId, message: error.localizedDescription)
                )
                AppLogger.error("Meeting diarization model warmup failed: \(error.localizedDescription)")
                environment.setError(error)
            }
            send(.meetingDiarizationModelWarmupFinished)
        }
        send(.meetingDiarizationModelWarmupTask(task))
        return task
    }

    @discardableResult
    func cancelMeetingDiarizationModelDownload() -> Task<Void, Never>? {
        guard state.isMeetingDiarizationModelDownloadInProgress else { return nil }

        let task = state.meetingDiarizationModelDownloadTask
        clearActiveMeetingDiarizationModelDownload()
        task?.cancel()
        environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
        return Task {}
    }

    @discardableResult
    func deleteDownloadedModelFiles() -> Task<Void, Never>? {
        guard environment.canDeleteModelFiles() else { return nil }

        let modelDirectory = environment.userModelDirectory()
        let modelID = environment.selectedModel().id
        return Task {
            guard await environment.modelWarmupClient()?.releaseResourcesForDeletion(modelID: modelID) ?? true,
                environment.canDeleteModelFiles(), environment.selectedModel().id == modelID
            else { return }
            do {
                if FileManager.default.fileExists(atPath: modelDirectory.path) {
                    try FileManager.default.removeItem(at: modelDirectory)
                }

                send(.setModelDownloadProgress(nil))
                environment.setErrorMessage(nil)
                environment.showOverlay(.done(message: "Model removed"))
                environment.hideOverlayAfter(1.0)
                environment.updateStateAfterModelChange()
            } catch {
                environment.setError(error)
            }
        }
    }

    func deleteMeetingDiarizationModelFiles() {
        guard environment.canDeleteMeetingDiarizationModelFiles(),
            let meetingDiarizationModelManager = environment.meetingDiarizationModelManager()
        else { return }

        Task {
            do {
                try await meetingDiarizationModelManager.deleteDownloadedModelFiles()
                send(.setMeetingDiarizationModelDownloadProgress(nil))
                environment.setMeetingDiarizationModelRuntimeState(.notLoaded)
            } catch {
                environment.setError(error)
            }
        }
    }

    @discardableResult
    func scheduleModelWarmupIfInstalled() -> Task<Void, Never>? {
        guard environment.canStartDictationRuntime() else { return nil }
        state.modelWarmupTask?.cancel()
        warmupGeneration = UUID()
        let generation = warmupGeneration
        send(.modelWarmupTask(nil))
        let selectedModelID = environment.selectedModel().id
        if let client = environment.modelWarmupClient() {
            Task { await client.releaseInactiveResources(selectedModelID: selectedModelID) }
        }
        guard environment.isModelInstalled(), let modelWarmupClient = environment.modelWarmupClient() else {
            environment.setModelRuntimeState(.notLoaded)
            return nil
        }

        if let existingTask = state.modelWarmupTask {
            existingTask.cancel()
        }

        let model = environment.selectedModel()
        let language = environment.transcriptionLanguage()
        let warmupJob = AppModelWarmupJob(
            client: modelWarmupClient,
            model: model,
            language: language,
            timeout: environment.modelWarmupTimeout()
        )

        environment.setModelRuntimeState(.warming(modelId: warmupJob.model.id))
        send(.modelWarmupTask(nil))

        let task = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            do {
                AppLogger.info("Warming up model \(warmupJob.model.id)")
                try await AsyncOperationTimeout.run(
                    timeout: warmupJob.timeout,
                    timeoutError: { TranscriptionError.modelWarmupTimedOut },
                    operation: {
                        try await warmupJob.client.warmUp(
                            model: warmupJob.model,
                            language: warmupJob.language
                        )
                    }
                )
                guard !Task.isCancelled, warmupGeneration == generation, environment.selectedModel().id == warmupJob.model.id else { return }
                AppLogger.info("Model warmup completed for \(warmupJob.model.id)")
                environment.setModelRuntimeState(.ready(modelId: warmupJob.model.id))
            } catch is CancellationError {
                AppLogger.info("Model warmup canceled for \(warmupJob.model.id)")
            } catch {
                guard !Task.isCancelled, warmupGeneration == generation, environment.selectedModel().id == warmupJob.model.id else { return }
                AppLogger.error("Model warmup failed for \(warmupJob.model.id): \(error.localizedDescription)")
                environment.setModelRuntimeState(
                    .failed(modelId: warmupJob.model.id, message: error.localizedDescription)
                )
                environment.setError(error)
            }
            if warmupGeneration == generation { send(.modelWarmupFinished) }
        }
        send(.modelWarmupTask(task))
        return task
    }

    func cancelModelWarmup() {
        guard state.modelWarmupTask != nil else { return }

        AppLogger.info("Canceling model warmup because recording started")
        state.modelWarmupTask?.cancel()
        warmupGeneration = UUID()
        send(.modelWarmupFinished)
    }

    func scheduleLifecycleModelWarmupIfPossible() {
        guard state.modelWarmupTask == nil,
            !state.isModelDownloadInProgress,
            environment.canScheduleLifecycleModelWarmup()
        else {
            return
        }

        if let lastWarmupDate = state.lastLifecycleModelWarmupDate,
            Date().timeIntervalSince(lastWarmupDate) < environment.lifecycleWarmupCooldown()
        {
            return
        }

        let now = Date()
        guard scheduleModelWarmupIfInstalled() != nil else { return }
        send(.setLifecycleWarmupDate(now))
    }

    func cancelMeetingDiarizationModelWarmup() {
        state.meetingDiarizationModelWarmupTask?.cancel()
        send(.meetingDiarizationModelWarmupFinished)
    }

    private func clearActiveModelDownload() {
        send(.modelDownloadFinished)
        send(.setModelDownloadProgress(nil))
    }

    private func clearActiveMeetingDiarizationModelDownload() {
        send(.meetingDiarizationModelDownloadFinished)
        send(.setMeetingDiarizationModelDownloadProgress(nil))
    }

    private func handleModelDownloadEvent(_ event: ModelDownloadEvent) {
        switch event {
        case let .downloadingArtifact(_, progress):
            send(.setModelDownloadProgress(progress))
            environment.setAppState(.downloadingModel(progress: progress))
        case let .extractingArtifact(name):
            send(.setModelDownloadProgress(nil))
            environment.setAppState(.preparingModel("Extracting \(name)"))
        case .validating:
            send(.setModelDownloadProgress(nil))
            environment.setAppState(.preparingModel("Validating model"))
        case .completed:
            send(.setModelDownloadProgress(nil))
            environment.setAppState(.preparingModel("Model ready"))
        }
    }

    private func handleMeetingDiarizationModelDownloadEvent(_ event: ModelDownloadEvent) {
        switch event {
        case let .downloadingArtifact(name, progress):
            send(.setMeetingDiarizationModelDownloadProgress(progress))
            if let progress {
                AppLogger.debug("Meeting diarization download: \(name) \(Int((progress * 100).rounded()))%")
            } else {
                AppLogger.info("Meeting diarization download: \(name)")
            }
        case let .extractingArtifact(name):
            send(.setMeetingDiarizationModelDownloadProgress(nil))
            AppLogger.info("Meeting diarization download extracting: \(name)")
        case .validating:
            send(.setMeetingDiarizationModelDownloadProgress(nil))
            AppLogger.info("Meeting diarization download validating")
        case .completed:
            send(.setMeetingDiarizationModelDownloadProgress(nil))
            AppLogger.info("Meeting diarization download completed")
        }
    }

    private func send(_ action: Action) {
        switch action {
        case let .modelDownloadStarted(downloadID):
            state.activeModelDownloadID = downloadID
        case let .modelDownloadTask(task):
            state.modelDownloadTask = task
        case .modelDownloadFinished:
            state.activeModelDownloadID = nil
            state.modelDownloadTask = nil
        case let .meetingDiarizationModelDownloadStarted(downloadID):
            state.activeMeetingDiarizationModelDownloadID = downloadID
        case let .meetingDiarizationModelDownloadTask(task):
            state.meetingDiarizationModelDownloadTask = task
        case .meetingDiarizationModelDownloadFinished:
            state.activeMeetingDiarizationModelDownloadID = nil
            state.meetingDiarizationModelDownloadTask = nil
        case let .modelWarmupTask(task):
            state.modelWarmupTask = task
        case .modelWarmupFinished:
            state.modelWarmupTask = nil
        case let .meetingDiarizationModelWarmupTask(task):
            state.meetingDiarizationModelWarmupTask = task
        case .meetingDiarizationModelWarmupFinished:
            state.meetingDiarizationModelWarmupTask = nil
        case let .setModelDownloadProgress(progress):
            environment.setModelDownloadProgress(progress)
        case let .setMeetingDiarizationModelDownloadProgress(progress):
            environment.setMeetingDiarizationModelDownloadProgress(progress)
        case let .setLifecycleWarmupDate(date):
            state.lastLifecycleModelWarmupDate = date
        }
    }

    private struct AppModelWarmupJob: @unchecked Sendable {
        let client: ModelWarmupClient
        let model: ModelManifestModel
        let language: String
        let timeout: Duration
    }
}
