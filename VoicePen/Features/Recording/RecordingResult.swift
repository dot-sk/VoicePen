import Foundation

struct RecordingResult: Equatable {
    let url: URL
    let startedAt: Date
    let endedAt: Date

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}
