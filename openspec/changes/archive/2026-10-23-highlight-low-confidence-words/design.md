## Context

Whisper.cpp v1.8.5 exposes whisper_full_get_token_p during normal decoding. Its CLI color feature operates on tokens, not whole words. Initially VoicePen discarded confidence, stored raw/final text, and rendered session detail with a read-only STTextView. Native GigaAM's token API has a probability field, but candidate.2 constructed tokens without populating it and its implementation default was zero. The API documents NaN for unavailable evidence; candidate.3 now supplies real CTC scores and follows that convention for invalid score evidence.

## Goals / Non-Goals

Make saved dictations easier to inspect using evidence already produced by recognition. Keep DictationPipeline and AppController responsibilities unchanged. Meetings, live overlays, punctuation, model changes, and extra inference are excluded.

## Decisions

- Add optional native confidence metadata to recognition results and forward it through routing. Do not enable token timestamps or change decoding to obtain probability.
- Reconstruct complete UTF-8 token bytes before mapping to Unicode word ranges. Skip special tokens. Validate reconstruction against recognized segment text and discard ambiguous ranges.
- Use the minimum valid token probability for a word and a centralized review threshold of 0.3. Reviewing 32 confirmed examples produced 48 hints at the candidate threshold 0.5, including correct short phrases, and 14 hints at 0.3. Choose the quieter policy; neither score is a calibrated probability of correctness. See confidence-review.md for false positives and missed errors.
- Associate stored ranges with the exact displayed text. Map unchanged words through normalization conservatively; discard hints for replacements, command output, or ambiguous alignment instead of guessing.
- Add an optional compressed word_confidence BLOB through migration 13. Store only review hints with a version and SHA-256 of the exact final text. Count compressed metadata in the existing total payload budget, retain it during text compression, and clear it on eviction. Tolerate absent, malformed, unsupported-version, or stale metadata.
- Render via existing attributed text support, with subtle amber indication and a textual/accessibility explanation. Keep plain text actions unchanged. GigaAM without scores and legacy sessions use the existing rendering.
- Keep the existing Sessions editor and controls. Do not add a confidence screen, separate text block, counter, or extra control; provide the explanation on hover and through the text view's accessibility help.

## Risks / Trade-offs

- Token confidence can miss confident mistakes and flag correct words. Validate highlights on actual examples and explain their limited meaning.
- Unicode boundaries and text normalization can misalign spans. Favor missing a hint over highlighting unrelated content and test repeated words and mixed scripts.
- Per-word metadata grows with text. Include it in the existing text-payload lifecycle rather than retaining it indefinitely after eviction.
- A rendering-only change might leave stale attributes after session or theme changes. Reapply hints when either confidence or text revisions change without resetting user selection unnecessarily.

## GigaAM extension

The user authorized completing the native CTC backend and Swift adapter. The old implementation's TokenEntry probability actually defaults to zero and is never assigned by the GigaAM decoder; the previous NaN description referred to the API's missing-score convention, not this implementation. Do not consume those old placeholder zeros as evidence.

Maintain a third source patch on the pinned archive and use a distinct candidate/runtime identity. Preserve token IDs and original first-frame positions. For each nonblank collapsed run retain the maximum normalized posterior of the winning symbol across that run; blank-separated occurrences remain separate. Reuse existing log-softmax output in the supported host-head path. The raw-logit diagnostic path normalizes scores before exposing them. Invalid score evidence remains unavailable.

The Swift adapter reads symbol probabilities regardless of timestamp options, replaces SentencePiece boundaries consistently with existing text decoding, and verifies exact reconstructed text before attaching word evidence. GigaAM word scores use a separately reviewed threshold, stored with the hint so persistence and rendering never silently reapply the Whisper threshold. The existing editor and all no-extra-interface constraints remain unchanged.

GigaAM uses threshold 0.6 after inspecting 42 confirmed examples; see confidence-review.md. Word metadata gains an optional threshold, so preexisting Whisper hints still use their original 0.3 policy. Known candidate.2 installation markers are compatible with candidate.3 only when model ID, version, size and digest match; model loading still verifies the complete artifact. No installation marker or user setting is rewritten by that compatibility check.

Validate old/new native output and wall times with the same weights, input audio, threads and options. Existing incomplete release-acceptance gates remain incomplete; producing and verifying a new local candidate is not publication or general acceptance of the original dependency.
