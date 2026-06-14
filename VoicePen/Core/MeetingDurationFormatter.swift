import Foundation

enum MeetingDurationFormatter {
    static func historyText(_ duration: TimeInterval) -> String {
        let seconds = max(0, duration)
        if seconds < 60 {
            return "\(displayedSeconds(seconds)) sec"
        }
        return String(format: "%.1f min", seconds / 60)
    }

    private static func displayedSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds > 0 else {
            return 0
        }
        return max(1, Int(seconds.rounded()))
    }
}
