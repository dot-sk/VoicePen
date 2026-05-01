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

- macOS on Apple Silicon.
- Xcode installed for local development.
- Microphone permission.
- Accessibility permission for text insertion and global hotkeys.

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
    "http_proxy": "http://192.168.86.2:2080/"
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
