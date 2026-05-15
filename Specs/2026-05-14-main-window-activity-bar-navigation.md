---
id: SPEC-014
status: active
updated: 2026-05-15
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Main Window Activity Bar Navigation

## Problem

VoicePen's main window sidebar uses a wide labeled list for navigation. This
takes space from the working area and makes the app feel heavier than needed
for a compact macOS utility.

## Behavior

VoicePen shall navigate the main window with a VS Code style activity bar: a
narrow fixed strip on the left that shows only icons for available sections.
The activity bar keeps the existing section order, feature flag visibility, and
meeting-aware Meetings icon behavior. Section names remain available through
accessibility labels and hover help, but they are not rendered as persistent
text in the left strip. The app readiness/status text shall be readable on Home
instead of represented by a standalone activity bar icon. System permission
controls belong in Settings and shall not appear as a standalone activity bar
icon.

Selecting an icon changes the detail content to that section. VoicePen opens
with Home selected by default. The strip shall preserve a visible selected
state and keep the existing persistent meeting recording panel behavior.

## Acceptance Criteria

- When the main window opens, VoicePen shall show a narrow left navigation strip with icon-only section controls.
- When Home is selected, VoicePen shall show the current app status as readable text.
- When the user selects an activity bar icon, VoicePen shall show the matching section detail.
- When Modes or AI feature flags are disabled, VoicePen shall omit those icons from the activity bar.
- When permission controls are available, VoicePen shall show them inside Settings instead of adding a separate Permissions activity bar icon.
- When Meeting recording or processing shows the persistent meeting panel, the Meetings icon shall use the current menu bar status icon.
- Activity bar icons shall expose section names to assistive technologies and hover help without rendering section names in the strip.
- When the main window is focused, Command-1 shall navigate to Home, Command-2 shall navigate to Meetings, and Command-3 shall navigate to Sessions.
- The persistent meeting recording panel shall keep its current bottom placement below the main content.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Default open | User opens the main window | Home detail is selected, the current app status is readable on Home, and the left navigation uses icon-only section controls |
| Navigate to Sessions | User selects the Sessions clock icon | Sessions detail appears and the clock icon shows selected state |
| Navigate with shortcuts | User presses Command-1, Command-2, or Command-3 in the main window | VoicePen switches to Home, Meetings, or Sessions respectively |
| Hidden AI feature | AI feature flag is disabled | AI icon is not shown in the activity bar |
| Permissions | User opens the main window | Permission controls are reachable from Settings without a separate Permissions icon |
| Meeting active | Meeting recording or processing is active | Meetings activity icon follows the app status icon |

## Test Mapping

- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` checks activity bar grouping, readable Home status placement, primary-section keyboard shortcuts, Settings permission placement, feature flags, and meeting-aware icon routing.
- Manual: open the main window; verify the left strip is narrow, shows only section icons, exposes section names through hover help/accessibility, Home shows readable app status, switching icons changes detail sections, and the meeting panel remains at the bottom while recording or processing.

## Notes

This is a presentation and navigation change only. It shall not change
settings persistence, history, dictionary editing, recording, transcription, or
meeting processing behavior.

## Open Questions

- None.
