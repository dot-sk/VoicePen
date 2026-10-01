## 1. Lock behavior and test mappings

- [x] 1.1 Review the four delta specs against the current main specs and keep the change limited to RNNoise output conditioning plus one global decoding-profile setting.
- [x] 1.2 Map every RNNoise range, fallback, dictation-file, Meeting-source, and diagnostic scenario to direct Swift Testing coverage before changing production audio code.
- [x] 1.3 Map every profile default, persistence, selection, prepared-request, VAD-retry, and diagnostic scenario to settings, routing, and Whisper option tests before changing production decoding code.

## 2. Bound successful RNNoise output

- [x] 2.1 Add pure conditioner tests for empty and silent input, unchanged finite in-range samples, positive and negative over-range peaks, uniform scaling to `0.95`, preserved sample count and ratios, and rejection of non-finite samples.
- [x] 2.2 Extend dictation preprocessing and Meeting mastering tests to prove that conditioned output reaches the derived dictation file and microphone mix, invalid output takes the existing original-audio fallback, and system, raw, and recovery audio stay unchanged.
- [x] 2.3 Implement the pure RNNoise output conditioner after output resampling and sample-count repair, returning in-range audio unchanged and uniformly attenuating only over-range results.
- [x] 2.4 Route conditioner failures through the existing dictation and Meeting denoising fallback paths and add privacy-safe pre-peak, post-peak, and attenuation-applied diagnostics.

## 3. Persist and expose the decoding profile

- [x] 3.1 Add `AppSettingsStore` and controller tests for the standard default, maximum-quality persistence across reload, invalid-value fallback, immediate published updates, and the two supported Recognition choices.
- [x] 3.2 Add the sendable `standard` and `maximumQuality` profile model and persist it under the additive `transcription.decodingProfile` key without a database schema migration.
- [x] 3.3 Add an `AppController` update method and a Model settings Recognition picker that writes through the shared settings store and explains the latency-quality trade-off through the existing help-label pattern.

## 4. Route profiles into Whisper decoding

- [x] 4.1 Add decoder-option tests proving that standard selects greedy, maximum quality selects beam search, both retain current language, glossary, timestamp, VAD, thread, audio-context, suppression, and temperature behavior, and timings identify the profile.
- [x] 4.2 Add routing tests proving that a prepared transcription captures one profile, a later settings change affects only the next prepared request, a VAD retry keeps the captured strategy, and warmup remains on the standard strategy.
- [x] 4.3 Capture the profile beside the selected model in `RoutingTranscriptionClient.prepareTranscription()` and pass it through the Whisper client and context without widening the general `TranscriptionRequest` contract.
- [x] 4.4 Map standard to Whisper greedy defaults and maximum quality to Whisper beam-search defaults, then include the captured profile in privacy-safe lifecycle diagnostics and `WhisperCppTimings`.

## 5. Verify behavior and quality trade-offs

- [x] 5.1 Run `openspec validate normalize-rnnoise-and-add-quality-decoding --strict`, `make validate-specs`, and `make format-check`.
- [x] 5.2 Run `make test`.
- [x] 5.3 Run `make build` to verify app-target settings and live transcription wiring.
- [x] 5.4 Manually inspect Model settings to confirm both profiles are selectable, persist after restart, and do not trigger a model download or reload.
- [x] 5.5 Compare the same short clean and overloaded microphone recordings with standard and maximum-quality decoding, recording input peaks, transcript differences, and elapsed decode time without adding user audio or transcript content to repository fixtures or logs.
- [x] 5.6 Confirm one push-to-talk and one Meeting run keep existing boost, selected-input, RNNoise fallback, VAD retry, timestamp, and timeout behavior.
