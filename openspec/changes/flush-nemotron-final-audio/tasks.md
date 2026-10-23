## 1. Contract and regression coverage

- [x] 1.1 Specify Nemotron-only trailing context and source/cancellation invariants.
- [x] 1.2 Add native short-word and exact-boundary coverage with unchanged source bytes/frame count; add silence controls and use existing longer-file/repeated/cancellation native coverage plus client cancellation/error lifecycle tests.

## 2. Implementation and validation

- [x] 2.1 Append one generated silent chunk in the native adapter without counting it as original audio.
- [x] 2.2 Run native weighted regressions, make test, make build, strict OpenSpec validation and focused format/lint checks.
