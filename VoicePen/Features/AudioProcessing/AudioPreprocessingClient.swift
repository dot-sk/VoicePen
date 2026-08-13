import Foundation

protocol AudioPreprocessingClient: AnyObject {
    func preprocess(audioURL: URL) async throws -> URL
}

final class PassthroughAudioPreprocessingClient: AudioPreprocessingClient {
    func preprocess(audioURL: URL) async throws -> URL {
        audioURL
    }
}
