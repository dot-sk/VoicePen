# Dictation word confidence

## Purpose

Help users review saved dictations by marking words for which the recognizer produced a low-confidence signal, without changing the text or claiming calibrated correctness.

## Requirements

### Requirement: Word review hints use available recognition evidence

VoicePen SHALL derive optional word review hints from valid confidence values in the original recognition result without rerunning recognition, changing decoding settings, or requiring word timestamps solely for this feature. It SHALL associate hints with complete displayed words, including Russian and mixed-script text, rather than displaying individual tokenizer fragments. Hints SHALL be described as review suggestions rather than probabilities that a word is correct.

#### Scenario: Native tokens split a Russian word

- **WHEN** valid low-confidence tokens include fragments of a Russian word or UTF-8 character
- **THEN** VoicePen preserves the recognized text and associates a review hint with the complete word without corrupting character boundaries

#### Scenario: Confidence is absent or invalid

- **WHEN** a recognizer returns no confidence or non-finite or out-of-range confidence values
- **THEN** VoicePen keeps the text and does not invent a confidence estimate for affected words

### Requirement: Review hints stay aligned with final dictation text

VoicePen SHALL display hints only where their association with the final displayed word is established. Dictionary, alias, command, sanitization, and output-normalization transformations SHALL NOT move a hint onto an unrelated word.

#### Scenario: Normalization replaces a word or command

- **WHEN** a text transformation replaces recognized words or produces a command
- **THEN** VoicePen suppresses hints for transformed content unless a reliable mapping exists and preserves valid hints for unaffected content

### Requirement: Saved review hints remain compatible with history lifecycle

VoicePen SHALL retain available hints with a saved session across restarts and text compression, validate their ranges before use, and remove text-associated hints when the corresponding text payload is evicted. Older sessions SHALL load without requiring new recognition or invented hints.

#### Scenario: Session with hints is saved and reloaded

- **WHEN** text with review hints is saved, compressed, and later loaded
- **THEN** the hints remain associated with the same words

#### Scenario: History text is evicted or hints are malformed

- **WHEN** a history payload is evicted or contains malformed or stale hint ranges
- **THEN** VoicePen removes or ignores unusable hints without preventing history loading

#### Scenario: Older session or unsupported recognizer

- **WHEN** a session has no stored usable confidence metadata
- **THEN** the text is available with the existing reading behavior and no synthetic highlights

### Requirement: Sessions exposes review hints without changing text actions

VoicePen SHALL visually distinguish low-confidence words in Sessions detail and expose a textual review explanation. It SHALL preserve reading, selection, search, copy, and insertion semantics and SHALL NOT treat unhighlighted text as verified correct.

#### Scenario: User reads a dictation with review hints

- **WHEN** a session has valid word review hints
- **THEN** Sessions displays the affected words with a review indication and an accessible textual explanation

#### Scenario: User copies or inserts highlighted text

- **WHEN** the user copies selected text, copies the complete session, or inserts it
- **THEN** VoicePen provides the same plain text without review annotations or formatting

### Requirement: GigaAM provides native dictation review evidence

VoicePen SHALL expose usable confidence evidence from the selected supported GigaAM CTC result without a second inference pass, requiring timestamps, changing model weights, or changing greedy text decoding. The native backend SHALL retain normalized finite probabilities for emitted symbols when scores are valid and SHALL distinguish missing scores from low confidence. It SHALL preserve decoded token IDs, order, timing positions, and the existing handling of blank-separated repetitions and long-recording windows.

#### Scenario: GigaAM dictation produces valid symbol probabilities

- **WHEN** the supported GigaAM backend completes dictation with valid CTC scores and timestamps are disabled
- **THEN** VoicePen maps the evidence to complete recognized words and can display review hints in the existing Sessions text field
- **AND** the text, selection, plain copy, and insertion behavior remain unchanged

#### Scenario: CTC symbols repeat across frames or blank boundaries

- **WHEN** identical symbols occupy consecutive frames or recur after a blank
- **THEN** confidence extraction retains the existing collapsed symbols and frame positions and aggregates evidence within each retained symbol run without merging blank-separated symbols

#### Scenario: GigaAM word scores use a different scale

- **WHEN** a GigaAM word receives a review hint
- **THEN** VoicePen applies a separately reviewed GigaAM policy and preserves that policy with stored hints instead of applying the Whisper threshold on reload

#### Scenario: GigaAM score metadata is unavailable or invalid

- **WHEN** native evidence is missing, non-finite, invalid, or cannot be aligned with the actual result text
- **THEN** VoicePen preserves the recognized text and suppresses unsupported hints without substituting zeros or invoking another recognizer

### Requirement: GigaAM confidence upgrade reuses unchanged installed weights

VoicePen SHALL reuse an already installed supported GigaAM artifact when upgrading from the known previous runtime to its confidence-capable successor if the installation's model ID, model version, artifact size, and content digest match the current artifact. It SHALL retain full artifact verification at native model load and SHALL NOT accept arbitrary runtime transitions or mismatched artifacts.

#### Scenario: Existing GigaAM weights match the confidence runtime

- **WHEN** the previous supported GigaAM runtime's installation marker describes the same model ID, model version, size and digest required by the confidence-capable runtime and the artifact still has the expected size
- **THEN** VoicePen treats the weights as installed without downloading them again and verifies the artifact before native loading

#### Scenario: Installation identity or runtime is incompatible

- **WHEN** the saved marker has different model identity, digest or size, the file size is wrong, or the runtime transition is not explicitly supported
- **THEN** VoicePen does not reuse that installation as a compatible confidence upgrade
