---
id: ADR-2026-06-16
status: accepted
date: 2026-06-16
---

# Custom Full-Height Glass Sidebar Layout

## Context

VoicePen's main window needs a ChatGPT-style sidebar: a full-height glass panel that starts at the top edge of the window, extends under the native traffic lights, and keeps icon-only navigation below the titlebar chrome. `NavigationSplitView` owns its sidebar column background, titlebar integration, and collapse behavior. That makes it hard to draw a dedicated glass layer from y=0 while keeping native traffic lights visible and clickable without fake controls or private API.

## Decision

Replace `NavigationSplitView` in the main window with a custom `HStack` layout inside a `fullSizeContentView` window:

- Configure the window with transparent titlebar, hidden title, and `isMovableByWindowBackground`.
- Render a fixed-width sidebar column with `NSVisualEffectView` material, theme tint, and a separate content stack inset below traffic lights.
- Keep section navigation logic in testable Core types (`MainWindowSidebarSectionGroups`, `MainWindowSidebarNavigation`).
- Leave detail content in plain SwiftUI layout on the right inside an AppKit-hosted main window.
- Own the main window through `GlassMainWindow` (`NSWindow` subclass) and `MainWindowController` instead of a SwiftUI `Window` scene.

We accept losing native split-view sidebar collapse and built-in split chrome in exchange for full control of the glass panel and titlebar overlap behavior.

## Consequences

- Easier: full-height glass sidebar, traffic-light overlap styling, version-specific sidebar metrics, predictable hit testing for background vs icons.
- Harder: future split-view features (column collapse, native sidebar drag-to-resize) must be rebuilt manually if needed.
- Intentionally constrained: main window uses one fixed sidebar width (~72pt) and icon-only navigation; widening to a labeled/search sidebar would be a separate product change.

## Links

- [SPEC-014 Main Window Icon Sidebar Navigation](../../Specs/2026-05-14-main-window-activity-bar-navigation.md)
- [VoicePenMainWindow.swift](../../VoicePen/App/VoicePenMainWindow.swift)
- [MainWindowSidebarNavigation.swift](../../VoicePen/Core/MainWindowSidebarNavigation.swift)
- [MainWindowTrafficLightLayout.swift](../../VoicePen/Core/MainWindowTrafficLightLayout.swift)
- [GlassMainWindow.swift](../../VoicePen/App/GlassMainWindow.swift)
- [MainWindowController.swift](../../VoicePen/App/MainWindowController.swift)
- [ADR-2026-06-16 AppKit Main Window Ownership](2026-06-16-appkit-main-window-ownership.md)
