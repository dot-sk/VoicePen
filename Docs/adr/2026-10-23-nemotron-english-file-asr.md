# ADR: Nemotron English file recognition

Date: 2026-10-23

## Status

Accepted.

## Decision

Offer the English Nemotron Speech 0.6B Core ML model as an optional recognizer
through the existing model selection and record-then-transcribe workflow. Reuse
FluidAudio exactly 0.17.7 from the existing native package, without another ML
framework or changes to the recommended Whisper model.

Use the upstream 2240 ms tier at revision
`e673531caa6d25ab7baf5a8c14c9b99ba1551838`. Its internal chunked RNNT decoding
runs only after capture stops; the app exposes only the final transcript. Keep
English and greedy RNNT fixed, retain preferences for other recognizers and do
not advertise timestamps, confidence, decoder prompts, VAD or configurable beam
search that this adapter does not provide.

Use immutable, size- and SHA-256-verified Hugging Face files for this model,
following the existing Nemotron diarization delivery. Limit the exception to
this model's repository, immutable revision and selected tier. Reuse proxy-aware
downloads, confirmed installation and app-managed deletion. Mirroring weights
in a new GitHub Release would add publication and maintenance work without
changing the runtime; no mirror is needed for this integration.

Serialize load and complete inference operations through one execution gate.
Prepared requests retain leased contexts across selection changes. Read every
prepared file buffer, flush its final tail and reset decoder state for each
recording. Suppress canceled results and discard a failing cached runtime before
the next prepared request. Core ML uses the CPU plus Neural Engine policy;
this does not establish per-operation hardware placement.

## Verification and limits

The native adapter passed a public JFK English recording, complete-input sample
count verification, repeated recognition and canceled-request recovery. Unit
tests cover installation identity, verified file reuse, routing, effective
settings, captured requests, shared loading and serialization. These checks do
not establish comparative quality or latency on personal recordings.

Runtime and model provenance and license references are recorded in
`Vendor/diarization.spm/README.md`.
