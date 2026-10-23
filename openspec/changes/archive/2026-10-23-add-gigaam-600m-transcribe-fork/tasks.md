## 0. Preserve completed research

- [x] 0.1 Preserve the existing source patch, 13 research scripts, source dependencies, license notice, environment versions, and checksums under `research/`. Keep detailed benchmark results, private audio/transcripts, weights, binaries, and tensor dumps in ignored local storage; summarize conclusions in implementation evidence.
- [x] 0.2 Record completed research and remaining promotion gaps in `research/README.md` and the design: 824 tensors/75 transforms, native F16/Q8 corpus benchmarks, sampled numerical checks, 27/27 matched-F32 whole-input text agreement, and the inconclusive 81-pair CPU/GPU head A/B. These checkboxes acknowledge preservation and research completion only; they do not complete the production tasks below.

## 1. Freeze contracts and automated fixtures

- [x] 1.1 Record pinned upstream/fork/ggml/model/reference/converter inputs, supported macOS target, current research evidence, patch ownership, and artifact manifest schema. Audit original license texts and derived-checkpoint redistribution provenance before accepting distributable artifacts.
- [x] 1.2 Add converter/loader contract tests for exact tensor accounting, inverse layout transforms, vocabulary/blank identity, profile/version validation, missing or corrupt tensors, and malformed metadata before implementing the profile.
- [x] 1.3 Add deterministic reference export and numerical comparison fixtures for frontend, subsampling, each encoder block, logits, CTC blank/repeat collapse, and short multilingual speech. Match logical weight values and documented activation arithmetic; record storage/compute precision separately. Implement the design's numerical gates and report failures by stage.
- [x] 1.4 Add long-input parity fixtures below/at/above the old window boundary, cross-boundary speech, and the longest corpus item. Pin the selected stock25 retained/context spans in the primary reference/native evaluation metadata, add real-repetition/blank-transition boundary cases, and fail mismatched-policy comparisons. Retain whole-input diagnostic fixtures separately.
- [x] 1.5 Add direct C-interface tests for capabilities/defaults, unsupported options, silence/invalid audio, required-Metal success/failure, cancellation/partial-result ownership, resource release, and successful model reuse after an aborted or failed request.
- [x] 1.6 Add evaluation-tool tests using a synthetic corpus that enforce exact full-corpus membership, digest validation, frozen normalization/policy hashes, edit counts/alignments, acceptance failures, and separate F16/Q8/reference identities. Do not put private audio or transcript text into Git.

## 2. Add the native checkpoint profile

- [x] 2.1 Promote `research/scripts/convert_mlx.py` into the offline converter and versioned multilingual GGUF metadata. Parameterize research paths and validate profile/configuration values rather than rewriting the proven tensor mapping. Verify all tensor transforms and preserve source license/digest provenance; produce deterministic F16 and F32 diagnostic artifacts.
- [x] 2.2 Promote the existing parameterized-encoder prototype into an isolated multilingual profile and validated loader/capability metadata, starting from the preserved patch and converter. Complete checkpoint-derived language metadata and preserve existing v3 profiles. Implement only the frontend/configuration/layout changes identified by failing parity fixtures.
- [x] 2.3 Make F16 with the measured stock25 planner the normal supported profile: at most 25 seconds including context, up to 2 seconds context per side, retained encoder-frame stitching, one CTC collapse, exact coverage and explicit resource errors. Remove reliance on research environment flags from the supported path. Retain whole-input only for diagnostics and preserve upstream v3 behavior.
- [x] 2.4 Preserve the existing C interface's status/ownership/default contracts; implement truthful option validation, silence/invalid-input behavior, cooperative abort checkpoints, and model reuse after failure/cancel.
- [x] 2.5 Enforce a required-Metal encoder and report requested/actual stage placement and model/runtime identities. Establish the host frontend and CTC projection/search baseline with separate timing. Test encoder graph placement as well as device selection, including absent kernels/device and backend failure; keep head placement explicit for the A/B experiment.
- [x] 2.6 Pass the floating numerical and decoded-output fixture gates with saved per-stage comparisons before evaluating a quantized candidate. Investigate mismatches without weakening thresholds to match observed WER.

## 3. Establish full-corpus quality and performance

