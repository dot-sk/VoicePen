import AppKit
import Foundation

@MainActor
final class MeetingRecordingStore {
    struct State {
        var elapsedTime: TimeInterval = 0
        var sourceStatus: MeetingSourceStatus = .idle
        var startedAt: Date?
        var activeProcessingID: UUID?
        var statusTask: Task<Void, Never>?
        var processingTask: Task<Void, Never>?
        var processingTimeoutTask: Task<Void, Never>?

        var isProcessing: Bool {
            processingTask != nil
        }
    }

    enum Action {
        case startRequested(Date)
        case startSucceeded
        case startFailed(Error)
        case stopRequested(UUID)
        case stopSucceeded(UUID, MeetingHistoryEntry)
        case stopFailed(UUID, Error)
        case cancelSucceeded
        case cancelFailed(Error)
        case retryRequested(UUID)
        case retrySucceeded(UUID, MeetingHistoryEntry)
        case retryFailed(UUID, Error)
        case statusTick(elapsedTime: TimeInterval?, sourceStatus: MeetingSourceStatus)
        case processingTimedOut(UUID)
        case processingFinished(UUID)
    }

    struct Environment {
        let meetingPipeline: MeetingPipeline?
        let meetingHistoryStore: MeetingHistoryStore?
        let permissions: PermissionsClient
        let settingsStore: AppSettingsStore
        let userPrompts: UserPromptPresenter
        let captureStartTimeout: Duration
        let processingTimeout: Duration
        let runningApplicationBundleIdentifiersProvider: () -> Set<String>
        let getAppState: () -> AppState
        let setAppState: (AppState) -> Void
        let setErrorMessage: (String?) -> Void
        let setElapsedTime: (TimeInterval) -> Void
        let setSourceStatus: (MeetingSourceStatus) -> Void
        let setProcessingProgress: (MeetingProcessingProgress?) -> Void
        let presentError: (Error) -> Void
        let refreshBaseState: () -> Void
    }

    private static let microphonePermissionRequiredMessage = "Microphone permission is required to record dictation audio locally."
    private static let systemAudioPermissionRequiredMessage = "System Audio permission is required to capture meeting audio locally."

    private(set) var state: State
    private let environment: Environment

    init(state: State = State(), environment: Environment) {
        self.state = state
        self.environment = environment
    }

    @discardableResult
    func start() -> Task<Void, Never>? {
        guard let meetingPipeline = environment.meetingPipeline else { return nil }
        guard environment.getAppState().canStartMeetingRecording else { return nil }
        guard acknowledgeMeetingRecordingConsentIfNeeded() else { return nil }

        guard environment.permissions.microphonePermissionStatus == .authorized else {
            environment.setAppState(.missingMicrophonePermission)
            environment.setErrorMessage(Self.microphonePermissionRequiredMessage)
            return nil
        }

        let preflightWarning = preflightSystemAudioSource()
        let timeout = environment.captureStartTimeout
        return Task { [weak self, meetingPipeline] in
            guard let self else { return }
            do {
                send(.startRequested(Date()))
                environment.setErrorMessage(preflightWarning)
                try await AsyncOperationTimeout.run(
                    timeout: timeout,
                    timeoutError: { MeetingRecordingError.captureTimedOut },
                    operation: {
                        try await meetingPipeline.start()
                    }
                )
                send(.startSucceeded)
            } catch {
                send(.startFailed(error))
            }
        }
    }

    private func preflightSystemAudioSource() -> String? {
        let currentSettings = MeetingSystemAudioSourceSettings(
            mode: environment.settingsStore.meetingSystemAudioSourceMode,
            selectedApps: environment.settingsStore.meetingAudioAppSelections
        )
        let result = MeetingSystemAudioSourcePreflight.resolve(
            settings: currentSettings,
            runningBundleIdentifiers: environment.runningApplicationBundleIdentifiersProvider()
        )
        guard result.settings.mode != currentSettings.mode else {
            return result.warning
        }

        do {
            try environment.settingsStore.updateMeetingSystemAudioSourceMode(result.settings.mode)
        } catch {
            environment.presentError(error)
            return error.localizedDescription
        }
        return result.warning
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        guard environment.getAppState() == .meetingRecording,
            let meetingPipeline = environment.meetingPipeline,
            !state.isProcessing
        else { return nil }

        let processingID = UUID()
        send(.stopRequested(processingID))

        let task = Task { [weak self, meetingPipeline] in
            guard let self else { return }
            defer {
                send(.processingFinished(processingID))
            }

            do {
                let entry = try await meetingPipeline.stopAndProcess()
                send(.stopSucceeded(processingID, entry))
            } catch {
                send(.stopFailed(processingID, error))
            }
        }
        state.processingTask = task
        return task
    }

    @discardableResult
    func cancel() -> Task<Void, Never>? {
        guard environment.getAppState() == .meetingRecording,
            let meetingPipeline = environment.meetingPipeline
        else { return nil }

        return Task { [weak self, meetingPipeline] in
            guard let self else { return }
            do {
                try await meetingPipeline.cancel()
                send(.cancelSucceeded)
            } catch {
                send(.cancelFailed(error))
            }
        }
    }

    @discardableResult
    func retry(_ entry: MeetingHistoryEntry) -> Task<Void, Never>? {
        let appState = environment.getAppState()
        guard appState != .meetingRecording,
            appState != .meetingProcessing,
            let meetingPipeline = environment.meetingPipeline,
            !state.isProcessing
        else { return nil }

        let processingID = UUID()
        send(.retryRequested(processingID))

        let task = Task { [weak self, meetingPipeline] in
            guard let self else { return }
            defer {
                send(.processingFinished(processingID))
            }

            do {
                let retriedEntry = try await meetingPipeline.retryProcessing(entry)
                send(.retrySucceeded(processingID, retriedEntry))
            } catch {
                send(.retryFailed(processingID, error))
            }
        }
        state.processingTask = task
        return task
    }

