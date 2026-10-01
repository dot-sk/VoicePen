# Main Window Icon Sidebar Navigation Specification

## Purpose

VoicePen's main window sidebar should stay compact without rendering a custom sidebar inside the native split-view sidebar. The app needs one left navigation surface that keeps section switching obvious while preserving working space. The sidebar should read as a floating glass island under the native traffic lights, similar to the new ChatGPT desktop app, without fake window controls or a separate empty titlebar strip.

## Requirements

### Requirement: Main Window Icon Sidebar Navigation

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen shall navigate the main window with a custom floating glass sidebar island and icon-only section controls. The left sidebar keeps the existing section order, Modes feature flag visibility, and meeting-aware Meetings icon behavior. Section names remain available through accessibility labels and hover help, but they are not rendered as persistent text in the left strip. The app readiness/status text shall be readable on Home instead of represented by a standalone sidebar icon. System permission controls belong in Settings and shall not appear as a standalone sidebar icon.

The main window shall use native full-size content chrome owned by AppKit: transparent titlebar, hidden title, and native traffic lights repositioned into the sidebar glass island by `GlassMainWindow`. Sidebar icon content shall start below the traffic-light zone. The sidebar island shall float with inset margins from the top, leading, and bottom window edges, use rounded corners on all sides, and leave a gap before the main detail content.

Selecting an icon changes the detail content to that section. VoicePen opens with Home selected by default. The strip shall preserve a visible selected state and keep the existing persistent meeting recording panel behavior. The sidebar shall not contain a second nested sidebar or duplicate activity bar surface inside the glass island.

#### Scenario: Main window opens

- **WHEN** the main window opens
- **THEN** VoicePen shall show one fixed-width floating glass sidebar island with icon-only section controls.

#### Scenario: Sidebar island

- **WHEN** this capability applies
- **THEN** The sidebar island shall float with inset margins from the top, leading, and bottom window edges and use rounded corners on all sides.

#### Scenario: Native traffic lights

- **WHEN** this capability applies
- **THEN** Native traffic lights shall remain visible, clickable, and visually inside the sidebar glass island after AppKit layout repositioning.

#### Scenario: Sidebar icon content

- **WHEN** this capability applies
- **THEN** Sidebar icon content shall start below the traffic-light zone and shall not overlap native traffic lights.

#### Scenario: Shall not render fake traffic lights, traffic-light cutouts, or a separate empty titlebar strip

- **WHEN** this capability applies
- **THEN** VoicePen shall not render fake traffic lights, traffic-light cutouts, or a separate empty titlebar strip above the sidebar.

#### Scenario: Home is selected

- **WHEN** Home is selected
- **THEN** VoicePen shall show the current app status as readable text.

#### Scenario: User selects a sidebar icon

- **WHEN** the user selects a sidebar icon
- **THEN** VoicePen shall show the matching section detail.

#### Scenario: Modes feature flag is disabled

- **WHEN** the Modes feature flag is disabled
- **THEN** VoicePen shall omit the Modes icon from the sidebar.

#### Scenario: Shall not show an AI icon or AI settings section in the main window

- **WHEN** this capability applies
- **THEN** VoicePen shall not show an AI icon or AI settings section in the main window.

#### Scenario: Permission controls are available

- **WHEN** permission controls are available
- **THEN** VoicePen shall show them inside Settings instead of adding a separate Permissions sidebar icon.

#### Scenario: Meeting recording or processing shows the persistent meeting panel

- **WHEN** Meeting recording or processing shows the persistent meeting panel
- **THEN** the Meetings icon shall use the current menu bar status icon.

#### Scenario: Sidebar icons

- **WHEN** this capability applies
- **THEN** Sidebar icons shall expose section names to assistive technologies and hover help without rendering section names in the strip.

#### Scenario: Sidebar hover and selected-state feedback

- **WHEN** this capability applies
- **THEN** Sidebar hover and selected-state feedback shall remain responsive while Home is selected; Home dashboard layout and chart preparation shall not require duplicate heavy dashboard trees during ordinary hover updates.

#### Scenario: Main window

- **WHEN** this capability applies
- **THEN** The main window shall keep native close, minimize, zoom, dragging, fullscreen, accessibility, hover, active, and inactive window behavior.

#### Scenario: Main window is focused

- **WHEN** the main window is focused
- **THEN** Command-1 shall navigate to Home, Command-2 shall navigate to Meetings, and Command-3 shall navigate to Sessions.

#### Scenario: Persistent meeting recording panel

- **WHEN** this capability applies
- **THEN** The persistent meeting recording panel shall keep its current bottom placement below the main content.
