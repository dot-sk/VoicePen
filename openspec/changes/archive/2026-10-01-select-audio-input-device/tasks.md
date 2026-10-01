## 1. Update behavior contracts

- [x] 1.1 Capture system-default selection, stable device persistence, invalid-value fallback, and automated settings coverage in the `audio-input-selection` delta spec and tasks.
- [x] 1.2 Capture the picker, shared Dictation and Meeting routing, unavailable-device behavior, selected-device gain handling, and automated coverage in the `audio-input-selection` delta spec and tasks.

## 2. Add selection persistence and device models

- [x] 2.1 Add a sendable audio input selection model for `systemDefault` and a stable device UID with last known name.
- [x] 2.2 Extend `AppSettingsStore` to load, normalize, publish, and persist the input selection through the existing SQLite key-value path.
- [x] 2.3 Add `AppSettingsStoreTests` coverage for missing, valid, unavailable, and malformed saved selections.

## 3. Discover and resolve Core Audio inputs

- [x] 3.1 Generalize the default-input provider into an injectable Core Audio input-device boundary that lists input-capable devices, reads UID and name, resolves UID to the current runtime device, and identifies the system default.
- [x] 3.2 Observe device-list, default-device, and device-name changes, rebuild per-device listeners after topology changes, and publish only changed snapshots.
- [x] 3.3 Add provider tests for input filtering, stable resolution, default resolution, duplicate-name identity, snapshot updates, and listener cleanup.
- [x] 3.4 Add a thread-safe selection coordinator that resolves one active device for capture and gain work and preserves an unavailable saved selection without default fallback.
- [x] 3.5 Add coordinator tests for system-default changes, manual selection, disconnect, reconnect, and malformed selection fallback.

## 4. Route recording and gain

- [x] 4.1 Update `CoreAudioMicrophoneCapture` to bind AUHAL to the device resolved by the selection coordinator during `prepare()` and return a distinct unavailable-selection error.
- [x] 4.2 Extend `CoreAudioMicrophoneCaptureTests` to prove manual-device routing, system-default routing, unavailable-device failure, and no mid-capture rebinding.
- [x] 4.3 Wire the same coordinator into live Dictation and Meeting microphone capture while preserving the current input-only AUHAL lifecycle and Meeting output-routing constraints.
- [x] 4.4 Generalize dictation input-gain handling to boost and restore the device selected for capture, then extend gain tests for selected-device and unsupported-gain cases.

## 5. Wire settings and app lifecycle

- [x] 5.1 Publish microphone options, the active selection, and availability through `AppController`, and persist updates through the shared settings store.
- [x] 5.2 Invalidate and rebuild idle Dictation preparation after a selection or relevant device snapshot change without switching an active Dictation or Meeting recording.
- [x] 5.3 Map unavailable manual selections to actionable Dictation and Meeting start errors while leaving the saved selection intact.
- [x] 5.4 Replace the read-only microphone status in the existing Audio settings section with a picker, including an unavailable saved-device row and duplicate-name disambiguation.
- [x] 5.5 Update app and settings tests for picker bindings, live snapshot changes, idle preparation invalidation, active-recording stability, and shared Dictation and Meeting wiring.

## 6. Verify

- [x] 6.1 Run `openspec validate select-audio-input-device --strict`, `make validate-specs`, and `make format-check`.
- [x] 6.2 Run `make test`.
- [x] 6.3 Run `make build` to verify the macOS app target.
- [x] 6.4 Manually confirm the Settings picker and one Dictation plus Meeting capture with `System default`, a selected microphone, disconnect, and reconnect.

## Verification notes

- Manual verification task 6.4 marked complete based on Sergey's confirmation on 2026-10-01.
