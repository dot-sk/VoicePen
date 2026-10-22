## 1. Contracts and recognition evidence

- [x] 1.1 Add behavioral tests for Russian UTF-8 fragments, special tokens, multiple words, invalid/missing probability, and exact word range reconstruction: TranscriptConfidenceTests
- [x] 1.2 Extract Whisper token confidence without changing inference options and preserve metadata through routing; prove unsupported GigaAM yields no fabricated scores: native 32-record extraction review, routingPreservesOptionalRecognitionConfidence, recognizerWithoutConfidenceKeepsPlainTextBehavior
- [x] 1.3 Review the candidate aggregation and threshold on existing confirmed examples, document false positives/negatives, and fix the policy before final UI validation: confidence-review.md, threshold 0.3

## 2. Text mapping and persistence

- [x] 2.1 Test and implement conservative alignment through sanitization, dictionary replacements, aliases, command output, punctuation, repeated words, and output normalization: mappingsPreserveOnlyUnchangedUnambiguousWords, dictationMapsHintsThroughDictionaryAndInsertsUnannotatedText, terminalCommandCanPasteAndSubmitInTerminalContext; existing sanitization/output-normalization coverage retained
- [x] 2.2 Test and implement optional history metadata round-trip, compression, eviction, malformed ranges, and older rows with absent hints: reviewHintsSurviveCompressionAndAreRemovedWithTextEviction, corruptReviewMetadataDoesNotPreventHistoryLoading, malformedOrStaleStoredHintsAreIgnored, existing legacy migration tests

## 3. Sessions display

- [x] 3.1 Supply valid ranges to Sessions detail attributed rendering and textual/accessibility review explanation; preserve selection when only styling changes. Use only the existing editor, no new controls or counter
- [x] 3.2 Add behavioral coverage for plain selected/full copy and insertion with hints; verify unsupported/legacy fallback and absence of stale hints after session change: TranscriptReviewTextTests, pipeline tests, isolated native editor QA for selected copy/full-copy routing and styling changes
- [x] 3.3 Inspect the production editor in an isolated native host in both themes for readable emphasis, native hover explanation, selection, long-text scrolling, and unchanged copy behavior; screenshots inspected after removing the counter

## 4. Verification

- [x] 4.1 Run strict OpenSpec validation, make test, and make build: 740 tests passed; final app build succeeded; strict formatting and git diff --check passed

## 5. Native GigaAM confidence extension

- [x] 5.1 Add native CTC tests for normalized confidence, repeat/blank collapse, score-shift invariance, invalid evidence, and unchanged token/frame output: transcribe_gigaam_ctc_confidence_unit, with assertions enabled in Release
- [x] 5.2 Maintain a reproducible native patch and package identity; build and verify a new local framework with unchanged model weights: 0003-ctc-confidence.patch, candidate.3, package manifest verification and app-bundle C API identity check
- [x] 5.3 Test and implement timestamp-independent Swift symbol-to-word mapping and persisted backend-specific review policy, including unavailable evidence fallback and reuse of the known previous runtime's unchanged weights: GigaAMConfidenceTests, gigaAMReviewHintUsesItsPersistedPolicy, confidenceRuntimeReusesUnchangedInstalledWeightsWithoutRewritingMarker, confidenceUpgradeRejectsDifferentInstallation
- [x] 5.4 Compare old/new native text and latency on paired confirmed recordings; inspect GigaAM review hints and document a separate threshold: 42 recordings, three repeats per run, before/candidate/after controls, 378 measured calls, threshold 0.6
- [x] 5.5 Run native tests, package verification, strict OpenSpec validation, make test, and make build: 53 native tests, 21 recipe tests, 748 Swift tests including actual packaged native inference; build succeeded
