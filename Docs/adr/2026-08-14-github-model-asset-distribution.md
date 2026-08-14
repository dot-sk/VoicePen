---
id: ADR-0010
status: accepted
date: 2026-08-14
---

# Distribute Local Models Through GitHub Releases

## Context

VoicePen installs large local transcription and diarization models on demand.
Hugging Face is unavailable to some users, while VoicePen already distributes
the application through GitHub Releases and has a small user base.

## Decision

Publish model binaries outside the Git repository in an immutable, separately
versioned GitHub Release. The application bundles direct asset descriptors with
byte sizes and SHA-256 digests and performs no Hugging Face requests at runtime.

Whisper artifacts are published separately so the shared Core ML encoder is not
duplicated. SpeakerKit's selected W8A16/W32A32 files are published as one archive
with their original license notices. Published assets are never overwritten;
updates use a new model-assets version and an application manifest update.

## Consequences

Users who can reach GitHub can install every supported local model without
Hugging Face. Model publication becomes a release prerequisite and must verify
asset hashes before an application version references them. Existing installed
models and completion markers remain compatible.

The selected SpeakerKit Core ML repository does not declare one top-level model
license. Mirroring therefore retains its upstream notices and attributions but
continues to carry the accepted licensing uncertainty documented during this
decision.

## Links

- `Specs/2026-05-02-local-transcription-model-handling.md`
- `Specs/2026-05-05-meeting-recording-mode.md`
- `VoicePen/Resources/model-manifest.json`
