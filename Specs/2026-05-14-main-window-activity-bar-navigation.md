---
id: SPEC-014
status: active
updated: 2026-06-14
tests:
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Main Window Icon Sidebar Navigation

## Problem

VoicePen's main window sidebar should stay compact without rendering a custom
sidebar inside the native split-view sidebar. The app needs one left navigation
surface that keeps section switching obvious while preserving working space.

## Behavior

VoicePen shall navigate the main window with a native `NavigationSplitView`
sidebar in icon-only mode. The left sidebar keeps the existing section order,
Modes feature flag visibility, and meeting-aware Meetings icon behavior. Section
names remain available through accessibility labels and hover help, but they
are not rendered as persistent text in the left strip. The app
readiness/status text shall be readable on Home instead of represented by a
standalone sidebar icon. System permission controls belong in Settings and
shall not appear as a standalone sidebar icon.

Selecting an icon changes the detail content to that section. VoicePen opens
with Home selected by default. The strip shall preserve a visible selected
state and keep the existing persistent meeting recording panel behavior. The
sidebar shall not contain a second custom sidebar, rounded island, or nested
activity bar surface inside the native split-view column.

## Acceptance Criteria

- When the main window opens, VoicePen shall show one narrow native split-view sidebar with icon-only section controls.
- When Home is selected, VoicePen shall show the current app status as readable text.
- When the user selects a sidebar icon, VoicePen shall show the matching section detail.
- When the Modes feature flag is disabled, VoicePen shall omit the Modes icon from the sidebar.
- VoicePen shall not show an AI icon or AI settings section in the main window.
- When permission controls are available, VoicePen shall show them inside Settings instead of adding a separate Permissions sidebar icon.
- When Meeting recording or processing shows the persistent meeting panel, the Meetings icon shall use the current menu bar status icon.
- Sidebar icons shall expose section names to assistive technologies and hover help without rendering section names in the strip.
- Sidebar hover and selected-state feedback shall remain responsive while Home is selected; Home dashboard layout and chart preparation shall not require duplicate heavy dashboard trees during ordinary hover updates.
- The main window shall keep native close, minimize, zoom, dragging, fullscreen, accessibility, hover, active, and inactive window behavior.
- When the main window is focused, Command-1 shall navigate to Home, Command-2 shall navigate to Meetings, and Command-3 shall navigate to Sessions.
- The persistent meeting recording panel shall keep its current bottom placement below the main content.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Default open | User opens the main window | Home detail is selected, the current app status is readable on Home, and the left split-view sidebar uses icon-only section controls |
| Home hover responsiveness | User moves the pointer across the sidebar while Home is selected | Hover feedback appears immediately without waiting for Home dashboard chart or heatmap preparation |
| Single sidebar | User opens the main window | The left side shows one native icon-only sidebar, without a rounded custom sidebar nested inside it |
| Navigate to Sessions | User selects the Sessions clock icon | Sessions detail appears and the clock icon shows selected state |
| Navigate with shortcuts | User presses Command-1, Command-2, or Command-3 in the main window | VoicePen switches to Home, Meetings, or Sessions respectively |
| Removed AI feature | User opens the main window | AI icon is not shown in the sidebar |
| Permissions | User opens the main window | Permission controls are reachable from Settings without a separate Permissions icon |
| Meeting active | Meeting recording or processing is active | Meetings sidebar icon follows the app status icon |

## Test Mapping

- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` checks sidebar section grouping, readable Home status placement, primary-section keyboard shortcuts, Settings permission placement, feature flags, and meeting-aware icon routing.
- Manual: open the main window; verify the left split-view sidebar is narrow, shows only section icons, does not contain a nested rounded custom sidebar, exposes section names through hover help/accessibility, Home shows readable app status, sidebar icon hover responds immediately while Home is selected, switching icons changes detail sections, native window controls and dragging work, dark mode looks correct, and the meeting panel remains at the bottom while recording or processing.

## Notes

This is a presentation and navigation change only. It shall not change
settings persistence, history, dictionary editing, recording, transcription, or
meeting processing behavior.

## Open Questions

- None.
