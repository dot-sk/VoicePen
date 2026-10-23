# Native implementation evidence

The maintained recipe is `Vendor/transcribe-native`: a pinned archive, the
immutable research patch, a second owned patch, offline tools and native tests.
No hosted fork, release, model asset, or application dependency is published here.
Private outputs below live under the ignored root
`.local/asr-quality/native-gigaam-600m/`. No private transcript is in this file.

## Candidate identity

Candidate `voicepen-gigaam-600m-0.1.0-candidate.2` remains **unaccepted** as a
complete dependency. Corpus acceptance is a narrower passing gate.
The reviewed F16 pair is **accepted for local use on this verified Mac**;
`host-local-acceptance.json` records that scope and explicitly keeps
`distribution_accepted=false`. This does not rewrite the immutable package
manifest's unaccepted distribution status or assert macOS 15 runtime testing.

| Artifact | Relative local path | SHA-256 |
| --- | --- | --- |
| Package manifest | `package-v3/manifest.json` | `7738da1d56246941906071a4177dd5586dd02c5560df4d97eb6fee72b52626e8` |
| Framework binary | `package-v3/VoicePenGigaAM.framework/Versions/A/VoicePenGigaAM` | `f2fe97a8a947483484d60c8af5e4179b26355387c2765cf83d62a7a83dbb3330` |
| F16 GGUF, 1,172,222,176 bytes | `models/gigaam-600m-F16-candidate2.gguf` | `06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae` |
| F32 diagnostic GGUF | `models/gigaam-600m-F32-candidate2.gguf` | `9308213089f60f3bdeb5596929e55086f56846b192192a59532c339fd958a7b2` |

The package uses C ABI/module `VoicePenGigaAM`, public `transcribe_*` symbols,
private static ggml, framework-owned embedded Metal source and no Objective-C
resource lookup class. Deployment metadata is macOS 15.0 arm64; execution was
on this Mac's macOS 26.6.2, not a macOS 15 installation. AppleClang and actual
compile SDK 26.5 are recorded in the package manifest. The 147 public exports,
relocatable install name and absence of external ggml/check-out paths were
checked by `package.py` using `nm` and `otool`.

## Passing evidence

