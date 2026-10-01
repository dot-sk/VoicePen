# Audio Input Selection Specification

## Purpose

Let users choose which microphone VoicePen records while preserving the existing system-default behavior for users who do not make a selection.

## Requirements

### Requirement: Settings expose microphone selection

VoicePen SHALL provide one microphone picker in the existing Audio settings section. The picker SHALL contain a `System default` option and every currently available audio input device, and SHALL indicate the active selection.

#### Scenario: User has multiple microphones
- **WHEN** Settings opens while more than one audio input device is available
- **THEN** the microphone picker shows `System default` and each available input device as selectable options

#### Scenario: No manual selection exists
- **WHEN** a new or existing installation has no saved microphone selection
- **THEN** the microphone picker selects `System default`

### Requirement: Microphone selection persists

VoicePen SHALL persist a manually selected input device by stable device identity and restore that selection after an app restart. A valid saved selection SHALL remain associated with the same physical or virtual input device even if its runtime identifier or display name changes.

#### Scenario: Selected device survives restart
- **WHEN** the user selects an available microphone and restarts VoicePen
- **THEN** VoicePen restores that microphone as the active selection

#### Scenario: Stored selection is malformed
- **WHEN** VoicePen loads a stored microphone selection that cannot identify a device
- **THEN** VoicePen uses `System default` and saves no invalid active selection

### Requirement: Selected microphone drives microphone capture

VoicePen SHALL use the active microphone selection for push-to-talk dictation and the microphone source in Meeting Mode. `System default` SHALL resolve to the current macOS default input device when a new capture is prepared. VoicePen MUST NOT change the macOS system-default input device.

#### Scenario: Dictation uses a selected microphone
- **WHEN** the user selects a specific available microphone and starts push-to-talk dictation
- **THEN** VoicePen captures dictation audio from that microphone

#### Scenario: Meeting uses a selected microphone
- **WHEN** the user selects a specific available microphone and starts Meeting Mode
- **THEN** VoicePen captures the Meeting microphone source from that microphone

#### Scenario: System default follows macOS
- **WHEN** `System default` is selected and macOS changes its default input device before the next recording
- **THEN** the next dictation or Meeting microphone capture uses the new macOS default

#### Scenario: Selection changes during capture
- **WHEN** the user changes the microphone selection while a recording is active
- **THEN** the active recording continues with its original microphone and the next recording uses the new selection

### Requirement: Dictation gain targets the captured microphone

When dictation microphone boost is enabled, VoicePen SHALL attempt to change and restore input gain on the same device selected for dictation capture. Gain handling SHALL remain best-effort and SHALL NOT block recording when the selected device has no settable input gain.

#### Scenario: Selected microphone supports input gain
- **WHEN** dictation starts with microphone boost enabled and the selected microphone exposes settable input gain
- **THEN** VoicePen boosts that device for the recording and restores the gain it changed when dictation ends

#### Scenario: Selected microphone has no settable input gain
- **WHEN** dictation starts with microphone boost enabled and the selected microphone has no settable input gain
- **THEN** VoicePen records from the selected microphone without a blocking gain error

### Requirement: Device availability stays current

VoicePen SHALL refresh microphone choices when input devices are connected, disconnected, or renamed. If a manually selected device is unavailable, VoicePen SHALL retain and display that selection as unavailable, SHALL NOT silently substitute another microphone, and SHALL reject new microphone capture with an actionable error. VoicePen SHALL make the selection available again when the same device returns.

#### Scenario: New microphone is connected
- **WHEN** macOS reports a newly available audio input device while VoicePen is running
- **THEN** the microphone picker adds it without requiring an app restart

#### Scenario: Selected microphone disconnects
- **WHEN** the manually selected microphone becomes unavailable
- **THEN** Settings keeps it selected, marks it unavailable, and new dictation or Meeting microphone capture does not use another device

#### Scenario: Selected microphone reconnects
- **WHEN** an unavailable selected microphone with the same stable identity becomes available again
- **THEN** VoicePen restores it as an available selection without requiring the user to select it again
