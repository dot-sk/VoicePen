@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

nonisolated protocol MeetingAudioBufferWriting: AnyObject {
    func write(_ buffer: AVAudioPCMBuffer) throws
    func close() throws
}

nonisolated enum ExtendedAudioFileWriteMode {
    case synchronous
    case asynchronous
}

nonisolated private enum ExtendedAudioFileWriterError: LocalizedError {
    case unsupportedFileType(String)
    case invalidState
    case status(operation: String, code: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFileType(extensionName):
            return "Extended audio writer does not support .\(extensionName) files."
        case .invalidState:
            return "Extended audio writer is closed or received an incompatible buffer format."
        case let .status(operation, code):
            return "Extended audio writer failed during \(operation): OSStatus(\(code))."
        }
    }
}

/// Audio Toolbox owns the ring buffer and disk-writing thread. After warm-up,
/// writes are suitable for a realtime Core Audio callback.
nonisolated final class ExtendedAudioFileWriter: MeetingAudioBufferWriting, @unchecked Sendable {
    private let clientFormat: AVAudioFormat
    private let writeMode: ExtendedAudioFileWriteMode
    private var audioFile: ExtAudioFileRef?
    private var firstFailureStatus: OSStatus?

    init(
        outputURL: URL,
        clientFormat: AVAudioFormat,
        fileFormat: AVAudioFormat,
        writeMode: ExtendedAudioFileWriteMode = .asynchronous
    ) throws {
        var fileDescription = fileFormat.streamDescription.pointee
        var audioFile: ExtAudioFileRef?
        let createStatus = ExtAudioFileCreateWithURL(
            outputURL as CFURL,
            try Self.fileType(for: outputURL),
            &fileDescription,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &audioFile
        )
        guard createStatus == noErr, let audioFile else {
            throw ExtendedAudioFileWriterError.status(
                operation: "file creation",
                code: createStatus
            )
        }

        do {
            var clientDescription = clientFormat.streamDescription.pointee
            let clientFormatStatus = ExtAudioFileSetProperty(
                audioFile,
                kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                &clientDescription
            )
            guard clientFormatStatus == noErr else {
                throw ExtendedAudioFileWriterError.status(
                    operation: "client format configuration",
                    code: clientFormatStatus
                )
            }

            if writeMode == .asynchronous {
                let warmUpStatus = ExtAudioFileWriteAsync(audioFile, 0, nil)
                guard warmUpStatus == noErr else {
                    throw ExtendedAudioFileWriterError.status(
                        operation: "asynchronous writer warm-up",
                        code: warmUpStatus
                    )
                }
            }
        } catch {
            ExtAudioFileDispose(audioFile)
            throw error
        }

        self.clientFormat = clientFormat
        self.writeMode = writeMode
        self.audioFile = audioFile
    }

    deinit {
        if let audioFile {
            ExtAudioFileDispose(audioFile)
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        if let firstFailureStatus {
            throw ExtendedAudioFileWriterError.status(
                operation: "a previous write",
                code: firstFailureStatus
            )
        }
        guard let audioFile, buffer.format.matches(clientFormat) else {
            throw ExtendedAudioFileWriterError.invalidState
        }

        let status: OSStatus
        switch writeMode {
        case .synchronous:
            status = ExtAudioFileWrite(
                audioFile,
                UInt32(buffer.frameLength),
                buffer.audioBufferList
            )
        case .asynchronous:
            status = ExtAudioFileWriteAsync(
                audioFile,
                UInt32(buffer.frameLength),
                buffer.audioBufferList
            )
        }
        guard status == noErr else {
            firstFailureStatus = status
            throw ExtendedAudioFileWriterError.status(
                operation: writeMode == .synchronous ? "synchronous write" : "asynchronous write",
                code: status
            )
        }
    }

    func close() throws {
        guard let audioFile else {
            if let firstFailureStatus {
                throw ExtendedAudioFileWriterError.status(
                    operation: "a previous write",
                    code: firstFailureStatus
                )
            }
            return
        }

        self.audioFile = nil
        let closeStatus = ExtAudioFileDispose(audioFile)
        if firstFailureStatus == nil, closeStatus != noErr {
            firstFailureStatus = closeStatus
        }
        if let firstFailureStatus {
            throw ExtendedAudioFileWriterError.status(
                operation: "file finalization",
                code: firstFailureStatus
            )
        }
    }

    private static func fileType(for outputURL: URL) throws -> AudioFileTypeID {
        switch outputURL.pathExtension.lowercased() {
        case "wav", "wave":
            return kAudioFileWAVEType
        case "caf":
            return kAudioFileCAFType
        default:
            throw ExtendedAudioFileWriterError.unsupportedFileType(outputURL.pathExtension)
        }
    }
}
