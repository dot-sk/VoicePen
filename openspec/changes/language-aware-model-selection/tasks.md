## 1. Contract and coverage

- [x] 1.1 Specify shared language controls, model fallback, explicit model selection and persistence semantics.
- [x] 1.2 Cover Russian restoration, compatible GigaAM, fallback order, locale/auto and explicit model selection in pure policy tests; cover restart, legacy/malformed map and write failure in settings tests; cover controller switching and active dictation rejection.

## 2. Implementation

- [x] 2.1 Add the local selection policy and atomic additive settings persistence.
- [x] 2.2 Wire both selectors through shared controller actions and preserve native effective decoding.

## 3. Verification

- [x] 3.1 Run strict OpenSpec validation, focused formatting/lint, make test and make build.

## 4. Per-language last-used priority

- [x] 4.1 Cover symmetric English/Russian restoration, remembered missing files and compatible current-model fallback only without a remembered choice.
- [x] 4.2 Prioritize each language's last-used model and rerun make test, formatting/lint and strict spec validation.
