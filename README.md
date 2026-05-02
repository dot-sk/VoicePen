# VoicePen

VoicePen is a small offline macOS push-to-talk dictation app.

It lives in the menu bar, records audio while the hotkey is held, transcribes locally, applies a custom dictionary, and pastes the final text into the active app.

## Current Status

VoicePen is an early Friends & Family build.

- Offline-first transcription.
- No cloud transcription.
- No analytics.
- No runtime data collection.
- Local history and dictionary storage.
- Model files are downloaded only after user confirmation.

## Requirements

- macOS 15 or newer on Apple Silicon.
- Xcode installed for local development.
- Microphone permission.
- Accessibility permission for text insertion and global hotkeys.

## Spec-Driven Development

VoicePen uses a strict AI spec-driven workflow. Product behavior should be described in `Specs/` before code changes are made.

For any feature or behavior change:

1. Find the relevant spec in `Specs/index.md`.
2. If there is no spec, create one from `Specs/templates/feature-spec.md`.
3. Fill in the frontmatter, problem, behavior, acceptance criteria, examples, and test mapping before implementation.
4. Add or update tests that prove the acceptance criteria.
5. Implement the smallest code change that satisfies the spec.
6. Update the spec in the same change if the final behavior or test mapping changes.
7. Run `make test-strict` before opening or merging the pull request.

For bug fixes, use `Specs/templates/bug-spec.md` when the bug is not already covered by an existing spec. The bug spec should include the current broken behavior, desired behavior, regression test, and any required manual verification.

`make test-strict` validates the specs and then runs the unit test suite. The spec validator checks frontmatter, required sections, acceptance criteria, test mapping, and links from `Specs/index.md`.

Use ADRs in `Docs/adr/` for significant technical decisions and tradeoffs. Specs describe what VoicePen should do; ADRs explain why a durable architecture or process decision was chosen. Routine bug fixes and small implementation details do not need ADRs.

## Build Locally

```bash
make resolve-packages
make build
```

Run tests:

```bash
make test
```

Build and launch:

```bash
make run
```

## Install a Friends & Family Build

If you received `VoicePen.app` or `VoicePen.zip`:

1. Unzip the file.
2. Move `VoicePen.app` to `/Applications`.
3. Right-click `VoicePen.app`.
4. Click `Open`.
5. Confirm opening the app if macOS warns that it is from an unidentified developer.

Do not double-click on first launch. Use **right-click -> Open** the first time.

## If macOS Still Blocks the App

Unsigned development builds can be quarantined by Gatekeeper.

If right-click -> Open is not enough, run:

```bash
xattr -dr com.apple.quarantine /Applications/VoicePen.app
```

Then open the app again with:

```bash
open /Applications/VoicePen.app
```

This is expected for unsigned Friends & Family builds. A paid Apple Developer ID certificate and notarization are needed for the smooth public distribution flow.

## Permissions

VoicePen needs two macOS permissions.

Microphone:

- Used to record your voice.
- Audio is processed locally.

Accessibility:

- Used for global hotkeys.
- Used to paste recognized text into the currently focused app.

To grant Accessibility manually:

1. Open System Settings.
2. Go to Privacy & Security.
3. Open Accessibility.
4. Enable VoicePen.
5. Restart VoicePen if needed.

If Accessibility still looks stuck, remove VoicePen from the list, quit the app, open it from `/Applications`, and grant the permission again.

## Models

VoicePen stores downloaded models here:

```text
~/Library/Application Support/VoicePen/Models/
```

The default Whisper model is:

```text
ggml-large-v3-turbo-q5_0
```

The app also requires its Core ML encoder companion for fast accelerated transcription.

## Local Data

VoicePen stores local app data here:

```text
~/Library/Application Support/VoicePen/VoicePen.sqlite
```

This database contains app settings, custom dictionary entries, usage stats, and voice session history.

Proxy settings, if needed for model downloads, can be configured outside the app:

```text
~/.voicepen/settings.json
```

Example:

```json
{
  "env": {
    "http_proxy": "http://proxy.example.local:2080/"
  }
}
```

## Custom Dictionary

The dictionary is edited inside the VoicePen app.

Each term has:

- canonical form;
- variants that should be replaced with that canonical form.

CSV import format:

```csv
canonical,variants
PostgreSQL,"постгрес; постгресе; postgres"
TypeScript,"тайп скрипт; type script"
```

Large dictionaries can slow down transcription post-processing. As a rough guide:

- up to 100 terms is small;
- 100-500 terms is usually fine;
- 500+ terms can become noticeable;
- 1,000+ terms should be trimmed or split.

## CI

GitHub Actions runs unit tests on every pull request and on pushes to `main`.

The workflow is in:

```text
.github/workflows/ci.yml
```

## Releases

Release builds are created only for GitHub releases.

Auto-update releases require the Sparkle private key in GitHub:

- repository secret `SPARKLE_PRIVATE_KEY`.

Generate the keypair with Sparkle's `generate_keys` tool. The public key is
stored in the app's `SUPublicEDKey`; keep the private key in GitHub Actions
secrets.

Prepare a release pull request:

```bash
make prepare-release VERSION=1.1.0
```

This creates a branch named `release/v1.1.0`, bumps the Xcode app version, pushes the branch, and opens a pull request.

After the pull request is merged, create and push the release tag:

```bash
make publish-release VERSION=1.1.0
```

Pushing the tag starts the Release workflow:

```text
.github/workflows/release.yml
```

When the workflow finishes, download `VoicePen-macOS-unsigned.zip` from the GitHub Release page.
The same workflow signs the archive for Sparkle and publishes
`https://dot-sk.github.io/VoicePen/appcast.xml` through GitHub Pages.

Local package build:

```bash
make package
```

The app is unsigned. First launch still requires **right-click -> Open**.
