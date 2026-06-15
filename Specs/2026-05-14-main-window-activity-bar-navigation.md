---
id: SPEC-014
status: implemented
updated: 2026-06-16
tests:
  - VoicePenTests/App/MainWindowSidebarNavigationTests.swift
  - VoicePenTests/App/MainWindowTrafficLightLayoutTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Main Window Icon Sidebar Navigation

## Problem

VoicePen's main window sidebar should stay compact without rendering a custom sidebar inside the native split-view sidebar. The app needs one left navigation surface that keeps section switching obvious while preserving working space. The sidebar should read as a floating glass island under the native traffic lights, similar to the new ChatGPT desktop app, without fake window controls or a separate empty titlebar strip.

## Behavior

VoicePen shall navigate the main window with a custom floating glass sidebar island and icon-only section controls. The left sidebar keeps the existing section order, Modes feature flag visibility, and meeting-aware Meetings icon behavior. Section names remain available through accessibility labels and hover help, but they are not rendered as persistent text in the left strip. The app readiness/status text shall be readable on Home instead of represented by a standalone sidebar icon. System permission controls belong in Settings and shall not appear as a standalone sidebar icon.

The main window shall use native full-size content chrome owned by AppKit: transparent titlebar, hidden title, and native traffic lights repositioned into the sidebar glass island by `GlassMainWindow`. Sidebar icon content shall start below the traffic-light zone. The sidebar island shall float with inset margins from the top, leading, and bottom window edges, use rounded corners on all sides, and leave a gap before the main detail content.

Selecting an icon changes the detail content to that section. VoicePen opens with Home selected by default. The strip shall preserve a visible selected state and keep the existing persistent meeting recording panel behavior. The sidebar shall not contain a second nested sidebar or duplicate activity bar surface inside the glass island.

## Acceptance Criteria

- When the main window opens, VoicePen shall show one fixed-width floating glass sidebar island with icon-only section controls.
- The sidebar island shall float with inset margins from the top, leading, and bottom window edges and use rounded corners on all sides.
- Native traffic lights shall remain visible, clickable, and visually inside the sidebar glass island after AppKit layout repositioning.
- Sidebar icon content shall start below the traffic-light zone and shall not overlap native traffic lights.
- VoicePen shall not render fake traffic lights, traffic-light cutouts, or a separate empty titlebar strip above the sidebar.
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
| Default open | User opens the main window | Home detail is selected, the current app status is readable on Home, and the left floating glass sidebar uses icon-only section controls |
| Floating island | User opens the main window | Sidebar island has inset margins from the window edges, rounded corners, and native traffic lights appear inside the island chrome |
| Home hover responsiveness | User moves the pointer across the sidebar while Home is selected | Hover feedback appears immediately without waiting for Home dashboard chart or heatmap preparation |
| Single sidebar | User opens the main window | The left side shows one floating glass sidebar island, without a nested duplicate sidebar inside it |
| Navigate to Sessions | User selects the Sessions clock icon | Sessions detail appears and the clock icon shows selected state |
| Navigate with shortcuts | User presses Command-1, Command-2, or Command-3 in the main window | VoicePen switches to Home, Meetings, or Sessions respectively |
| Removed AI feature | User opens the main window | AI icon is not shown in the sidebar |
| Permissions | User opens the main window | Permission controls are reachable from Settings without a separate Permissions icon |
| Meeting active | Meeting recording or processing is active | Meetings sidebar icon follows the app status icon |

## Test Mapping

- Automated: `VoicePenTests/App/MainWindowSidebarNavigationTests.swift` checks sidebar section grouping, meeting-aware icon routing, and primary-section keyboard shortcut mapping.
- Automated: `VoicePenTests/App/MainWindowTrafficLightLayoutTests.swift` checks traffic-light inset layout math.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` checks status menu command placement.
- Manual: open the main window; verify the left floating glass sidebar island is narrow, shows only section icons, has inset margins and rounded corners, keeps native traffic lights visible and clickable inside the island chrome, does not contain a nested duplicate sidebar, exposes section names through hover help/accessibility, Home shows readable app status, sidebar icon hover responds immediately while Home is selected, switching icons changes detail sections, native window controls and dragging work, dark mode looks correct, and the meeting panel remains at the bottom while recording or processing.

## Notes

This is a presentation and navigation change only. It shall not change settings persistence, history, dictionary editing, recording, transcription, or meeting processing behavior.

## Open Questions

- None.
