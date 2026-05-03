---
id: ADR-0002
status: accepted
date: 2026-05-03
---

# Separated Development App Identity

## Context

VoicePen needs macOS privacy permissions such as Microphone and Accessibility.
During development, running locally built apps with the production bundle
identifier can cause the development build and installed production app to share
or invalidate TCC permission records and local Application Support data.

## Decision

Use separate build-time identity values for Debug and Release builds.

Debug builds use a development bundle identifier, display name, and Application
Support folder. Release builds keep the production bundle identifier, display
name, and Application Support folder expected by Sparkle updates and installed
users.

Keep the product bundle filename stable so existing build, package, and run
tooling can continue to locate `VoicePen.app`.

## Consequences

macOS treats local development runs and production installs as separate apps for
privacy permissions. Development data and downloaded models no longer share the
production Application Support directory.

The development build asks for permissions once under its own identity. Release
builds keep the existing production identity and can continue to preserve
permissions across updater installs when signed consistently.

## Links

- [SPEC-006 GitHub Release Auto Updates](../../Specs/2026-05-02-github-release-auto-updates.md)
- `Config/VoicePen-Info.plist`
- `VoicePen.xcodeproj/project.pbxproj`
