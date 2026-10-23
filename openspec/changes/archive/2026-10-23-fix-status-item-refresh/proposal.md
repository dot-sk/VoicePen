## Why

The menu bar icon can remain in its processing state after dictation finishes until the user opens the menu. State observation currently rebuilds the menu snapshot before the published property stores its new value.

## What Changes

- Refresh the status snapshot after published state changes have been stored.
- Cover automatic recovery to the current idle, warning, or meeting state without opening the menu or waiting for another state change.
- Preserve existing status icon selection and menu construction behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `push-to-talk-dictation-pipeline`: Clarify that automatic status refresh reflects the latest completed state transition, including return from processing.

## Impact

The AppKit status item observer and hosted regression tests. No public APIs, persistence, dependencies, or dictation pipeline changes.
