## Why

The confirmed dictation corpus shows worse recognition and latency with RNNoise. Existing stage timings omit recording finalization and model readiness, so they do not explain the delay users experience after releasing push-to-talk.

## What Changes

- Default dictation RNNoise to off when no saved choice exists; preserve explicit choices and the manual toggle.
- Measure release-to-insertion completion with a monotonic clock, including recording finalization, readiness, and scheduling waits.
- Store total latency and the missing stage timings locally and show them in session details. Older history remains readable without invented measurements.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `audio-settings-voice-processing`: opt-in dictation background noise suppression.
- `push-to-talk-dictation-pipeline`: optional RNNoise and complete successful dictation latency.
- `history-settings-persistence`: default and persisted choice compatibility; saved latency metadata.

## Impact

Settings defaults, app dictation orchestration, pipeline timing, history metadata presentation, and behavioral tests. No model, audio filter, punctuation, dependency, or database schema change.