    func deleteEntry(id: MeetingHistoryEntry.ID) {
        do {
            try environment.meetingHistoryStore?.delete(id: id)
        } catch {
            environment.presentError(error)
        }
    }

    func send(_ action: Action) {
        switch action {
        case let .startRequested(startedAt):
            environment.setAppState(.meetingRecording)
            environment.setErrorMessage(nil)
            state.startedAt = startedAt
            updateElapsedTime(0)

        case .startSucceeded:
            startStatusUpdates()

        case let .startFailed(error):
            handleStartError(error)

        case let .stopRequested(processingID):
            state.activeProcessingID = processingID
            environment.setAppState(.meetingProcessing)
            environment.setProcessingProgress(nil)
            stopStatusUpdates()
            startProcessingTimeoutMonitor(id: processingID)

        case let .stopSucceeded(processingID, entry):
            guard state.activeProcessingID == processingID else { return }
            updateElapsedTime(entry.duration)
            environment.refreshBaseState()
            environment.setErrorMessage(nil)

        case let .stopFailed(processingID, error):
            guard state.activeProcessingID == processingID else { return }
            stopStatusUpdates()
            environment.presentError(error)

        case .cancelSucceeded:
            stopStatusUpdates()
            updateElapsedTime(0)
            updateSourceStatus(.idle)
            environment.setProcessingProgress(nil)
            environment.refreshBaseState()
            environment.setErrorMessage(nil)

        case let .cancelFailed(error):
            environment.presentError(error)

        case let .retryRequested(processingID):
            state.activeProcessingID = processingID
            environment.setAppState(.meetingProcessing)
            environment.setProcessingProgress(nil)
            startProcessingTimeoutMonitor(id: processingID)

        case let .retrySucceeded(processingID, entry):
            guard state.activeProcessingID == processingID else { return }
            updateElapsedTime(entry.duration)
            environment.refreshBaseState()
            environment.setErrorMessage(nil)

        case let .retryFailed(processingID, error):
            guard state.activeProcessingID == processingID else { return }
            environment.presentError(error)

        case let .statusTick(elapsedTime, sourceStatus):
            if let elapsedTime {
                updateElapsedTime(elapsedTime)
            }
            updateSourceStatus(sourceStatus)

        case let .processingTimedOut(processingID):
            guard state.activeProcessingID == processingID,
                environment.getAppState() == .meetingProcessing
            else { return }

            AppLogger.error("Meeting processing timed out")
            state.processingTask?.cancel()
            finishProcessing(id: processingID)
            environment.presentError(TranscriptionError.transcriptionTimedOut)

        case let .processingFinished(processingID):
            finishProcessing(id: processingID)
        }
    }

    private func acknowledgeMeetingRecordingConsentIfNeeded() -> Bool {
        guard !environment.settingsStore.hasAcknowledgedMeetingRecordingConsent else { return true }

        let response = environment.userPrompts.showAlert(
            messageText: "Start meeting recording?",
            informativeText: """
                VoicePen will record microphone and system audio only after you start Meeting Recording. Transcription runs locally, raw audio is temporary, and meeting output is saved as transcript history.
                """,
            style: .informational,
            buttons: ["Start Recording", "Cancel"],
            activateBeforeShowing: true
        )

        guard response == .alertFirstButtonReturn else { return false }
        do {
            try environment.settingsStore.updateMeetingRecordingConsentAcknowledged(true)
            return true
        } catch {
            environment.presentError(error)
            return false
        }
    }

    private func handleStartError(_ error: Error) {
        if let meetingError = error as? MeetingRecordingError,
            meetingError == .systemAudioPermissionDenied
        {
            environment.setAppState(.missingSystemAudioPermission)
            environment.setErrorMessage(Self.systemAudioPermissionRequiredMessage)
            return
        }

        environment.presentError(error)
    }

    private func startStatusUpdates() {
        state.statusTask?.cancel()
        state.statusTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let appState = environment.getAppState()
                let elapsedTime =
                    appState == .meetingRecording
                    ? Date().timeIntervalSince(state.startedAt ?? Date())
                    : nil
                let sourceStatus = environment.meetingPipeline?.sourceStatus ?? .idle
                send(.statusTick(elapsedTime: elapsedTime, sourceStatus: sourceStatus))
                if appState == .meetingRecording, sourceStatus.hasFailedSource {
                    _ = stop()
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopStatusUpdates() {
        state.statusTask?.cancel()
        state.statusTask = nil
        state.startedAt = nil
        updateSourceStatus(.idle)
    }

    private func startProcessingTimeoutMonitor(id: UUID) {
        state.processingTimeoutTask?.cancel()
        let timeout = environment.processingTimeout
        state.processingTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }

            self?.send(.processingTimedOut(id))
        }
    }

    private func finishProcessing(id: UUID) {
        guard state.activeProcessingID == id else { return }

        state.processingTimeoutTask?.cancel()
        state.processingTimeoutTask = nil
        state.processingTask = nil
        state.activeProcessingID = nil
        environment.setProcessingProgress(nil)
    }

    private func updateElapsedTime(_ elapsedTime: TimeInterval) {
        state.elapsedTime = elapsedTime
        environment.setElapsedTime(elapsedTime)
    }

    private func updateSourceStatus(_ sourceStatus: MeetingSourceStatus) {
        state.sourceStatus = sourceStatus
        environment.setSourceStatus(sourceStatus)
    }
}
