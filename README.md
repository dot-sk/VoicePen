# VoicePen

VoicePen is a small offline macOS app for dictation, voice sessions, and meeting recording.

I built it for myself because I wanted something simple, comfortable, and free:
quick push-to-talk dictation, a normal sessions/history flow, and a meeting
recording mode with local transcription and experimental speaker diarization. I
could not find that exact mix without subscriptions, cloud transcription, or too
much product ceremony, so I decided to make it and keep the project in an
open-source spirit.

It is still early and personal, but useful enough to share.

## Features

- Push-to-talk dictation: hold the hotkey, speak, and VoicePen inserts the final text into the active app.
- Sessions: keep local history for ordinary dictation sessions.
- Meetings: record microphone plus system audio, transcribe locally, and optionally add timecodes and speaker labels.
- Custom dictionary: normalize names, product terms, and recurring recognition mistakes.
- Local-first privacy: no cloud transcription, no analytics, and no runtime data collection.

## Status

VoicePen is an early macOS build for my own workflow and a small Friends &
Family circle. Expect rough edges, but also a bias toward practical fixes over
big platform ideas.

## Requirements

- macOS 15 or newer on Apple Silicon.
- Microphone permission.
- Accessibility permission for text insertion and global hotkeys.
- System Audio Recording permission for Meeting Mode.
- Xcode installed for local development.

## Install

If you received `VoicePen.app` or `VoicePen.zip`:

1. Unzip the file.
2. Move `VoicePen.app` to `/Applications`.
3. Right-click `VoicePen.app`.
4. Click `Open`.
5. Confirm opening the app if macOS warns that it is from an unidentified developer.

Use **right-click -> Open** on the first launch. Unsigned development builds can
be blocked by Gatekeeper; if that happens, run:

```bash
xattr -dr com.apple.quarantine /Applications/VoicePen.app
open /Applications/VoicePen.app
```

## Build Locally

```bash
make resolve-packages
make build
make run
```

Run tests:

```bash
make test
```

Development tooling lives in [`Docs/development.md`](Docs/development.md), and
test guidance lives in [`Docs/testing.md`](Docs/testing.md).

## Development Workflow

VoicePen uses a spec-driven workflow for product behavior. Before changing how
the app behaves, update or create the relevant spec in [`Specs/`](Specs/).

The short version:

1. Find the relevant spec in [`Specs/index.md`](Specs/index.md).
2. Update acceptance criteria before implementation.
3. Add or update focused tests for the changed behavior.
4. Implement the smallest useful change.
5. Run `make test` before handoff for production behavior changes.

Presentation-only and README changes do not need a spec.

## Local Data

VoicePen stores downloaded models here:

```text
~/Library/Application Support/VoicePen/Models/
```

VoicePen stores settings, history, dictionary entries, and meeting transcripts
in a local SQLite database:

```text
~/Library/Application Support/VoicePen/VoicePen.sqlite
```

Optional proxy settings for model downloads can be configured here:

```text
~/.voicepen/config.toml
```

## Support

VoicePen is free because I wanted this workflow to exist without another
subscription. Feedback, issues, and pull requests are welcome. I may add a
"buy me a beer" link later for people who want to support the work, but the app
should stay useful without paying for it.

## Maintainers

- Release and signing notes: [`Docs/releasing.md`](Docs/releasing.md)
- Architecture decisions: [`Docs/adr/`](Docs/adr/)
- Product specs: [`Specs/`](Specs/)
