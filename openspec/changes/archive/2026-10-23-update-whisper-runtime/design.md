## Context

The local SwiftPM wrapper currently pins the official v1.8.5 XCFramework. Latest stable v1.9.5 has no assets on its semantic-version release, but official binary release b5454 resolves to the exact same source commit, d1be6fde11ac6e0407606b4e42fe72d34add8037.

## Decisions

Use the existing remote binary-target mechanism with the official b5454 XCFramework. Its SHA-256 is e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b, verified against the GitHub asset digest and the downloaded archive. Document semantic version, binary tag and source commit together. This avoids introducing a custom build or binary hosting flow.

Keep model artifacts, defaults, decoding profiles, language/glossary handling, Metal-only initialization policy, isolated model paths, cancellation and shared loading unchanged. Update diagnostics to v1.9.5. Existing native regression coverage will exercise Q5 and Q8, legacy companions, confidence and timestamp contracts. Execute GigaAM and Whisper native tests in the same test process to detect packaging conflicts.

Read the diagnostic version from `whisper_version()` rather than a handwritten label. The official b5454 binary reports `1.9.5-dev`; both GitHub tag references were independently resolved to the same commit, so this suffix is retained verbatim rather than hidden.

## Risks and verification

Updated ggml may change initialization diagnostics, GPU resource discovery or numeric decoding results. Compile against the new headers, execute native tests, run make test and make build, and inspect the framework embedded in the built app. No speed or corpus-wide quality improvement is assumed from a dependency update.
