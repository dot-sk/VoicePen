## ADDED Requirements

### Requirement: Nemotron recognizes complete recordings locally

VoicePen SHALL run the selected English Nemotron model through the packaged native runtime after capture has stopped and return only the completed transcript through the ordinary normalization, final insertion and history workflow. It SHALL read the complete prepared audio, including final partial read buffers. Model loading and inference SHALL not block app-facing state updates. Prepared requests SHALL retain their captured model, serialize access to mutable recognition state and start each recording with fresh decoder state.

#### Scenario: Recognize a complete recording

- **WHEN** a valid recording uses the installed Nemotron model
- **THEN** all prepared audio, including the final tail, contributes to one final English transcription and the existing workflow normalizes, inserts and records that result with the captured model identity

#### Scenario: Capture is still active

- **WHEN** the user records dictation with Nemotron selected
- **THEN** VoicePen performs no partial transcription display or incremental text insertion

#### Scenario: Requests overlap or selection changes

- **WHEN** model loading or recognition overlaps another request or the selected model changes
- **THEN** requests share compatible loading, retain the captured runtime safely and execute with isolated decoder state

#### Scenario: Recognition is canceled or fails

- **WHEN** Nemotron recognition is canceled, times out or fails
- **THEN** VoicePen emits no late transcript or partial insertion, releases the operation safely and permits another request without silently substituting another recognizer
