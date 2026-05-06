---
id: SPEC-006
status: implemented
updated: 2026-05-07
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
- When release publishing runs on GitHub Actions, it shall restore SwiftPM
  package and build caches before testing and packaging so release jobs can
  reuse dependency downloads and compiled intermediates when package manifests
  are unchanged.
- When a release tag is published, it shall be created from the release branch
  where the app version was bumped.
- When a release tag is published, release publishing shall require an open,
  non-draft pull request from the release branch into `main` with completed
  green checks.
- When a release tag is published, release publishing shall require the Xcode
  marketing version to match the requested release version.
- When a release tag is published, release publishing shall require exactly one
  numeric Xcode build number that is greater than the previous release build.
- When release publishing builds a tagged release, it shall avoid a standalone
  package-resolution step because the test and package builds already resolve
  Swift packages as needed.
- When release publishing packages an app archive, the app bundle shall not
  contain a corrupted or stale code signature that prevents Sparkle validation.
- When release publishing packages app archives across versions, it shall sign
  the app bundle with a stable macOS code signing identity so macOS privacy
  permissions can remain associated with VoicePen across updater installs.
- When release publishing packages a production app archive, it shall verify the
  final code signature before uploading the archive.
- When a development build is run locally, it shall use a distinct bundle
  identifier, display name, and Application Support folder from the release app
  so macOS privacy permissions and local state do not conflict with production
  installs.
- When a release build is packaged, it shall keep the production bundle
  identifier, display name, and Application Support folder used by installed
  updater-enabled builds.
- When an archive is missing a valid updater signature, VoicePen shall not offer
  it as an installable update.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Manual check finds update | Installed build `1.0`, feed contains `1.1` | VoicePen shows the updater prompt for `1.1`. |
| Manual check is current | Installed build matches newest feed item | VoicePen reports that VoicePen is up to date. |
| First updater rollout | User has a pre-updater build installed | User manually installs the transition build once; later updates use the updater. |
| Local development run | Debug build is launched from Xcode or `make run` | macOS sees `VoicePen Dev` with a development bundle identifier and separate local data folder. |
| Release packaging | Release build is archived for GitHub Releases | macOS sees production `VoicePen` with the production bundle identifier and local data folder. |
| Release signing | Tagged release workflow packages the app | The app is signed with the configured identity and passes code signature verification before upload. |
| Release tag publishing | `make publish-release VERSION=1.1.0` after preparing `release/v1.1.0` | The `v1.1.0` tag is pushed from `release/v1.1.0`. |
| Release build cache | Publish a tag after a prior macOS CI run with unchanged package manifests | The release workflow can restore SwiftPM package and build artifacts before tests and packaging. |
| Release PR not green | `make publish-release VERSION=1.1.0` while the release PR has pending or failed checks | Publishing stops before creating or pushing `v1.1.0`. |
| Release metadata mismatch | `make publish-release VERSION=1.1.0` while the branch contains another marketing version or a non-incremented build | Publishing stops before creating or pushing `v1.1.0`. |
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
- Manual: run `make prepare-release VERSION=x.y.z`, wait for the release pull
  request checks to pass, then run `make publish-release VERSION=x.y.z` and
  confirm the script refuses non-green PRs, mismatched versions, or
  non-incremented builds before tagging, and confirm a valid tag points to the
  release branch commit.
- Automated: `VoicePenTests/Updates/SoftwareUpdateConfigurationTests.swift`
  verifies the package target signs and verifies the app bundle before archiving
  it and the release workflow imports a stable macOS signing identity from GitHub
  Secrets.
- Automated: `.github/workflows/release.yml` restores SwiftPM package and build
  caches before release tests and packaging.
- Automated: `VoicePenTests/Updates/SoftwareUpdateConfigurationTests.swift`
  verifies Debug and Release use separate app identity and local data build
  settings.
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
- Developer ID signing and notarization are still recommended for public
  distribution. Friends & Family builds may use the configured non-Developer ID
  signing identity, but the package step must still verify the code signature
  before upload. Sparkle update signatures are still required for authenticating
  update archives.
- The first update-enabled build is a transition build and must be installed
  manually on machines that currently run pre-updater builds.

## Open Questions

- None.
