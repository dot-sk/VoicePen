## Context

See proposal.md for motivation. MeetingSpeakerAnalysis currently prefers the backend speaker roster when computing the count. Filtering only turns would therefore leave a stale count. Confirmation must provide one participant set to both the transcript formatter and persistence.

The private two-meeting comparison found Nemotron offline counts of 3/3 for user-confirmed participant counts of 3/2, compared with SpeakerKit 5/3. Nemotron fast128 returned 3/5. This does not establish full timeline accuracy. The user identified office background speech in the first extra Nemotron interval at 901.13 seconds. Its extra identity spans about 29 seconds across 13 postprocessed turns, so a three-turn rule alone is inadequate.

## Goals / Non-Goals

**Goals:** Confirm participants using meeting-wide evidence, keep text intact, and prevent count/label inconsistencies.

**Non-Goals:** Change the production model, suppress audio, train a model, add voice enrollment UI, or automatically rewrite history. Keep this separate from slim-diarization-runtime, whose parity gate must remain an extraction comparison.

## Decisions

### Evaluate evidence before fixing thresholds

Build a deterministic local confirmation helper over validated finite intervals. Coalesce fragments into contribution episodes, compute union duration without double counting, independent-episode support and usable non-overlapped speech. A missing confidence score is not zero confidence. Do not use a percentage of meeting length as the sole rejection rule. Preserve a sole usable voice in short recordings.

Evaluate at most six predeclared policies including the unchanged baseline. Freeze parameters before a held-out check; document exact constants and measured failures before production integration. Use focused synthetic contract fixtures and independently reviewed real intervals, not merely the desired aggregate speaker count. The two existing meetings are development examples, not independent evidence of generalization. If background speech and real infrequent participants cannot be separated with available evidence, do not ship an arbitrary count-correcting heuristic. Report that outcome and keep baseline behavior.

### Use one confirmation result

Place confirmation before transcript assignment and final counting, retaining the accepted identity set and rejection reasons. Rebuild the roster from accepted identities. Regions with only unconfirmed speech remain unattributed; do not bridge a rejected interval by extending another person's turn. Preserve stable labels for accepted identities within the processing run. No persisted candidate state or schema change is needed for this offline pass.

### Conversation membership is a distinct inference problem

Relevant primary research:

- Chen et al., Interspeech 2024, [Target conversation extraction: Source separation using turn-taking dynamics](https://www.isca-archive.org/interspeech_2024/chen24d_interspeech.pdf), uses a participant enrollment embedding and conversational timing to separate a target conversation from interfering speakers. [Author code and checkpoints](https://github.com/chentuochao/Target-Conversation-Extraction) are available. This is a learned source-separation model, not validation of a minimum-turn heuristic.
- Hu et al., EMNLP 2025, [Proactive Hearing Assistants that Isolate Egocentric Conversations](https://aclanthology.org/2025.emnlp-main.1289/), uses self-speech as an anchor plus conversational dynamics with binaural wearable audio. That input assumption differs from VoicePen's captured meeting tracks.

Our inference from these papers is that interaction timing deserves evaluation alongside duration. Their results do not establish a threshold or Russian-language performance for VoicePen. A learned membership or extraction model would require a separate decision and evaluation if simple evidence is insufficient.

## Risks / Trade-offs

- Infrequent genuine participant rejected: include brief substantive contributions and highly imbalanced conversations in acceptance fixtures; never optimize only the total count.
- Repeated background conversation passes simple thresholds: independently annotate the problematic intervals and block integration if the policy cannot distinguish them reliably.
- Labels become inconsistent with count: one accepted roster drives both outputs; test backend rosters containing rejected IDs.
- Overlap handling removes legitimate interruptions: use overlap as evidence, not an unconditional rejection.

## Migration Plan

Complete offline evaluation first, then implement only a passing frozen policy with automated tests. Run strict OpenSpec validation and make test before handoff. New processing and explicit retries use the policy; existing history is untouched. Rollback removes the confirmation call without a data migration.
