import Foundation

protocol MeetingRecordingClient: AnyObject {
    var sourceStatus: MeetingSourceStatus { get }

    func start() async throws
    func stop() async throws -> MeetingRecordingResult
    func cancel() async throws
}
