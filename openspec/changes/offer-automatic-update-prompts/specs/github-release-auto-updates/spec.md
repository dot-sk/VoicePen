## ADDED Requirements

### Requirement: Visible automatic update offers by default

VoicePen SHALL enable automatic update discovery on an hourly default schedule
and use Sparkle's standard visible update offer with user-approved installation.
This supersedes the automatic download preparation default in GitHub Release
Auto Updates. VoicePen SHALL NOT default to silently downloading and installing
updates. Existing explicit Sparkle preferences SHALL remain effective.

#### Scenario: Default update-enabled build configuration

- **WHEN** an update-enabled build has no explicit Sparkle preference overrides
- **THEN** automatic checks are enabled with a default interval of one hour
- **AND** silent automatic downloading and installation are disabled by default so discovered releases use the standard update offer
