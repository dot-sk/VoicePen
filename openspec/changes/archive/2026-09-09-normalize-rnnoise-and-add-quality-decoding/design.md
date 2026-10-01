## Context

See `proposal.md` for motivation and the delta specs for required behavior.

`RNNoiseAudioDenoiser` currently rescales RNNoise frames back to floating-point
PCM and returns the resampled output without checking peak amplitude. Dictation
processes one complete recording per call. Meeting Mode invokes the same
denoiser on bounded microphone windows before its existing source-level
normalization and master headroom pass. Both callers already treat a thrown
denoising error as a reason to use the original microphone audio.

`WhisperCppContext` currently creates greedy default parameters for every
decode. `RoutingTranscriptionClient.prepareTranscription()` already captures the
selected model before returning a prepared operation, which is the right
lifecycle point to capture a decoding profile. Model settings and other
persistent choices flow through `AppSettingsStore` and `AppController`.

## Goals / Non-Goals

**Goals:**

- Keep successful RNNoise output finite and inside the supported floating-point
  PCM range without changing sample count or amplifying safe audio.
- Use one conditioning rule for dictation and Meeting microphone processing.
- Let users choose between current greedy decoding and beam search without
  changing models or backend routing.
- Capture the profile once per prepared transcription so concurrent settings
  changes cannot alter an active request.
- Preserve useful privacy-safe diagnostics for peak conditioning, strategy, and
  latency comparison.

**Non-Goals:**

- Loudness-normalizing quiet microphone recordings.
- Changing the microphone-boost default or RNNoise enablement policy.
- Adding a compressor, automatic gain controller, cloud backend, new model, or
  per-mode decoding settings.
- Changing transcription timeouts, glossary behavior, VAD policy, timestamp
  behavior, or model warmup lifecycle.
- Building an automatic WER benchmark or reading saved user recordings in unit
  tests.

## Decisions

### Condition the final output of each RNNoise operation

Add a small pure sample-conditioning type used by
`RNNoiseAudioDenoiser.process` after output resampling and sample-count repair.
It validates that every sample is finite and finds the maximum absolute sample
value.

If the peak does not exceed full scale, return the samples unchanged. If it
does, apply one uniform gain to the complete returned buffer so its peak reaches
a named headroom target below full scale. A target of `0.95` leaves margin while
avoiding needless attenuation of valid output. The operation preserves sample
count, polarity, and relative amplitude. Invalid or non-finite output throws
through the existing denoising fallback in both callers.

Putting the conditioner inside the denoiser gives dictation and Meeting one
rule and keeps downstream file writers unaware of RNNoise behavior. Meeting
continues to apply its existing whole-master source gain and mix headroom after
each denoised microphone window.

Alternative considered: clamp each out-of-range sample. Rejected because hard
clipping changes the waveform and creates harmonics.

Alternative considered: normalize every recording toward a target loudness.
Rejected because the evidence only establishes excessive peaks. Amplifying
quiet recordings would change microphone-gain behavior and noise levels without
supporting measurements.

Alternative considered: disable microphone boost or RNNoise by default.
Rejected because both behaviors are established settings contracts and the
observed files do not isolate either one as the sole cause.

### Persist one global decoding-profile enum

Introduce a sendable, raw-representable local decoding profile with two values:
`standard` and `maximumQuality`. Store it under an additive
`transcription.decodingProfile` key in the existing SQLite key-value table.
Missing and unknown values normalize to `standard`. The Model settings
Recognition section binds directly through `AppController` and
`AppSettingsStore`.

Use one global choice for dictation and Meeting because both share the selected
local model, language, and transcription client. Separate settings would add
state without evidence that users need different policies.

Alternative considered: make beam search the new default. Rejected because it
would raise latency for every existing installation and could increase timeout
risk without a measured quality baseline.

Alternative considered: infer the strategy from the selected model
quantization. Rejected because model size and decoding search are independent
trade-offs.

### Capture the profile when transcription is prepared

Give `RoutingTranscriptionClient` a profile provider next to the model provider.
`prepareTranscription()` reads both once and passes the captured profile through
the Whisper client and context. Push-to-talk and Meeting already use this
prepared-operation boundary, so a settings change affects the next request
without mutating a request that is loading or decoding.

Do not add the profile to `TranscriptionRequest`. That request is assembled
after model readiness and is also used by test doubles and non-Whisper
boundaries. Reading the live setting there would weaken the captured-request
contract.

