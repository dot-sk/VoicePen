## ADDED Requirements

### Requirement: Dictation uses the captured selected recognizer

When GigaAM is selected, prepared dictation SHALL use that model's accepted local runtime and captured effective capabilities through the same application routing service used by Meetings. Existing Whisper-specific shared-client wording SHALL apply to Whisper requests; GigaAM requests SHALL use their own shared backend service. The existing capture, preprocessing, normalization, insertion, history, empty-output, and timeout contracts SHALL remain in effect. History SHALL identify the model that actually produced the result, regardless of later selection changes.

#### Scenario: Complete GigaAM dictation

- **WHEN** valid dictation is prepared with an installed GigaAM model
- **THEN** it runs offline with that captured model, inserts normalized non-empty text, and records GigaAM model and app metadata through the existing history path

#### Scenario: Selection changes after dictation preparation

- **WHEN** a prepared dictation request waits or runs while the selection changes
- **THEN** the request retains its captured recognizer and effective configuration, and the next prepared request uses the new selection

#### Scenario: Cancel or time out native GigaAM dictation

- **WHEN** GigaAM dictation is canceled or reaches its processing timeout
- **THEN** VoicePen aborts queued or active recognition, prevents late text insertion or success history, leaves dictation processing, and permits another request without changing Meeting lifecycle state

#### Scenario: GigaAM returns silence or fails

- **WHEN** GigaAM returns no usable speech or a native recognition error
- **THEN** VoicePen follows its existing empty-output or error path without inserting invented text, silently switching recognizers, or leaving the next dictation blocked
