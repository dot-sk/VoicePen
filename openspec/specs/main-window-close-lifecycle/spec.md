# Main Window Close Lifecycle Specification

## Purpose

The main window can be closed with the standard title-bar close button while VoicePen is
actively recording or waiting for user workflow. The app should continue running in the
tray without being terminated, while presenting as an accessory in the Dock.

## Requirements

### Requirement: Main Window Close Lifecycle

VoicePen SHALL preserve the behavior contract for this capability.

When the main window is closed, VoicePen keeps running and status bar workflows (dictation,
meeting recording, reminders, and existing menu commands) remain available from the tray.
The main window close should hide the Dock icon by restoring accessory activation policy.

When a user opens VoicePen from the tray, main menu, or Dock reopen path, the main window should become
available again and the Dock icon should reappear.

The main window is owned by `MainWindowController` as an AppKit `GlassMainWindow` with SwiftUI content hosted through `NSHostingController`. Closing the window switches activation policy in `NSWindowDelegate.windowWillClose`.

#### Scenario: Main window closes

- **WHEN** the main window closes
- **THEN** `applicationShouldTerminateAfterLastWindowClosed(_:)` shall return `false`.

#### Scenario: User closes the main window with the standard close action

- **WHEN** the user closes the main window with the standard close action
- **THEN** VoicePen shall keep the process alive and switch the app to `.accessory` activation policy.

#### Scenario: User opens VoicePen from tray, main menu, or Dock reopen entry points

- **WHEN** the user opens VoicePen from tray, main menu, or Dock reopen entry points
- **THEN** VoicePen shall set activation policy to `.regular` before activating/opening the main window.

#### Scenario: User clicks the Dock icon while no windows are visible

- **WHEN** the user clicks the Dock icon while no windows are visible
- **THEN** VoicePen shall reopen the main window through `applicationShouldHandleReopen(_:hasVisibleWindows:)`.

#### Scenario: Shall create its AppKit NSStatusItem only after AppKit reports application launch completion, so status

- **WHEN** this capability applies
- **THEN** VoicePen shall create its AppKit `NSStatusItem` only after AppKit reports application launch completion, so status menu startup does not depend on pre-launch WindowServer connection timing.

#### Scenario: Existing tray menu actions for Open VoicePen Window, Check for Updates..., and Quit

- **WHEN** this capability applies
- **THEN** Existing tray menu actions for `Open VoicePen Window`, `Check for Updates...`, and `Quit` shall continue to use their existing handlers.

#### Scenario: Quit is selected from the tray

- **WHEN** `Quit` is selected from the tray
- **THEN** VoicePen shall still terminate.
