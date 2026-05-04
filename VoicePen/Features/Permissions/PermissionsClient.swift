import Foundation

enum MicrophonePermissionStatus: Equatable {
    case authorized
    case notDetermined
    case denied
}

protocol PermissionsClient: AnyObject {
    var microphonePermissionStatus: MicrophonePermissionStatus { get }
    var hasAccessibilityPermission: Bool { get }
    var hasSystemAudioRecordingPermission: Bool { get }

    func requestAccessibilityPermission()
    func requestMicrophonePermission() async -> Bool
    func requestSystemAudioRecordingPermission()
}
