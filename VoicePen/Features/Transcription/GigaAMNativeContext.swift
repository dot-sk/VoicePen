import Foundation

#if canImport(VoicePenGigaAM)
    import VoicePenGigaAM
#endif

nonisolated enum GigaAMNativeContext {
    static let packageID = "voicepen-gigaam-600m-0.1.0-candidate.2"

    static func checkStatus(_ status: Int32) throws {
        switch status {
        case 0: return
        case 4, 5, 6: throw GigaAMError.incompatibleModel
        case 7: throw GigaAMError.resourceExhausted
        case 8: throw GigaAMError.metalUnavailable
        case 9, 21: throw GigaAMError.invalidAudio
        case 13: throw CancellationError()
        case 17: throw GigaAMError.inputTooLong
        case 18, 19: throw GigaAMError.incompleteOutput
        default: throw GigaAMError.nativeStatus(status)
        }
    }

    static func load(path: String, model: ModelManifestModel) throws -> GigaAMLoadedContext {
        guard let sha256 = model.sha256, let byteSize = model.byteSize, model.runtimePackageID == packageID,
            model.capabilities?.timestamps == false
        else {
            throw GigaAMError.incompatibleModel
        }
        try VerifiedModelAssetDownloader().verify(
            ModelAssetRemoteFile(downloadURL: model.downloadURL ?? "", byteSize: byteSize, sha256: sha256),
            at: URL(fileURLWithPath: path)
        )
        #if canImport(VoicePenGigaAM)
            let native = try GigaAMNativeModel(path: path, expected: model)
            return GigaAMLoadedContext { samples, token, includeTimestamps in
                try native.transcribe(samples: samples, token: token, includeTimestamps: includeTimestamps)
            }
        #else
            throw GigaAMError.packageUnavailable
        #endif
    }
}

#if canImport(VoicePenGigaAM)
    nonisolated private final class GigaAMNativeModel: @unchecked Sendable {
        private let model: OpaquePointer
        private let packageID: String

        init(path: String, expected: ModelManifestModel) throws {
            var params = transcribe_model_load_params()
            transcribe_model_load_params_init(&params)
            params.backend = TRANSCRIBE_BACKEND_METAL
            var loaded: OpaquePointer?
            try Self.check(transcribe_model_load_file(path, &params, &loaded))
            guard let loaded else { throw GigaAMError.incompatibleModel }
            do {
                var capabilities = transcribe_capabilities()
                transcribe_capabilities_init(&capabilities)
                try Self.check(transcribe_model_get_capabilities(loaded, &capabilities))
                let languages = (0..<Int(capabilities.n_languages)).compactMap { index -> String? in
                    guard let code = capabilities.languages?[index] else { return nil }
                    return String(cString: code)
                }
                guard String(cString: transcribe_model_arch_string(loaded)) == "gigaam",
                    String(cString: transcribe_version()) == "0.4.0",
                    String(cString: transcribe_version_commit()) == "1dc22fac+voicepen-gigaam-600m-candidate.2",
                    capabilities.native_sample_rate == 16_000,
                    capabilities.max_timestamp_kind == TRANSCRIBE_TIMESTAMPS_NONE,
                    !capabilities.supports_translate, !capabilities.supports_streaming,
                    Set(languages) == Set(expected.supportedLanguageCodes)
                else { throw GigaAMError.incompatibleModel }
                guard String(cString: transcribe_model_backend(loaded)).hasPrefix("MTL") else { throw GigaAMError.metalUnavailable }
                guard String(cString: transcribe_model_variant_string(loaded)) == "gigaam-multilingual-large-ctc",
                    String(cString: transcribe_model_meta_val_str(loaded, "stt.gigaam.window_policy")) == "stock25-v1",
                    String(cString: transcribe_model_meta_val_str(loaded, "stt.gigaam.storage")) == "F16"
                else { throw GigaAMError.incompatibleModel }
                AppLogger.info(
                    "GigaAM native loaded: backend=\(String(cString: transcribe_model_backend(loaded))), package=\(expected.runtimePackageID ?? "unknown"), profile=f16-f32-stock25, language=auto, decoding=greedy-ctc, native_timestamps=none, token_alignment=available"
                )
            } catch {
                transcribe_model_free(loaded)
                throw error
            }
            model = loaded
            packageID = expected.runtimePackageID ?? ""
        }

        deinit { transcribe_model_free(model) }

        func transcribe(samples: [Float], token: NativeAbortToken, includeTimestamps: Bool) throws -> TranscriptionClientResult {
            var params = transcribe_session_params()
            transcribe_session_params_init(&params)
            params.n_threads = 4
            var session: OpaquePointer?
            try Self.check(transcribe_session_init(model, &params, &session))
            guard let session else { throw GigaAMError.incompatibleModel }
            defer { transcribe_session_free(session) }
            transcribe_set_abort_callback(
                session,
                { pointer in
                    guard let pointer else { return true }
                    return Unmanaged<NativeAbortToken>.fromOpaque(pointer).takeUnretainedValue().isCanceled
                }, Unmanaged.passUnretained(token).toOpaque())
            defer { transcribe_set_abort_callback(session, nil, nil) }
            var run = transcribe_run_params()
            transcribe_run_params_init(&run)
            run.timestamps = TRANSCRIBE_TIMESTAMPS_NONE
            let status = samples.withUnsafeBufferPointer { transcribe_run(session, $0.baseAddress, Int32($0.count), &run) }
            if token.isCanceled { throw CancellationError() }
            try Self.check(status)
            let text = String(cString: transcribe_full_text(session))
            let segments: [TranscriptionSegment]
            if includeTimestamps && !text.isEmpty {
                let tokenCount = max(0, Int(transcribe_n_tokens(session)))
                var alignedTokens: [GigaAMAlignedToken] = []
                alignedTokens.reserveCapacity(tokenCount)
                for index in 0..<tokenCount {
                    var nativeToken = transcribe_token()
                    transcribe_token_init(&nativeToken)
                    let tokenStatus = transcribe_get_token(session, Int32(index), &nativeToken)
                    guard tokenStatus.rawValue == 0, let tokenText = nativeToken.text else {
                        alignedTokens.removeAll()
                        break
                    }
                    alignedTokens.append(
                        GigaAMAlignedToken(
                            text: String(cString: tokenText),
                            startMilliseconds: nativeToken.t0_ms,
                            endMilliseconds: nativeToken.t1_ms
                        ))
                }
                let duration = Double(samples.count) / 16_000
                if let alignedSegments = GigaAMTokenAlignment.segments(text: text, tokens: alignedTokens, duration: duration) {
                    segments = alignedSegments
                } else {
                    AppLogger.info("GigaAM token alignment unavailable; returning text without timing")
                    segments = []
                }
            } else {
                segments = []
            }
            var timings = transcribe_timings()
            transcribe_timings_init(&timings)
            try Self.check(transcribe_get_timings(session, &timings))
            AppLogger.info(
                "GigaAM recognition completed: frontend_ms=\(timings.mel_ms), encoder_ms=\(timings.encode_ms), ctc_ms=\(timings.decode_ms), samples=\(samples.count), encoder=Metal, frontend=host, ctc=host, window_seconds=25, context_seconds=2"
            )
            return TranscriptionClientResult(
                text: text,
                segments: segments,
                executionDiagnostics: TranscriptionExecutionDiagnostics(
                    packageID: packageID, inputSampleCount: samples.count, nativeBackend: String(cString: transcribe_model_backend(model)),
                    loadMilliseconds: Double(timings.load_ms), frontendMilliseconds: Double(timings.mel_ms), encoderMilliseconds: Double(timings.encode_ms),
                    decodingMilliseconds: Double(timings.decode_ms)))
        }

        private static func check(_ status: transcribe_status) throws {
            try GigaAMNativeContext.checkStatus(Int32(status.rawValue))
        }
    }
