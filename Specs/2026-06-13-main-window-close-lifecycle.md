---
id: SPEC-016
status: implemented
updated: 2026-06-13
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Main Window Close Lifecycle

## Problem

The main window can be closed with the standard title-bar close button while VoicePen is
actively recording or waiting for user workflow. The app should continue running in the
tray without being terminated, while presenting as an accessory in the Dock.

## Behavior

When the main window is closed, VoicePen keeps running and status bar workflows (dictation,
meeting recording, reminders, and existing menu commands) remain available from the tray.
The main window close should hide the Dock icon by restoring accessory activation policy.

When a user opens VoicePen from the tray or command path, the main window should become
available again and the Dock icon should reappear.

## Acceptance Criteria

- When the main window closes, `applicationShouldTerminateAfterLastWindowClosed(_:)` shall return `false`.
- When the user closes the main window with the standard close action, VoicePen shall keep the process alive and switch the app to `.accessory` activation policy.
- When the user opens VoicePen from tray or command entry points, VoicePen shall set activation policy to `.regular` before activating/opening the main window.
- Existing tray menu actions for `Open VoicePen Window`, `Check for Updates...`, and `Quit` shall continue to use their existing handlers.
- When `Quit` is selected from the tray, VoicePen shall still terminate.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Close while active | User clicks the main window close button | App continues recording/processing, status menu remains, Dock icon hides |
| Re-open from tray | User selects `Open VoicePen Window` in status menu | Dock icon returns, main window opens |
| Existing tray workflow | User selects `Quit` | App process exits |

## Test Mapping

- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` checks App delegate wiring, window open/close activation policy handling, close-lifecycle bridge, and tray Open/Quit command handlers.

## Notes

No changes are made to LSUIElement, dictation logic, meeting workflows, settings persistence, or tray command availability.

## Open Questions

- None.
