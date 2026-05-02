---
id: SPEC-006
status: implemented
updated: 2026-05-02
tests:
  - VoicePenTests/Updates/SoftwareUpdateConfigurationTests.swift
  - VoicePenTests/Updates/AppcastGenerationTests.swift
---

# GitHub Release Auto Updates

## Problem

VoicePen release builds are currently distributed as downloadable GitHub Release
archives. Users who already installed the app must manually download and replace
the application for each update, which makes Friends & Family updates slow and
error-prone.

## Behavior

VoicePen shall provide a macOS app update flow backed by GitHub Releases. A user
running an update-enabled build can choose to check for updates from the app UI,
review the available release, and approve installation without manually
downloading or replacing `VoicePen.app`.

VoicePen shall also enable Sparkle's automatic update checks and automatic update
download preparation so update-enabled builds can discover and stage updates
without requiring the user to manually fetch a release archive.

The update channel starts with the first build that includes the updater. Builds
installed before that version must be manually replaced once with the transition
build.

Release publishing shall produce the downloadable app archive and publish the
update feed to the repository's GitHub Pages site at a stable HTTPS URL. The app
shall only offer updates whose archive is authenticated by the configured
update-signing material.

## Acceptance Criteria

- When a user opens the VoicePen menu or app commands in an update-enabled build,
  VoicePen shall expose a check-for-updates action.
- When an update-enabled build is running, VoicePen shall allow Sparkle to check
  for updates automatically and prepare eligible updates in the background.
- When a newer GitHub Release is available in the configured feed, VoicePen shall
  present a standard macOS update prompt with release information and an install
  action.
- When the user approves installation, VoicePen shall download the release
  archive, replace the installed app bundle, and relaunch or prompt for relaunch
  using the updater's standard flow.
- When no newer release is available, VoicePen shall report that the installed
  build is current.
- When release publishing runs for a tagged release, it shall publish or update
  the GitHub Pages appcast/feed metadata that points to the GitHub Release
  archive.
- When release publishing builds a tagged release, it shall avoid a standalone
  package-resolution step because the test and package builds already resolve
  Swift packages as needed.
- When release publishing packages an app archive, the app bundle shall not
  contain a corrupted or stale code signature that prevents Sparkle validation.
- When release publishing packages app archives across versions, it shall sign
  the app bundle with a stable macOS code signing identity so macOS privacy
  permissions can remain associated with VoicePen across updater installs.
- When an archive is missing a valid updater signature, VoicePen shall not offer
  it as an installable update.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Manual check finds update | Installed build `1.0`, feed contains `1.1` | VoicePen shows the updater prompt for `1.1`. |
| Manual check is current | Installed build matches newest feed item | VoicePen reports that VoicePen is up to date. |
| First updater rollout | User has a pre-updater build installed | User manually installs the transition build once; later updates use the updater. |
| Invalid release archive | Feed item lacks a valid update signature | VoicePen refuses to install that update. |

## Test Mapping

- Automated: `VoicePenTests/Updates/SoftwareUpdateConfigurationTests.swift`
  verifies the app target uses an explicit `Config/VoicePen-Info.plist` that
  contains a stable update feed URL, an updater public key, automatic Sparkle update
  checks/download preparation, Sparkle package wiring, and a check-for-updates
  command/menu entry wired to the updater.
- Automated: `VoicePenTests/Updates/AppcastGenerationTests.swift` verifies
  release feed generation emits an item for the tagged version with the expected
  archive URL, version/build metadata, length, and updater signature.
- Automated: `VoicePenTests/Updates/SoftwareUpdateConfigurationTests.swift`
  verifies the package target signs the app bundle before archiving it and the
  release workflow imports a stable macOS signing identity from GitHub Secrets.
- Manual: install an older update-enabled build into `/Applications`, publish or
  locally host a newer feed item, choose check for updates, approve the prompt,
  and confirm the app updates and launches as the newer version.
- Manual: locally host an appcast item for a newer build whose archive has a
  missing or invalid updater signature, choose check for updates, and confirm
  VoicePen refuses to install that update.
- Manual: check for updates from the newest build and confirm the standard
  no-update result is shown.

## Notes

- Sparkle 2 is the preferred updater framework because it provides the standard
  macOS update UI, archive verification, app replacement, and relaunch behavior.
- GitHub Releases remain the archive host. The appcast/feed is published through
  GitHub Pages from this repository so installed apps can keep a stable HTTPS
  `SUFeedURL` across releases.
- A Developer ID signed and notarized app is recommended for the smoothest macOS
  install and update experience. Sparkle update signatures are still required for
  authenticating update archives.
- The first update-enabled build is a transition build and must be installed
  manually on machines that currently run pre-updater builds.

## Open Questions

- None.