| Tasks | Evidence below local root | What it proves |
| --- | --- | --- |
| 1.1 | `package-v3/manifest.json`; repository `pins.json`, `PATCHES.md`, `schema/`, `licenses/` | Pinned source/model/tool inputs, patch ownership, full license provenance and content schema. |
| 1.2, 1.6 | `offline-tests-accepted.log`, 21 tests; `candidate2-loader/report.json` | Exact tensor/layout/vocabulary/profile contracts, frozen evaluation accounting; native malformed metadata and finite-valued tensor corruption reject before exposing a model. A nested-watchdog test also proves cleanup despite duplicate SIGTERM forwarding by uv. |
| 1.3 | `fixtures-f16/report.json`; eight per-fixture reports | All 24 blocks plus frontend/subsample/final encoder/logits, five licensed language samples and silence/impulse/seeded noise: 224 passing F16 checkpoints. Speech token IDs exactly match the reference. |
| 1.4 | `boundary-parity/report.json`; `window-ctc-tests`; complete stock25 corpus | Release package passes speech/logits/token/span comparisons at 624/625/626 encoder frames; native planner/collapse tests cover repeats and blank transitions. The longest corpus recording matches the window oracle. |
| 2.2 | `v3-regression/report.json`; repository `fixtures/v3-regression.json` | All four real upstream v3 checkpoints preserve exact text/tokens, capabilities, explicit option errors and legacy ignored-prompt behavior on short and longest inputs (8/8 fixture pairs). |
| 2.1 | `conversion-repro.log`, `conversion-f32-repro.log`; both model sidecar catalogs | Both F16 and F32 conversions repeated with identical digests, 824 tensors, 75 inverse transforms and exact logical values. |
| 2.5 | `metal-library-failure.log`, `metal-oom-reuse.log`; existing masked-device and placement reports | Exact canonical binary: nil Metal library compilation returns backend error/model NULL; nil encoder buffer allocation returns OOM, then the same model succeeds after removing the fault. Tests alter Metal methods only inside their own process and create no physical memory pressure. Individual post-load pipeline-function failure was not separately injected. |
| 2.6 | `fixtures-f16/report.json`, `fixtures-f32-cpu/report.json` | Root review confirms the original design permits this primary F16/Metal plus strict F32/CPU graph/layout split. Both pass. The additional F32-storage/Metal run remains FAILED, with half-operand cause and unchanged limits. |
| 1.5, 2.4 | `candidate2-contracts.log`, `.process.json`; `candidate2-loader/report.json` | Actual C defaults/capabilities, explicit unsupported options, invalid/silent audio, deterministic abort at the fourth callback poll, reuse after abort, required-Metal success and masked-device failure. |
| 2.3 | `window-ctc-tests`; `candidate2-f16-stock25/` native logs and sample counts | Actual native planner/one-collapse contract and default stock25 execution; no research overrides used by the release package. |
| 3.1 | `reference-stock25/metadata.json`, `runs.jsonl`, `reference-stock25.process.json` | Independent MLX F32 stock-window oracle for all 27 inputs, matching F16-valued weights and retained/window-local spans. Frozen research whole-input and MLX F16 arithmetic remain separate comparators. |
| 3.2 | `candidate2-evaluation-f16.json`; `candidate2-f16-stock25/` | Exact final package/model pair: 27/27 recordings match oracle and frozen research stock25 baseline; 81/81 repeated outputs stable, all four scoring protocols and edit alignments saved. |
| 3.5 | `candidate2-evaluation-summary.json`; `candidate2-benchmark.process.json` | Cold load, one warmup per shape, three timed calls, four threads; median warmed 0.253570 s and peak RSS 1,303,527,424 bytes. Longest input is included; no dump overhead. |
| 3.4 | `q8-unavailable-report.json`, `q8-unavailable.log` | Optional Q8 remains unavailable. Final loader rejects the old artifact's missing version/integrity metadata. Fresh scoring of preserved complete native Q8 stock25 runs finds sample-009 word/character regression and aggregate regression under all four policies. No maintained Q8 inference acceptance is claimed. |
| 3.6 | `head-ab-maintained/report.json`, `native-profiles.json`; `head-probes/` | Exact maintained validation build: 81/81 CPU/GPU pairs match text and all four policies; separate same-build tensor probes pass. Original reporting failure and source snapshot remain preserved; complete measured pairs were reused. |
| 3.7 | `package-v3/manifest.json` head decision | Host CTC head retained; preserved 81-pair research confidence interval crosses zero. No GPU-head optimization acceptance. |
| 4.1 | `build-test/`, `build-framework/`; `build-test-crc.process.json`, `build-framework-crc.process.json` | Library-only isolated release and library/tests/tools matrix build, examples disabled; required `wav.h` dependency fixed. Latest CRC diagnostic rebuild passed. |
| 4.2 | `package-v3/`, `swift-v3-smoke.json`; `/private/tmp/voicepen-gigaam-v3/` | Final exact v3 framework linked and imported by standalone C/Swift clients outside the checkout, target arm64 macOS 15.0. |
| 4.4 | `package-repro-check/report.json`; `restored-client.process.json` | Second clean framework build and package reproduce all 41 files, binary and manifest exactly, with no UUID differences. Corrupted/missing binary and incompatible interface reject; restored pair completes real C load/run/cancel/reuse/free without Python on PATH. This restores a verified candidate, not an invented accepted dependency. |
| 4.5 | `ctest-candidate2.log`, `.process.json`; `v3-regression/report.json` | Final CRC diagnostic build passes all 52 upstream tests, serial; all four real v3 profiles preserve their pre-extension contracts. |
| 4.6 | Repository `tools/update_gate.py`, `tests/test_package.py`, `PATCHES.md` | Fail-closed dependency gate requires matching candidate evidence for every applicable acceptance category. Documentation records update review and rollback. This does not mean all gate inputs currently exist. |