#endif

nonisolated struct GigaAMAlignedToken: Sendable {
    let text: String
    let startMilliseconds: Int64
    let endMilliseconds: Int64
}

nonisolated enum GigaAMTokenAlignment {
    static func segments(text: String, tokens: [GigaAMAlignedToken], duration: TimeInterval) -> [TranscriptionSegment]? {
        guard let aligned = segment(text: text, tokens: tokens, duration: duration) else { return nil }
        var result: [TranscriptionSegment] = []
        var current: [TranscriptionWord] = []
        var characterCount = 0

        func appendCurrent() {
            guard let first = current.first, let last = current.last else { return }
            result.append(
                TranscriptionSegment(
                    text: current.map(\.text).joined(separator: " "),
                    startTime: first.startTime,
                    endTime: last.endTime,
                    words: current
                ))
            current = []
            characterCount = 0
        }

        for word in aligned.words {
            if let first = current.first, let last = current.last,
                word.endTime - first.startTime > 20 || word.startTime - last.endTime > 3 || characterCount + word.text.count + 1 > 240
            {
                appendCurrent()
            }
            current.append(word)
            characterCount += word.text.count + 1
        }
        appendCurrent()
        return result
    }

    static func segment(text: String, tokens: [GigaAMAlignedToken], duration: TimeInterval) -> TranscriptionSegment? {
        guard !tokens.isEmpty, duration.isFinite, duration > 0 else { return nil }
        var reconstructed = ""
        var words: [TranscriptionWord] = []
        var word = ""
        var wordStart = 0.0
        var wordEnd = 0.0
        var previousStart: Int64 = -1

        func appendWord() {
            if !word.isEmpty {
                words.append(TranscriptionWord(text: word, startTime: wordStart, endTime: wordEnd))
                word = ""
            }
        }

        for token in tokens {
            guard !token.text.isEmpty,
                token.startMilliseconds >= previousStart,
                token.startMilliseconds >= 0,
                token.endMilliseconds >= token.startMilliseconds,
                Double(token.endMilliseconds) <= duration * 1_000 + 100
            else { return nil }
            previousStart = token.startMilliseconds
            reconstructed += token.text
            for character in token.text {
                if character.isWhitespace {
                    appendWord()
                } else {
                    if word.isEmpty { wordStart = Double(token.startMilliseconds) / 1_000 }
                    word.append(character)
                    wordEnd = Double(token.endMilliseconds) / 1_000
                }
            }
        }
        appendWord()
        guard reconstructed == text, let first = words.first, let last = words.last else { return nil }
        return TranscriptionSegment(text: text, startTime: first.startTime, endTime: last.endTime, words: words)
    }
}
