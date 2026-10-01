## Context

See `proposal.md` for motivation and `specs/audio-input-selection/spec.md` for behavior.

The current Core Audio provider exposes only the macOS default input device and observes only default-device changes. Both AUHAL capture paths resolve that default during `prepare()`. Dictation input gain also targets the default device independently. Settings are stored in a SQLite key-value table and flow through `AppSettingsStore` and `AppController`.

Dictation keeps an idle AUHAL capture prepared to reduce startup latency. Meeting microphone capture prepares when a meeting starts. Neither path may change output volume, mute, routing, or the macOS default input device.

## Goals / Non-Goals

**Goals:**

- Give settings and both capture paths one source of truth for the selected input.
- Keep device discovery and capture routing testable without live Core Audio hardware.
- Preserve idle dictation preparation and the current AUHAL lifecycle.
- Keep existing installations on system-default behavior until the user selects a device.

**Non-Goals:**

- Selecting separate microphones for dictation and Meeting Mode.
- Selecting input channels within a multi-channel device.
- Changing the macOS default input device.
- Changing Meeting system-audio app selection or output routing.
- Adding a new settings section, dependency, or ADR.

## Decisions

### Represent the selection separately from a runtime device

Model the setting as either `systemDefault` or a device UID with its last known display name. Core Audio UIDs remain stable across launches, while `AudioDeviceID` values are valid only for the current hardware session.

At capture preparation time, resolve the selection to a current `AudioDeviceID`. A saved device UID that cannot be resolved is unavailable, not malformed. A malformed stored value resets to `systemDefault`.

Alternative considered: persist `AudioDeviceID`. Rejected because macOS can assign a different numeric ID after a restart or reconnect.

### Extend the Core Audio boundary to discover and observe input devices

Replace the default-only boundary with an input-device provider that can:

- return the current default device;
- list devices that expose at least one input channel;
- resolve a stable UID to the current runtime device;
- observe device-list, default-device, and device-name changes.

The provider rebuilds per-device name listeners when the device list changes. It publishes immutable snapshots to the main actor. Core Audio calls and listener registration stay behind injectable boundaries so tests do not depend on local hardware.

Alternative considered: refresh only when Settings opens or the app activates. Rejected because the spec requires the list and availability state to change while VoicePen is running.

### Use a small thread-safe selection coordinator

A shared coordinator holds the active selection and resolves it through the provider for background capture and gain work. `AppSettingsStore` remains the persistence owner, and `AppController` remains the SwiftUI-facing facade. The controller loads the saved selection into the coordinator, publishes picker options and availability, and writes picker changes back through the settings store immediately.

This avoids reading a `@MainActor` settings object from Core Audio worker queues. It also prevents separate dictation, Meeting, and gain components from resolving different devices.

Alternative considered: rebuild the complete recording and Meeting pipelines after every setting change. Rejected because those long-lived objects own unrelated state and callbacks.

### Resolve the device when capture is prepared

`CoreAudioMicrophoneCapture.prepare()` asks the coordinator for one device and binds the AUHAL unit to that `AudioDeviceID`. The unit keeps that device until teardown. Changing the selection invalidates idle dictation preparation and schedules a new prepare. It does not rebind a running dictation or Meeting capture.

Meeting capture uses the same coordinator when its microphone source prepares. The next capture therefore observes the latest selection without duplicating settings logic.

Alternative considered: switch an active AUHAL unit to the newly selected device. Rejected because a mid-recording format or channel-count change can break timeline continuity and file conversion.

### Do not silently fall back for an unavailable manual selection

If `systemDefault` is selected, failure to resolve the current default keeps the existing missing-input behavior. If a specific saved UID is unavailable, the picker includes a synthetic unavailable row using the last known name. New microphone capture fails with an error that tells the user to reconnect the device or choose another input.

The coordinator automatically resolves the saved UID again when the device returns. The setting does not change.

Alternative considered: capture from the system default while the selected device is missing. Rejected because it can record from an unintended microphone without the user's knowledge.

### Route dictation gain through the same resolved device

Generalize the input-gain implementation so it receives the device chosen for the dictation capture rather than querying the system default itself. Keep the existing best-effort gain rules and device-specific restore token. Meeting Mode still does not boost microphone gain.

Alternative considered: leave gain on the system default. Rejected because capture and gain could affect different devices.

## Risks / Trade-offs

- [Core Audio emits several related notifications for one hardware change] → Coalesce refreshes on the provider queue and publish only changed snapshots.
- [A device disappears after resolution but before AUHAL initialization] → Return the existing capture-start error path and leave the saved selection unchanged.
- [Duplicate device names make the picker ambiguous] → Keep UID as identity and add a short disambiguating detail only when display names collide.
- [Changing the selection while dictation is idle races with prepared capture work] → Serialize invalidation and preparation through the existing recording preparation path.
- [A prior app version does not understand the new setting] → Store the selection in additive key-value entries; rollback ignores them and continues with system default.

## Migration Plan

1. Add the new setting with `systemDefault` as the missing or invalid value fallback. No database schema migration is required.
2. Complete the `audio-input-selection` delta requirements, scenarios, and
   automated test tasks before production code.
3. Introduce device discovery and selection resolution behind tests.
4. Wire settings, dictation capture, Meeting capture, and dictation gain to the shared coordinator.
5. Run focused tests, `make test`, and an app build.

Rollback removes the picker and selection routing. Stored key-value entries may remain because older code ignores them.
