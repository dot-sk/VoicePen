---
id: ADR-2026-06-16-appkit-window
status: accepted
date: 2026-06-16
---

# AppKit Main Window Ownership

## Context

VoicePen's glass sidebar requires native traffic lights to sit inside a floating island with custom inset positioning. SwiftUI's `Window` scene owns the underlying `NSWindow` and repeatedly relayouts the titlebar, resetting button positions and reintroducing unwanted title chrome. Notification-based repositioning was fragile and fought the framework on every resize.

## Decision

Replace the SwiftUI app entry scene with an AppKit-owned main window:

- Use `@main` `VoicePenAppDelegate` with `NSApplication.run()` instead of `struct VoicePenApp: App` and `Window(...)`.
- Own the main window through `MainWindowController` and a `GlassMainWindow` subclass that repositions native traffic lights using `MainWindowTrafficLightLayout`.
- Host existing SwiftUI UI through `NSHostingController(rootView: VoicePenMainWindow(...))`.
- Build the application menu in AppKit through `MainAppMenu`.

## Consequences

- Easier: reliable traffic-light positioning on every layout pass; no SwiftUI titlebar relayout fighting custom chrome; transparent header without navigation title artifacts.
- Harder: main menu and window lifecycle are maintained manually in AppKit; we no longer get SwiftUI `.commands` for free.
- Intentionally constrained: one primary AppKit window; future multi-window flows would need explicit AppKit window controllers.

## Links

- [SPEC-014 Main Window Icon Sidebar Navigation](../../Specs/2026-05-14-main-window-activity-bar-navigation.md)
- [SPEC-016 Main Window Close Lifecycle](../../Specs/2026-06-13-main-window-close-lifecycle.md)
- [ADR-2026-06-16 Custom Full-Height Glass Sidebar Layout](2026-06-16-main-window-glass-sidebar-layout.md)
- [GlassMainWindow.swift](../../VoicePen/App/GlassMainWindow.swift)
- [MainWindowController.swift](../../VoicePen/App/MainWindowController.swift)
