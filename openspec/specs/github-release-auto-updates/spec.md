# GitHub Release Auto Updates Specification

## Purpose

VoicePen release builds are currently distributed as downloadable GitHub Release
archives. Users who already installed the app must manually download and replace
the application for each update, which makes Friends & Family updates slow and
error-prone.

## Requirements

### Requirement: GitHub Release Auto Updates

VoicePen SHALL preserve the behavior contract for this capability.

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

#### Scenario: User opens the VoicePen menu or app commands in an update-enabled build

- **WHEN** a user opens the VoicePen menu or app commands in an update-enabled build
- **THEN** VoicePen shall expose a check-for-updates action.

#### Scenario: Update-enabled build is running

- **WHEN** an update-enabled build is running
- **THEN** VoicePen shall allow Sparkle to check for updates automatically and prepare eligible updates in the background.

#### Scenario: Newer GitHub Release is available in the configured feed

- **WHEN** a newer GitHub Release is available in the configured feed
- **THEN** VoicePen shall present a standard macOS update prompt with release information and an install action.

#### Scenario: User approves installation

- **WHEN** the user approves installation
- **THEN** VoicePen shall download the release archive, replace the installed app bundle, and relaunch or prompt for relaunch using the updater's standard flow.

#### Scenario: No newer release is available

- **WHEN** no newer release is available
- **THEN** VoicePen shall report that the installed build is current.

#### Scenario: Release publishing runs for a tagged release

- **WHEN** release publishing runs for a tagged release
- **THEN** it shall publish or update the GitHub Pages appcast/feed metadata that points to the GitHub Release archive.

#### Scenario: CI runs for a release pull request

- **WHEN** CI runs for a release pull request
- **THEN** it shall build an unsigned production release candidate from the pull request head commit in parallel with the required quality and unit-test checks.

#### Scenario: CI finishes the release-candidate build

- **WHEN** CI finishes the release-candidate build
- **THEN** it shall retain the candidate as an immutable workflow artifact whose identity includes the exact source commit.

#### Scenario: Release-candidate builds

- **WHEN** this capability applies
- **THEN** Release-candidate builds shall not receive production signing or update-signing secrets.

#### Scenario: Release tag is published

- **WHEN** a release tag is published
- **THEN** it shall be created from the release branch where the app version was bumped.

#### Scenario: Release tag is published 2

- **WHEN** a release tag is published
- **THEN** release publishing shall require an open, non-draft pull request from the release branch into `main` with completed green checks.

#### Scenario: Release tag is published 3

- **WHEN** a release tag is published
- **THEN** release publishing shall require the Xcode marketing version to match the requested release version.

#### Scenario: Release tag is published 4

- **WHEN** a release tag is published
- **THEN** release publishing shall require exactly one numeric Xcode build number that is greater than the previous release build.

#### Scenario: Release publishing runs for a tag

- **WHEN** release publishing runs for a tag
- **THEN** it shall require a successful release pull-request CI run for the exact tagged commit before publishing any archive.

#### Scenario: Exact release-candidate artifact is available

- **WHEN** the exact release-candidate artifact is available
- **THEN** tagged release publishing shall promote that artifact instead of recompiling or rerunning the unit-test suite.

#### Scenario: Validated release-candidate artifact is unavailable

- **WHEN** a validated release-candidate artifact is unavailable
- **THEN** tagged release publishing may rebuild the package from the same commit only after confirming that the exact commit already passed release pull-request CI.

#### Scenario: Release publishing packages an app archive

- **WHEN** release publishing packages an app archive
- **THEN** the app bundle shall not contain a corrupted or stale code signature that prevents Sparkle validation.

#### Scenario: Release publishing packages app archives across versions

- **WHEN** release publishing packages app archives across versions
- **THEN** it shall sign the app bundle with a stable macOS code signing identity so macOS privacy permissions can remain associated with VoicePen across updater installs.

#### Scenario: Release publishing packages a production app archive

- **WHEN** release publishing packages a production app archive
- **THEN** it shall verify the final code signature before uploading the archive.

#### Scenario: Development build is run locally

- **WHEN** a development build is run locally
- **THEN** it shall use a distinct bundle identifier, display name, and Application Support folder from the release app so macOS privacy permissions and local state do not conflict with production installs.

#### Scenario: Release build is packaged

- **WHEN** a release build is packaged
- **THEN** it shall keep the production bundle identifier, display name, and Application Support folder used by installed updater-enabled builds.

#### Scenario: Archive is missing a valid updater signature

- **WHEN** an archive is missing a valid updater signature
- **THEN** VoicePen shall not offer it as an installable update.

### Requirement: Promoted releases prepare update signing tools

Release publishing SHALL prepare the tools needed to sign update metadata independently of app compilation when promoting a validated candidate on a fresh runner.

#### Scenario: Candidate is promoted on a fresh release runner

- **WHEN** a validated release candidate is promoted on a runner without build dependencies
- **THEN** publication prepares update-signing tools before generating the signed appcast without recompiling the candidate
