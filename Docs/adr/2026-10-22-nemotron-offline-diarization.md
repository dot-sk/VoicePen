# ADR: Nemotron offline meeting diarization

Date: 2026-10-22

## Status

Accepted. Supersedes the backend choice in
[the previous boundary ADR](2026-05-07-meeting-diarization-backend-boundary.md).

## Decision

Use Nemotron-3 offline with FluidAudio exactly 0.17.7 behind a small local Swift
package. Disable the optional NemoTextProcessing trait. Remove SpeakerKit and
its Argmax dependency graph from both the app and unit-test package.

Keep VoicePen's full-timeline 16 kHz input, existing turn postprocessor and
transcript assignment. The adapter retains native speaker cache state throughout
one recording, and creates fresh state for another. Use local-only Core ML
loading with the tested `.all` compute policy. VoicePen owns immutable per-file
SHA-256/size verification, proxy configuration and transactional installation.
Legacy settings normalize to Nemotron; saved history is not rewritten.

Load diarization only for analysis. Do not preload it on app startup, enabling
diarization or completing a download. Release the retained runtime immediately
after the last active operation, including errors and cancellation. Diagnostic
validation releases its runtime too. Meetings are not frequent enough to justify
keeping several hundred MiB resident between analyses. Core ML can retain system
caches after VoicePen releases its references, so lower RSS is not guaranteed.
Fresh diagnostic processes each took about 46 seconds to load, while same-process
reloads took about 0.1 seconds. Accept this trade-off instead of idle residency.

## Evidence and trade-offs

On the two private frozen meetings, the selected offline preset produced three
speaker IDs on each. The long meeting contains two main participants and an
occasional background voice. The intended behavior permits that occasional third
label while preserving the two main identities. There is no complete manual
speaker annotation, so these comparisons do not establish global accuracy.

Streaming and whole-buffer predictions matched exactly on the long input before
integration. The earlier size-only Release experiment measured +4.54 MiB of app
files after removing SpeakerKit, excluding downloaded models. This overhead is
accepted to avoid maintaining our own inference/cache implementation.

Keeping the ready library adds unused upstream resources. Extracting a smaller
fork can be reconsidered if measured distribution cost warrants ongoing upkeep.
Participant filtering, custom embeddings and a custom voice matcher are outside
this decision.

## Verification

Automated installation/settings/pipeline coverage runs through `make test`.
The opt-in native regression compares every turn against frozen outputs for both
inputs, repeats analysis and checks canceled analysis followed by reset/retry.
SwiftPM tests and a Release Xcode build independently verify dependency wiring.
Runtime and model provenance are recorded in `Vendor/diarization.spm/README.md`.
