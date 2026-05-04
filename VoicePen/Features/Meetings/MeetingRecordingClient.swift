import Foundation

protocol MeetingRecordingClient: AnyObject {
    var sourceStatus: MeetingSourceStatus { get }

    func start() async throws
    func pause() async throws
    func resume() async throws
    func stop() async throws -> MeetingRecordingResult
    func cancel() async throws
}
