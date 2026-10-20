## ADDED Requirements

### Requirement: GigaAM participates in shared model readiness

GigaAM warmup, dictation, and Meeting requests SHALL share tracked loading by exact model/package identity and serialize native inference through the selected backend's shared service. Requester timeout or cancellation SHALL NOT abandon an uncooperative native load or start a duplicate. A late result for an old selection SHALL NOT publish readiness for the new selection. Inactive model resources SHALL be released after their last captured request finishes; model changes SHALL NOT release resources still in use.

#### Scenario: Warmup and both workflows request cold GigaAM

- **WHEN** GigaAM warmup, dictation, and Meeting processing overlap for the same unloaded model
- **THEN** they share one tracked native load, serialize inference, and preserve the existing separation between model-loading wait and dictation processing timeout

#### Scenario: Old warmup completes after a model change

- **WHEN** selection changes between GigaAM and Whisper while the previous selection is loading
- **THEN** each request keeps its captured model identity and the old completion cannot overwrite the selected model's readiness or current warmup tracking

#### Scenario: Cancel a GigaAM load waiter and retry

- **WHEN** a requester stops waiting for GigaAM initialization, or shared initialization fails
- **THEN** cancellation ends that wait promptly while an active native load remains tracked, and failure clears the failed load so a later request can retry

#### Scenario: Switch models while a request owns GigaAM

- **WHEN** a prepared GigaAM request is still active and the selected model changes
- **THEN** its context remains valid until that request finishes or cancels, and inactive GigaAM resources are released afterward rather than accumulating across switches
