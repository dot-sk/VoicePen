## 1. Evidence and automated contract

- [ ] 1.1 Independently review background and genuine-participant intervals in both production recordings, retaining private audio and annotations locally; add a held-out recording or reviewed independent examples before claiming generalization.
- [ ] 1.2 Predeclare at most six policies including baseline; evaluate episode support, union speech duration and independent speech evidence without forcing the known participant count. Freeze passing parameters and report rejected genuine speech as well as background acceptance. Stop integration if no policy passes.
- [ ] 1.3 Add Swift Testing fixtures for isolated background interjection, fragmented background event and repeated substantive participation, including imbalanced speech, true interruptions and short genuine contributions.
- [ ] 1.4 Add Swift Testing coverage for short single-speaker recording, no candidate qualifies, absent confidence, invalid/nonfinite intervals, overlapping duplicate turns and order independence.
- [ ] 1.5 Add pipeline/formatter/history coverage for labels and count using the same confirmed identities, preserved unattributed text, no bridging across rejected intervals, and unchanged existing meetings when read without retry.

## 2. Implementation after the evidence gate

- [ ] 2.1 Implement the frozen deterministic participant-confirmation helper with accepted identities, supporting evidence and rejection reasons; avoid new dependencies.
- [ ] 2.2 Apply confirmation before transcript assignment and counting; prevent the backend roster or existing-count fallback from restoring rejected IDs, and keep aggregate diagnostics free of transcript content.
- [ ] 2.3 Repeat private local evaluation using the production helper and document failures and limitations separately from model-selection research.

## 3. Verification

- [ ] 3.1 Run `openspec validate confirm-meeting-participants --strict --no-interactive` and `make test`; run `make build` if app-target wiring changes.
- [ ] 3.2 Inspect the scoped diff, record exact checks and frozen policy results, and leave unrelated changes and existing saved recordings untouched.
