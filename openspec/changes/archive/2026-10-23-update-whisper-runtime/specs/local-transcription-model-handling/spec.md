## ADDED Requirements

### Requirement: Bundled Whisper runtime upgrades preserve installed transcription features

VoicePen SHALL reuse valid installed supported Whisper weights and completion state across a bundled runtime upgrade. Transcription SHALL preserve Metal encoder and decoder execution, optional timestamps, and usable word confidence evidence. Execution diagnostics SHALL identify the bundled runtime version.

#### Scenario: Existing quantized model is used after a runtime upgrade

- **WHEN** a user with valid installed supported Q5 or Q8 Whisper weights transcribes after a bundled runtime upgrade, including an installation with legacy Core ML companions
- **THEN** VoicePen uses those weights with Metal encoder and decoder, returns transcription and confidence evidence, and reports the updated runtime identity without requiring another download

#### Scenario: Timestamped transcription uses the upgraded runtime

- **WHEN** a transcription request asks for timestamps using the upgraded bundled Whisper runtime
- **THEN** VoicePen returns timestamped segments and word confidence evidence from that runtime

#### Scenario: Other local ASR backend remains available

- **WHEN** Whisper and GigaAM are loaded in the same process after a Whisper runtime upgrade
- **THEN** both backends can transcribe with their own packaged runtime and confidence evidence
