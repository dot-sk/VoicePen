import Foundation

nonisolated struct RecordingResult: Equatable, Sendable {
    let url: URL
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}
