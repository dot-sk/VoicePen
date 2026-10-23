# Verification

## Completed

- Contract-first baseline failed as expected before the new path/initialization types existed: `/private/tmp/whisper-metal-contract-baseline.log`.
- First targeted manifest, migration, alias and acceleration contracts: 8 tests passed, `/private/tmp/whisper-metal-contract-implemented.log`.
- Focused Whisper, routing, manifest, app paths and app-controller regression run: 151 tests in 11 suites passed, `/private/tmp/whisper-metal-focused.log`.
- Initial and final `make build` passed. Final source build exited 0: `/private/tmp/whisper-metal-final-build.log`; initial build: `/private/tmp/whisper-metal-app-build.log`.
- Real pinned v1.8.5 Q5 and Q8, each with and without legacy encoder files beside the canonical input path: inference and observed Metal encoder/decoder passed, and the runner exited 0. `/private/tmp/whisper-metal-native-swiftpm-cleanexit.log`.
- First hosted run preserved all four existing hosted tests, including both GigaAM/Whisper load orders. The new Whisper-specific test skipped because xcodebuild does not forward arbitrary shell environment variables. A configured xctestrun is required before counting that test as passed. `/private/tmp/whisper-metal-hosted.log`.
- Final `make test`: 708 tests in 80 suites passed, including canceled-waiter/non-cooperative alias ownership, canonical artifact fingerprint changes, cleanup boundaries, diagnostics, old completion-marker reuse, and failed repair retry. `/private/tmp/whisper-metal-final-complete-tests.log`.
- `make integration-test INTEGRATION_TEST_ACTION=build-for-testing` passed. `/private/tmp/whisper-metal-hosted-build.log`.
- A new temporary app copy was ad-hoc signed and its xctestrun explicitly received `VOICEPEN_WHISPER_NATIVE_CONFIG`. `make integration-test INTEGRATION_TEST_ACTION=test-without-building INTEGRATION_TEST_RUN=/private/tmp/voicepen-whisper-metal-hosted-configured-20261019/relocated.xctestrun` passed all five hosted tests without skips and exited 0. Q5/Q8 each completed inference with and without legacy companions, and the existing GigaAM checks passed in both native load orders. Framework/resource environment overrides were removed and the GigaAM app-bundle check remained enabled. `/private/tmp/whisper-metal-hosted-configured.log`.

## Q8 frozen-corpus evaluation

`VOICEPEN_WHISPER_NATIVE_CONFIG=/private/tmp/voicepen-whisper-metal-20261019/config.json`, `VOICEPEN_WHISPER_EVALUATION_DATASET=<repository>/.local/asr-quality/exports/c49eabd7e9a517bb85185f61c7b182af127071d3eaaa8ec49f8fc624fdec4561/dataset.json`, `VOICEPEN_WHISPER_EVALUATION_PROMPT=<repository>/.local/asr-quality/evaluations/gigaam-20261019/whisper-current/asr/prompt.txt`, and `VOICEPEN_WHISPER_EVALUATION_OUTPUT=/private/tmp/voicepen-whisper-metal-20261019/q8-evaluation.json` configured `make test TEST_FILTER=WhisperMetalNativeTests.productionAdapterRunsFrozenQ8Corpus`. A 600-second watchdog bounded the process. The test passed in 71.912 seconds and exited 0.

All 27 frozen saved ASR inputs were used without another preprocessing pass. Audio hashes, mono 16 kHz format, complete sample counts, 81 unique recording/repetition pairs and successful inference were asserted. Q8 SHA-256 remained `317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1`. Language was Russian, profile standard greedy, the frozen 40-term prompt was unchanged, and timestamps/VAD were disabled as in the matching historical pinned-runtime baseline.

`Tools/WhisperIntegration/score_metal_evaluation.py` reused the frozen normalizer functions, term policy and hesitation filter. Its final comparison used `gigaam-20261019/whisper-current/asr/runs.jsonl`, the matching pinned v1.8.5 Metal baseline. All 81 texts matched after the app's existing whitespace trimming. Raw native baseline strings retain surrounding whitespace; the app adapter trims it.

| Protocol | WER | CER |
|---|---:|---:|
| Base | 7.8125% | 4.2641% |
| Term aliases | 6.9435% | 3.6506% |
| Hesitation-filtered base | 7.8125% | 4.2641% |
| Hesitation-filtered aliases | 6.9435% | 3.6506% |

All four protocols reproduced the matching historical Metal scores. Median native inference was 0.948201 seconds versus historical 0.964032 seconds; model loading was 0.428471 seconds and warmup 0.432277 seconds. Median adapter wall time, including WAV reading, was 0.950225 seconds. Timing is sequential host evidence, not a paired Core ML comparison or microphone-to-insertion measurement. Pinned public timings do not expose a frontend timer, so that optional diagnostic is zero and is not used as a measured frontend result.

Private raw output and scored results: `/private/tmp/voicepen-whisper-metal-20261019/q8-evaluation.json`, `/private/tmp/voicepen-whisper-metal-20261019/q8-scored.json`; logs `/private/tmp/whisper-metal-q8-corpus.log`, `/private/tmp/whisper-metal-q8-score.log`.

## Teardown regression caught and fixed

The first native test completed all four inference cases but then exited 1 in the pinned runtime's Metal residency-set destructor. An asynchronous lease-cleanup closure retained the native context after the prepared request was released. The cleanup task now owns only the model ownership counter; the prepared operation itself owns the context. Tests release the prepared operation before releasing the client cache and assert that actual-context diagnostics disappear. The second native run completed cleanly without disabling residency sets, changing the framework, or bypassing process teardown.

## Specification and review

- Main-spec sync changed three local-model scenarios and added the two migration/availability requirements. A before/after assertion preserved all 31 unrelated scenarios and both decoding-profile requirements. Before-sync snapshot: `/private/tmp/whisper-metal-main-spec-before-sync.md`.
- `openspec validate use-metal-only-whisper --strict --no-interactive` and `openspec validate --specs --strict --no-interactive` passed, including all 17 main specs.
- `git --no-pager diff --no-ext-diff --check` passed. Focused strict Swift formatting passed for new runtime/integration files and changed Whisper production/test files.
- ADR-0012 was accepted after the measured SwiftPM, app-bundle and corpus checks. The OpenSpec change remains active; archival requires a separate user request.

## Limits

The host was Apple M1 Max on macOS 26.6.2. Actual macOS 15 execution was not repeated. Q5 recognition quality remains unmeasured. Unavailable GPU/library paths have deterministic signal-validation coverage; no physical GPU removal was attempted. The initialization observer depends on the pinned runtime's structural log signals, so framework upgrades require this native regression.

Private audio, weights, transcripts and detailed corpus output stay outside Git. No user model installation, settings, recordings, or running VoicePen process was modified. No model/runtime assets or releases were published, no worktree was created, and no commit or push was made.
