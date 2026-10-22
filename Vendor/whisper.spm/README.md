# VoicePen whisper.cpp package wrapper

This local package exposes the official prebuilt
[`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) XCFramework to VoicePen.
The release URL and SwiftPM checksum are pinned in `Package.swift`.

Current runtime: **v1.9.5**, distributed as official binary release
[`b5454`](https://github.com/ggml-org/whisper.cpp/releases/tag/b5454).
Both tags resolve to source commit `d1be6fde11ac6e0407606b4e42fe72d34add8037`.
The v1.9.5 release itself has no binary assets. The b5454 XCFramework SHA-256,
verified against the GitHub asset digest and downloaded archive, is
`e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b`.
The official binary's `whisper_version()` reports `1.9.5-dev` despite sharing
the stable tag's commit. Execution diagnostics retain that native version string.

The legacy source tree remains in this directory for repository history, but it
is not compiled by the current package manifest.
