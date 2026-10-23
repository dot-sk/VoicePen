## Context

FluidAudio is already pinned at 0.17.7 in the local native adapter package. The existing transcription router captures models and capabilities, and model installation verifies declared artifacts. English Nemotron offers a greedy RNNT file-compatible path using its internal chunked decoder.

## Decisions

- Add an adapter to the existing native package and a separate core Nemotron client, keeping AppController as composition wiring. Reuse the existing router, execution gate, context lease and verified artifact downloader rather than creating another framework integration.
- Use the upstream 2240 ms English tier at revision `e673531caa6d25ab7baf5a8c14c9b99ba1551838`. Load local files only; no upstream auto-download call or partial callback runs in recognition. Iterate prepared file buffers and flush the tail once.
- Preserve the existing file workflow and preprocessing. Only final text is exposed. Timestamp-dependent Meeting controls remain unavailable for this first integration; existing saved preferences are retained.
- Add effective fixed-language and decoding descriptions so an English-only model does not misleadingly display automatic multilingual CTC settings.
- Install the exact upstream file set through proxy-aware verified downloads with a revision-compatible completion marker. Limit the upstream-source exception to immutable Nemotron URLs. This follows the existing Nemotron diarization delivery and avoids publishing another copy of the weights.
- Coalesce compatible loads, lease prepared contexts, serialize complete inference operations and release inactive contexts only after their last owner. Cancellation never resets a manager still executing another operation.

## Risks / Trade-offs

- Core ML calls cannot necessarily be interrupted mid-prediction. Check cancellation between bounded audio chunks and suppress late output through the existing pipeline checks.
- The English tier is a distinct download and allocation from diarization. Verify a real local inference and repeated requests rather than treating successful compilation as runtime evidence.
- Upstream published benchmark results do not establish quality on Sergey's speech. The runtime smoke test checks usable English output and lifecycle, not an optimization claim.