Model warmup always uses the standard strategy. Warmup only establishes model
readiness and should not pay the beam-search cost or restart when the profile
changes.

Alternative considered: read the setting inside `WhisperCppContext` immediately
before decoding. Rejected because an in-flight prepared request could silently
change behavior while waiting for shared model readiness.

### Map profiles only at the Whisper parameter boundary

Keep the existing language, glossary prompt, timestamp, VAD, audio-context,
thread-count, suppression, and temperature settings. Standard uses
`WHISPER_SAMPLING_GREEDY`. Maximum quality uses
`WHISPER_SAMPLING_BEAM_SEARCH` with the vendored default bounded beam width.
The VAD retry reuses the same parameter set, so removing VAD does not downgrade
the chosen search strategy.

Record the profile in `WhisperCppTimings` and privacy-safe lifecycle diagnostics.
Do not log transcript text, glossary content, or audio data.

Alternative considered: add beam width, patience, and temperature controls to
Settings. Rejected because that exposes decoder internals and expands the
compatibility surface before the two useful profiles have been measured.

## Risks / Trade-offs

- [One extreme RNNoise sample can attenuate a complete processed buffer] ->
  Apply attenuation only when full scale is exceeded, retain a `0.95` peak
  target, and log pre/post peaks so real recordings can show whether a later
  dynamics processor is justified.
- [Meeting denoises bounded windows rather than the full source in one call] ->
  Preserve each window's sample count and let the existing whole-master gain and
  headroom passes keep the final mix consistent.
- [Beam search may be slower without improving every utterance] -> Keep standard
  as the default, expose the choice, include the profile in timings, and compare
  both profiles on the same audio during manual validation.
- [Beam search may approach the existing dictation processing timeout on long
  recordings] -> Keep timeout behavior unchanged in this narrow change, cover
  timeout propagation, and treat a measured need for profile-specific timeouts
  as a separate behavior change.
- [A future transcription backend may not support these profiles] -> Keep the
  setting named for local decoding and map it inside the Whisper backend rather
  than widening the general request contract.
- [The active audio-input selection change touches shared settings and live
  wiring] -> Add fields and closures without replacing its selection
  coordinator or reverting its current edits.

## Automated Test Mapping

RNNoise scenarios map to:

- `RNNoiseOutputConditionerTests` for empty, silent, finite in-range,
  positive/negative over-range, uniform gain, sample-count preservation,
  non-finite rejection, and peak/attenuation diagnostic values.
- `RNNoiseAudioDenoiserTests` for the concrete RNNoise integration point,
  conditioned dictation input-file samples, unchanged safe samples, and the
  existing original-audio fallback after conditioning failure.
- `MeetingPipelineTests` for conditioned microphone samples reaching the
  master, invalid microphone output falling back to the original source, and
  system-audio plus source-span/recovery references remaining unchanged.

Decoding-profile scenarios map to:

- `AppSettingsStoreTests` for the standard default, immediate published
  updates, reload persistence, and missing or invalid stored-value fallback.
- `AppControllerTests` for the controller write-through path and the two
  supported Recognition choices.
- `WhisperCppTranscriptionClientTests` for greedy/beam option selection,
  unchanged language, glossary, timestamp, VAD, thread, audio-context,
  suppression, and temperature options, VAD retry strategy reuse, warmup
  strategy, and timing/diagnostic profile identity.
- `RoutingTranscriptionClientTests` for prepared-request profile capture and
  the next prepared request observing a later settings change.

## Migration Plan

1. Add delta contracts and automated test mappings before production code.
2. Add the pure RNNoise output conditioner and direct unit tests, then route
   successful denoiser output through it.
3. Add the decoding-profile model, SQLite normalization and persistence, and the
   Recognition settings binding.
4. Capture the profile in prepared transcription and map it to Whisper
   parameters and diagnostics.
5. Run focused tests, strict OpenSpec validation, repository spec and format
   checks, `make test`, and `make build`.
6. Manually compare the same short clean and overloaded recordings with both
   decoding profiles and inspect latency plus transcript differences.

Rollback removes the UI and routing for the new setting and restores greedy-only
parameter creation. The additive SQLite value can remain because older code
ignores it. Removing the RNNoise conditioner restores the prior signal path and
requires no data migration.
