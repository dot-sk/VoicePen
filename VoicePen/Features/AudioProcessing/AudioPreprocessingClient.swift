import Foundation

protocol AudioPreprocessingClient: AnyObject {
    func preprocess(audioURL: URL, mode: SpeechPreprocessingMode) async throws -> URL
}

final class PassthroughAudioPreprocessingClient: AudioPreprocessingClient {
    func preprocess(audioURL: URL, mode _: SpeechPreprocessingMode) async throws -> URL {
        audioURL
    }
}
