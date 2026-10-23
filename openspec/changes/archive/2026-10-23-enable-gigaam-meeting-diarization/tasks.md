## 1. Contract and tests

- [x] 1.1 Add behavior tests for GigaAM effective timing policy, valid and invalid CTC token alignment, and text-only dictation.
- [x] 1.2 Add Meeting pipeline tests for GigaAM timecodes, two speakers, and alignment fallback; map retained-audio retry to the existing pipeline retry tests.

## 2. Implementation

- [x] 2.1 Extract aligned words from the pinned GigaAM token API only when timestamps are requested.
- [x] 2.2 Route GigaAM Meeting timing requests into existing formatting and diarization, and update settings and diagnostics to reflect effective support.

## 3. Verification

- [x] 3.1 Validate OpenSpec strictly, run `make test`, and build the app if target wiring requires it.
- [x] 3.2 Verify the native aligned-token path on a retained Meeting excerpt and report the recorded Meeting's observed SpeakerKit output without changing its saved history.
