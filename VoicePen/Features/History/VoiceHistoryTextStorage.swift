import Compression
import Foundation

struct StoredTextRow {
    var id: String
    var rawText: String
    var finalText: String
    var textStorageFormat: String
    var compressedRawText: Data?
    var compressedFinalText: Data?
    var recognizedWordCount: Int?

    var textByteCount: Int {
        if textStorageFormat == VoiceHistoryTextStorageFormat.zlib {
            return (compressedRawText?.count ?? 0) + (compressedFinalText?.count ?? 0)
        }

        return rawText.utf8.count + finalText.utf8.count
    }

    func resolvedWordCount() throws -> Int {
        if let recognizedWordCount {
            return recognizedWordCount
        }

        return VoiceHistoryEntry.wordCount(in: try resolvedBestText())
    }

    private func resolvedBestText() throws -> String {
        if textStorageFormat == VoiceHistoryTextStorageFormat.zlib {
            guard let compressedRawText, let compressedFinalText else {
                throw VoiceHistoryStoreError.invalidRow("Compressed history text is missing payload")
            }

            let rawText = try VoiceHistoryTextCompressor.decompress(compressedRawText)
            let finalText = try VoiceHistoryTextCompressor.decompress(compressedFinalText)
            return finalText.isEmpty ? rawText : finalText
        }

        return finalText.isEmpty ? rawText : finalText
    }
}

struct StoredHistoryText {
    var rawText: String
    var finalText: String
    var isEvicted: Bool = false
}

enum VoiceHistoryTextStorageFormat {
    static let plain = "plain"
    static let zlib = "zlib"
    static let evicted = "evicted"
}

enum VoiceHistoryTextCompressor {
    private static let algorithm = COMPRESSION_ZLIB
    private static let maximumDecompressedBytes = 128 * 1024 * 1024

    static func compress(_ text: String) throws -> Data {
        let sourceData = Data(text.utf8)
        guard !sourceData.isEmpty else { return Data() }

        return try sourceData.withUnsafeBytes { sourceBuffer in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw VoiceHistoryStoreError.compressionFailed
            }

            var destinationSize = max(64, sourceData.count + 1024)
            let maximumDestinationSize = max(1024, sourceData.count * 4 + 4096)

            while destinationSize <= maximumDestinationSize {
                var destination = [UInt8](repeating: 0, count: destinationSize)
                let compressedSize = destination.withUnsafeMutableBufferPointer { destinationBuffer in
                    compression_encode_buffer(
                        destinationBuffer.baseAddress!,
                        destinationSize,
                        sourcePointer,
                        sourceData.count,
                        nil,
                        algorithm
                    )
                }

                if compressedSize > 0 {
                    return Data(destination.prefix(compressedSize))
                }

                destinationSize *= 2
            }

            throw VoiceHistoryStoreError.compressionFailed
        }
    }

    static func decompress(_ data: Data) throws -> String {
        guard !data.isEmpty else { return "" }

        let decompressedData = try data.withUnsafeBytes { sourceBuffer in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw VoiceHistoryStoreError.decompressionFailed
            }

            var destinationSize = max(256, data.count * 4)

            while destinationSize <= maximumDecompressedBytes {
                var destination = [UInt8](repeating: 0, count: destinationSize)
                let decompressedSize = destination.withUnsafeMutableBufferPointer { destinationBuffer in
                    compression_decode_buffer(
                        destinationBuffer.baseAddress!,
                        destinationSize,
                        sourcePointer,
                        data.count,
                        nil,
                        algorithm
                    )
                }

                if decompressedSize > 0 {
                    return Data(destination.prefix(decompressedSize))
                }

                destinationSize *= 2
            }

            throw VoiceHistoryStoreError.decompressionFailed
        }

        guard let text = String(data: decompressedData, encoding: .utf8) else {
            throw VoiceHistoryStoreError.invalidCompressedText
        }

        return text
    }
}
