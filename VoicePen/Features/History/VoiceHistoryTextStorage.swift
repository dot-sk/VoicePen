import Compression
import Foundation

struct StoredTextComponent {
    var plainText: String
    var compressedText: Data?
}

struct StoredTextPayload {
    var format: String
    var components: [StoredTextComponent]
    var missingCompressedPayloadError: () -> Error

    var isEvicted: Bool {
        format == VoiceHistoryTextStorageFormat.evicted
    }

    var byteCount: Int {
        switch format {
        case VoiceHistoryTextStorageFormat.evicted:
            return 0
        case VoiceHistoryTextStorageFormat.zlib:
            return components.reduce(0) { $0 + ($1.compressedText?.count ?? 0) }
        default:
            return components.reduce(0) { $0 + $1.plainText.utf8.count }
        }
    }

    func resolvedTexts() throws -> [String] {
        if isEvicted {
            return components.map { _ in "" }
        }

        guard format == VoiceHistoryTextStorageFormat.zlib else {
            return components.map(\.plainText)
        }

        return try components.map { component in
            guard let compressedText = component.compressedText else {
                throw missingCompressedPayloadError()
            }
            return try VoiceHistoryTextCompressor.decompress(compressedText)
        }
    }

    func preferredText() throws -> String {
        let texts = try resolvedTexts()
        return texts.reversed().first { !$0.isEmpty } ?? texts.first ?? ""
    }
}

struct StoredTextRow {
    var id: String
    var rawText: String
    var finalText: String
    var textStorageFormat: String
    var compressedRawText: Data?
    var compressedFinalText: Data?
    var recognizedWordCount: Int?

    var textByteCount: Int {
        payload.byteCount
    }

    func resolvedWordCount() throws -> Int {
        if let recognizedWordCount {
            return recognizedWordCount
        }

        return VoiceHistoryEntry.wordCount(in: try payload.preferredText())
    }

    var payload: StoredTextPayload {
        StoredTextPayload(
            format: textStorageFormat,
            components: [
                StoredTextComponent(plainText: rawText, compressedText: compressedRawText),
                StoredTextComponent(plainText: finalText, compressedText: compressedFinalText)
            ],
            missingCompressedPayloadError: {
                VoiceHistoryStoreError.invalidRow("Compressed history text is missing payload")
            }
        )
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
