## 1. Contract and automated coverage

- [x] 1.1 Specify optional English model selection, verified installation and final-only file recognition.
- [x] 1.2 Add model-manifest, routing, effective-settings and preference-restoration tests for both selection scenarios and final-only pipeline behavior.
- [x] 1.3 Add installation tests for verified completion, incompatible/partial files, cancellation and retry; cover idle/active resource deletion.
- [x] 1.4 Add client lifecycle tests for shared loading, captured model, serialized fresh requests, complete audio and cancellation/error recovery.

## 2. Implementation

- [x] 2.1 Add the file-only native Nemotron adapter and core client with managed resource lifetime.
- [x] 2.2 Wire the existing model selector, router, effective capabilities, settings and diagnostics.
- [x] 2.3 Add the immutable verified upstream artifact manifest and reuse the existing download lifecycle.

## 3. Verification

- [x] 3.1 Run a real English audio smoke test with the pinned downloaded weights, including repeated requests and cancellation/retry.
- [x] 3.2 Run strict OpenSpec validation, focused formatting/lint, `make test` and `make build`.