The final corpus base result is 119 word edits / 1472 words and 375 character
edits / 8724 characters. Alias diagnostics are 81 / 1469 and 166 / 8711;
hesitation variants have the same totals. These are measurements, not new
acceptance thresholds. Gold, normalization and policy hashes are unchanged.

The primary F16 numerical gate's maximum NRMSE is 0.0010843542, at Kyrgyz
block 3, below its frozen 0.01 limit; minimum cosine is 0.9999994121.
The separate **F32-storage/Metal diagnostic fails** at Kyrgyz blocks 2–5:
NRMSE 0.001010–0.001084 exceeds the frozen 0.001 limit, despite exact token
IDs. Its raw dumps and failing `fixtures-f32/report.json` are preserved.
Pinned ggml `kernels/mul_mm.metal:851` instantiates
`kernel_mul_mm_f32_f32` using half operands and `simdgroup_half8x8`.
Changing weight storage does not change those matrix operands to F32.
The permitted F32/CPU graph/layout diagnostic passes all 224 checkpoints on
the same eight fixtures, with exact speech tokens (`fixtures-f32-cpu/report.json`).
Its worst NRMSE is 0.00000685889 and minimum cosine is 0.999999999976.
It is a separate test; it cannot
relabel this failed Metal comparison or replace the primary F16/Metal gate.

F16 conversion was independently repeated as
`models/gigaam-600m-F16-candidate2-repro.gguf`; `conversion-repro.log` records
the identical SHA-256. F32 diagnostic conversion preserves exactly the same
logical weight values. Full all-block/language and packaging reproduction
gates are recorded above.

The new maintained-build whole-input head experiment measures a 0.844%
reduction in summed recording medians, with bootstrap mean-delta interval
[-2.431, -1.660] ms. Unlike the earlier preserved research run, this interval
does not cross zero. Both results are retained. This remains a whole-input
diagnostic, without stock25/package optimization acceptance. The selected
shipping host head and immutable package manifest are unchanged. The head
report identifies its original postprocessing recovery and leaves the original
uncaptured common cold-load duration unknown; primary cold load is measured
independently in the final F16 corpus benchmark.

## Verification entry points

Use the exact Python/package pins and command examples in
`Vendor/transcribe-native/README.md`. Each long command runs through
`tools/run.py`; adjacent `.process.json` files preserve argv, exit status and
elapsed time. Builds use two jobs, inference four threads, one heavy job at a
time. The diagnostic suite uses `TRANSCRIBE_ENABLE_VALIDATION_HOOKS=ON`; the
release framework compiles these hooks out.

The remaining required external distribution gate is actual execution on
macOS 15 arm64: packaged C/Swift Metal load/run/cancel/reuse, resources and ABI.
This Mac runs 26.6.2, so that gate is not verified here. Representative Metal
device/library/backend/OOM failure paths and the F32 precision split have now
been tested and reviewed; they are not pending. Optional Q8 remains unavailable: regeneration, integrity
metadata and maintained-candidate numerical/reproducibility work are not done.
Its native research quality misses the unchanged non-regression rule (121 vs
119 word edits, 376 vs 375 character edits). ADR-0013 remains proposed. No
accepted rollback pair has been invented. The dependency update gate also
requires a digest of current converter/reference/tests/patch/license inputs,
so unchanged artifact bytes cannot reuse stale validation after tool changes.
Host-local acceptance does not authorize publication. Native package publication
requires `native_package.distribution_accepted=true`, not only the report's
`accepted` field. The independent static GGUF's content, conversion, quality and
license checks are recorded as `model_artifact.accepted=true`; that narrower
verdict neither verifies a native binary on macOS 15 nor authorizes publication
of the model. Model-only publication requires a separate explicit decision.

The final scenario review covers all 19 rows in the tasks coverage map. Every
row has executed automated coverage on the verified host. The clean-package
scenario remains incomplete for the minimum macOS 15 runtime; Q8 regeneration
is optional and unavailable. Strict OpenSpec and tracked/untracked maintained
file whitespace checks pass. No source patch, model, or canonical package byte
changed during final review.
