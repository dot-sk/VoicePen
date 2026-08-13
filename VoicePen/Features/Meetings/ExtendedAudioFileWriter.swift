@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

nonisolated protocol MeetingAudioBufferWriting: AnyObject {
    func write(_ buffer: AVAudioPCMBuffer) throws
    func close() throws
}

nonisolated private enum ExtendedAudioFileWriterError: Error {
    case unsupportedFileType
    case invalidState
    case status(OSStatus)
}

nonisolated final class ExtendedAudioFileWriter: MeetingAudioBufferWriting, @unchecked Sendable {
    private let clientFormat: AVAudioFormat
    private var audioFile: ExtAudioFileRef?
    private var firstFailureStatus: OSStatus?

    init(
        outputURL: URL,
        clientFormat: AVAudioFormat,
        fileFormat: AVAudioFormat
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
            throw ExtendedAudioFileWriterError.status(createStatus)
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
                throw ExtendedAudioFileWriterError.status(clientFormatStatus)
            }

            let warmUpStatus = ExtAudioFileWriteAsync(audioFile, 0, nil)
            guard warmUpStatus == noErr else {
                throw ExtendedAudioFileWriterError.status(warmUpStatus)
            }
        } catch {
            ExtAudioFileDispose(audioFile)
            throw error
        }

        self.clientFormat = clientFormat
        self.audioFile = audioFile
    }

    deinit {
        if let audioFile {
            ExtAudioFileDispose(audioFile)
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) throws {
        if let firstFailureStatus {
            throw ExtendedAudioFileWriterError.status(firstFailureStatus)
        }
        guard let audioFile, buffer.format.matches(clientFormat) else {
            throw ExtendedAudioFileWriterError.invalidState
        }

        let status = ExtAudioFileWriteAsync(
            audioFile,
            UInt32(buffer.frameLength),
            buffer.audioBufferList
        )
        guard status == noErr else {
            firstFailureStatus = status
            throw ExtendedAudioFileWriterError.status(status)
        }
    }

    func close() throws {
        guard let audioFile else {
            if let firstFailureStatus {
                throw ExtendedAudioFileWriterError.status(firstFailureStatus)
            }
            return
        }

        self.audioFile = nil
        let closeStatus = ExtAudioFileDispose(audioFile)
        if firstFailureStatus == nil, closeStatus != noErr {
            firstFailureStatus = closeStatus
        }
        if let firstFailureStatus {
            throw ExtendedAudioFileWriterError.status(firstFailureStatus)
        }
    }

    private static func fileType(for outputURL: URL) throws -> AudioFileTypeID {
        switch outputURL.pathExtension.lowercased() {
        case "wav", "wave":
            return kAudioFileWAVEType
        case "caf":
            return kAudioFileCAFType
        default:
            throw ExtendedAudioFileWriterError.unsupportedFileType
        }
    }
}