- [x] 3.1 Freeze the accepted 27-recording snapshot, current scorer, term-spelling aliases, hesitation policy, and unclear-marker treatment by digest. Reuse preserved whole-input evidence and add the missing MLX F32 stock-window oracle with the same F16-valued weights, frontend, retained/context spans, window-local positions, frame selection and one stitched CTC collapse. Preserve default MLX F16-activation results as a separate quality comparator rather than the parity oracle.
- [x] 3.2 Run the maintained fork F16 stock25 profile on the complete snapshot and require base-normalized transcript equality to the matched-window floating oracle and the frozen research F16-stock25 outputs for every recording. Save raw outputs, per-recording/aggregate WER/CER/edit alignments, all diagnostic protocols, backend proof, and pass/fail reasons.
- [ ] 3.3 Reuse the preserved Q8 conversion command, precision map and measured artifact as research evidence; regenerate with pinned tooling only when producing or validating the maintained candidate. Test conversion reproducibility and compare Q8 numerical error as diagnostics without treating MLX INT8 as its format equivalent.
- [x] 3.4 Run native Q8 on the complete same snapshot. Enforce per-recording base word/character edit-count non-regression against accepted F16 and aggregate WER/CER non-regression under every declared protocol. Record Q8 as accepted or explicitly unavailable/experimental with failing checks. A documented failed Q8 evaluation completes this optional-variant investigation without blocking accepted F16; do not replace a failed comparison with historical MLX results.
- [x] 3.5 Measure paired cold load, repeated warmed inference, timing distribution/median/real-time factor, and peak memory with the same machine and repetition policy. Include the longest input and all failures; remove tensor-dump overhead from reported inference timings. Measure the supported F16 stock25 path and label whole-input/GPU-head diagnostics separately. Do not require repeating unchanged completed research as if it had never run.
- [x] 3.6 Carry forward the completed research Metal-head A/B code/evidence and reproduce applicable checks against the maintained fork's exact build. Preserve identical weights, inputs, options, and the full 27-recording snapshot. Save tensor/output parity, every WER/CER protocol, head/transfer/synchronization and end-to-end timings, memory, paired distributions, and run-order/noise evidence. Research completion alone does not complete production verification.
- [x] 3.7 Record the host-head baseline and its measured decision in the package manifest: the current end-to-end confidence interval crosses zero. Adopt Metal projection only if later evidence passes parity/quality gates and demonstrates repeatable end-to-end improvement beyond measured noise. Re-run applicable package/regression gates on the selected path without blocking accepted F16 on an unsuccessful optimization.

## 4. Package and preserve upstream compatibility

- [x] 4.1 Define and pass clean macOS arm64 library-only and library-plus-required-converter/quantizer build jobs. Resolve the required `wav.h` target dependency if that tool is in the supported matrix; distinguish unrelated upstream target failures from passing targeted builds.
- [x] 4.2 Produce the local versioned native library/XCFramework, C headers/module map, Metal resources, license notices, and content manifest. Build a minimal C client and Swift import client without changing VoicePen application dependency wiring.
- [ ] 4.3 Run the package clients outside the source checkout without Python/MLX runtime dependencies. Exercise capability query, required-Metal load/run/cancel/free, missing resource, incompatible interface, and altered-checksum cases at the supported deployment target.
- [x] 4.4 Rebuild conversion and packaging twice from pinned inputs. Require identical model digests and package contents; document compiler/signing/UUID binary variation. Exercise rejecting a bad candidate and restoring the known-good package/model pair.
- [x] 4.5 Run all four existing GigaAM v3 profile regression fixtures, affected shared loader/frontend/backend fixtures, and the upstream native test suite. Preserve pre-extension loading, outputs, capabilities, and error contracts.
- [x] 4.6 Add the dependency-update gate that reruns applicable numerical, full-corpus, interface, package, license, and existing-family checks whenever runtime/model/converter/toolchain inputs change. Document patch review, upstream contribution candidates, and rollback without publishing artifacts.

## 5. Review and handoff

- [x] 5.1 Run `openspec validate add-gigaam-600m-transcribe-fork --strict` and `git diff --check`; review every scenario against the coverage map and report exact native build/test/evaluation commands and unaccepted variants.
- [ ] 5.2 Review ADR-0013 and the complete evidence before accepting a native dependency pin. Leave hosting, publication, VoicePen integration, new model defaults, and Meeting behavior to separately authorized work. Sync the new capability before archiving after implementation completes.

This plan changes no app-target behavior. `make test` and `make build` are not verification of a documentation-only proposal or a replacement for the fork's native tests. Run them if later work changes VoicePen production behavior or app-target wiring, which requires its own scoped spec change.

## Scenario coverage map

Coverage below maps scenarios to automated tasks. Actual passing, failing and pending evidence is recorded in `implementation-evidence.md`; a checked investigation task does not accept an unavailable precision variant. The native fork owns C/C++ behavior tests, offline tooling owns numerical/evaluation tests, and the isolated Swift client owns import/package compatibility checks.

| Spec scenario | Automated coverage tasks |
| --- | --- |
| Convert the pinned floating checkpoint | 1.2, 2.1, 4.4 |
| Reject an inconsistent artifact | 1.2, 2.1, 2.2 |
| Compare short speech with the floating reference | 1.3, 2.6 |
| Compare long speech with the floating reference | 1.4, 2.3, 2.6, 3.1, 3.2 |
| Run the primary profile without research overrides | 1.5, 2.3, 2.5, 3.2, 4.3 |
| Speech and repetitions cross a window boundary | 1.4, 2.3, 3.1, 3.2 |
| Evaluate a native precision candidate | 1.6, 3.1, 3.2, 3.4, 3.5 |
| A precision candidate fails acceptance | 1.6, 3.2, 3.4 |
| Required Metal is available | 1.5, 2.5, 4.3 |
| Required Metal cannot execute | 1.5, 2.5, 4.3 |
| Compare CTC projection placement | 3.6, 3.7 |
| Inspect profile capabilities | 1.5, 2.2, 2.4, 4.3 |
| Request an unsupported option | 1.5, 2.4 |
| Process silence and invalid audio | 1.3, 1.5, 2.4 |
| Cancel and reuse a model | 1.5, 2.4, 4.3 |
| Build and consume a clean package | 4.1, 4.2, 4.3, 4.4 |
| Validate or roll back a dependency artifact | 1.1, 4.3, 4.4, 4.6 |
| Exercise existing profiles after the extension | 4.5 |
| Evaluate an upstream update | 4.6 |
