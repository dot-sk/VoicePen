## ADDED Requirements

### Requirement: Status menu reflects current state automatically

VoicePen SHALL refresh its menu bar status from the current app and dictation state after a state transition, without requiring the user to open the menu or waiting for another state change.

#### Scenario: Processing returns to readiness

- **WHEN** processing finishes and VoicePen becomes ready
- **THEN** the menu bar status returns to its ready state automatically

#### Scenario: Processing ends in a warning or an active meeting

- **WHEN** processing ends and the current state is a warning, meeting recording, or meeting processing
- **THEN** the menu bar status automatically reflects that current state

#### Scenario: State changes happen in quick succession

- **WHEN** multiple status-affecting state transitions happen before the menu bar refresh is handled
- **THEN** the menu bar status reflects the latest state without waiting for another transition
