import AppKit
@preconcurrency import UserNotifications

@MainActor
protocol MeetingRecordingReminderPresenter {
    func setReminderClickAction(_ action: @escaping @MainActor () -> Void)
    func showMeetingRecordingStillRunningReminder()
}

@MainActor
final class NoOpMeetingRecordingReminderPresenter: MeetingRecordingReminderPresenter {
    func setReminderClickAction(_ action: @escaping @MainActor () -> Void) {}
    func showMeetingRecordingStillRunningReminder() {}
}

@MainActor
final class UserNotificationMeetingRecordingReminderPresenter: NSObject, MeetingRecordingReminderPresenter {
    nonisolated static let notificationIdentifier = "voicepen.meetingRecording.limitReminder"

    static let shared = UserNotificationMeetingRecordingReminderPresenter()

    private let center: UNUserNotificationCenter
    private var reminderClickAction: (@MainActor () -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func setReminderClickAction(_ action: @escaping @MainActor () -> Void) {
        reminderClickAction = action
    }

    func showMeetingRecordingStillRunningReminder() {
        Task { @MainActor [weak self] in
            await self?.deliverReminderIfAllowed()
        }
    }

    private func deliverReminderIfAllowed() async {
        let settings = await center.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = (try? await center.requestAuthorization(options: [.alert])) ?? false
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Meeting recording is still running"
        content.body = "VoicePen will stop the recording automatically in about 5 minutes."
        content.threadIdentifier = "voicepen.meetingRecording"

        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            AppLogger.error("Meeting recording reminder notification failed: \(error.localizedDescription)")
        }
    }
}

extension UserNotificationMeetingRecordingReminderPresenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.identifier == Self.notificationIdentifier else {
            completionHandler([])
            return
        }

        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.notification.request.identifier == Self.notificationIdentifier else {
            completionHandler()
            return
        }

        Task { @MainActor [weak self] in
            self?.reminderClickAction?()
        }
        completionHandler()
    }
}
