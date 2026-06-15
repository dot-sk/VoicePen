---
id: SPEC-016
status: implemented
updated: 2026-06-16
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
  - VoicePenTests/App/MainWindowTrafficLightLayoutTests.swift
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

When a user opens VoicePen from the tray, main menu, or Dock reopen path, the main window should become
available again and the Dock icon should reappear.

The main window is owned by `MainWindowController` as an AppKit `GlassMainWindow` with SwiftUI content hosted through `NSHostingController`. Closing the window switches activation policy in `NSWindowDelegate.windowWillClose`.

## Acceptance Criteria

- When the main window closes, `applicationShouldTerminateAfterLastWindowClosed(_:)` shall return `false`.
- When the user closes the main window with the standard close action, VoicePen shall keep the process alive and switch the app to `.accessory` activation policy.
- When the user opens VoicePen from tray, main menu, or Dock reopen entry points, VoicePen shall set activation policy to `.regular` before activating/opening the main window.
- When the user clicks the Dock icon while no windows are visible, VoicePen shall reopen the main window through `applicationShouldHandleReopen(_:hasVisibleWindows:)`.
- VoicePen shall create its AppKit `NSStatusItem` only after AppKit reports application launch completion, so status menu startup does not depend on pre-launch WindowServer connection timing.
- Existing tray menu actions for `Open VoicePen Window`, `Check for Updates...`, and `Quit` shall continue to use their existing handlers.
- When `Quit` is selected from the tray, VoicePen shall still terminate.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Close while active | User clicks the main window close button | App continues recording/processing, status menu remains, Dock icon hides |
| Re-open from tray | User selects `Open VoicePen Window` in status menu | Dock icon returns, main window opens |
| Re-open from Dock | User clicks the Dock icon while the main window is closed | Main window opens and Dock icon stays visible |
| Existing tray workflow | User selects `Quit` | App process exits |

## Test Mapping

- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` checks tray Open/Quit command handlers.
- Automated: `VoicePenTests/App/MainWindowTrafficLightLayoutTests.swift` checks traffic-light inset layout math used by the AppKit main window.
- Manual: launch the packaged app and verify the status item appears after launch without crashing before the main window opens; verify close hides the Dock icon, tray reopen restores it, and Dock reopen opens the main window.

## Notes

No changes are made to LSUIElement, dictation logic, meeting workflows, settings persistence, or tray command availability.

## Open Questions

- None.
