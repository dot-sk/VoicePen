## ADDED Requirements

### Requirement: Language selection can choose a compatible recognizer

VoicePen SHALL keep the global language selector available in Settings and the tray regardless of the selected backend. The selector SHALL show the user's selected language independently of the native decoder's effective language. This supersedes model-specific fixed-language control restrictions; native Nemotron remains English-only and GigaAM remains automatic CTC.

When a language is selected, VoicePen SHALL first restore the last-used compatible model remembered for that particular language, even when the current model supports it too. This SHALL apply equally to English and Russian. A remembered model whose files are missing SHALL remain selected with normal missing-model readiness. If no valid remembered model exists, VoicePen SHALL keep a compatible current model, then prefer the installed recommended model, the first installed compatible model, and finally a compatible recommended or first available model. It SHALL NOT download models automatically. System language SHALL resolve to the current locale for compatibility; Auto-detect SHALL require a multilingual model. Explicit selection of an incompatible model SHALL choose its supported language while remembering the outgoing language/model pair. Other decoding preferences SHALL remain unchanged.

#### Scenario: Return to Russian from Nemotron

- **WHEN** the user previously selected an installed model for Russian, selects Nemotron, then chooses Russian from either shared language control
- **THEN** VoicePen restores the remembered Russian model and persists Russian as the selected language

#### Scenario: Restore English even when the Russian model supports English

- **WHEN** English was last used with Nemotron and Russian was last used with GigaAM, and the user switches from Russian to English and back
- **THEN** VoicePen restores Nemotron for English and GigaAM for Russian instead of retaining a multilingual model for both

#### Scenario: No model remembered for the language

- **WHEN** the user selects a language without a valid remembered model and the current model supports it
- **THEN** VoicePen keeps that model, persists the language choice and retains backend-specific effective decoding behavior

#### Scenario: Remembered model cannot be used

- **WHEN** the remembered model is absent from the model catalog or no longer supports the selected language
- **THEN** VoicePen follows the compatible fallback order without starting a download, and reports missing-model readiness if no compatible model is installed

#### Scenario: Last-used model files are missing

- **WHEN** the remembered compatible model is still available in the catalog but its files are not installed
- **THEN** VoicePen restores that model and shows missing-model readiness without downloading it or substituting another installed model

#### Scenario: System language or auto is selected

- **WHEN** System language or Auto-detect is selected with an incompatible model active
- **THEN** VoicePen selects a model supporting the resolved locale language or multilingual recognition respectively while retaining the chosen language option

#### Scenario: Selection changes during dictation

- **WHEN** a language or model change is requested during active dictation
- **THEN** the selection remains unchanged and the active request keeps its captured model and language

#### Scenario: Incompatible model is chosen explicitly

- **WHEN** the user selects an English-only model while Russian or Auto-detect is selected
- **THEN** VoicePen selects English, retains the outgoing Russian or Auto-detect model preference and leaves decoding profile preferences intact
