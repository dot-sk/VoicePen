# GigaAM integration and local acceptance

GigaAM Multilingual 600M F16 uses the isolated `VoicePenGigaAM` framework.
Whisper remains the recommended model and continues to use whisper.cpp.
The GigaAM profile recognizes Russian, English, Kazakh, Kyrgyz and Uzbek
automatically with greedy CTC. Meeting timecodes and speaker labels use its
aligned CTC tokens and the existing local diarizer when those options are
enabled; the native backend still reports no direct timestamp result. Dictionary
replacements still apply after recognition. The app keeps
saved Whisper language, decoding and Meeting preferences for switching back.

## Delivery state

The exact F16 package/model pair is accepted for local use on the tested Apple
M1 Max with macOS 26.6.2. General native distribution acceptance remains open
because actual macOS 15 execution has not been verified. The canonical native
manifest retains its candidate status; the separate host-local report records
the reviewed evidence without changing the tested binary.

The model and license archive are published in
[the immutable GigaAM asset release](https://github.com/dot-sk/VoicePen/releases/tag/model-assets-gigaam-600m-f16-v1).
Both public downloads passed complete size and SHA-256 readback. The bundled
manifest now offers GigaAM Multilingual 600M F16 alongside Whisper, which remains
recommended. Choose GigaAM in Model settings and confirm Download Model to
install its 1.17 GB weights. Recognition then works offline. This does not
publish a native framework or application update.

`Vendor/transcribe.spm/candidate-manifest.json` records the exact local native
package. Both SwiftPM and the Xcode app consume the same prepared XCFramework.
`scripts/prepare-gigaam-runtime.sh` compares that manifest and validates all
file hashes and symlinks before copying ignored artifacts. The explicit
`--allow-unaccepted-candidate` flag permits local evaluation only.

Prepare local model publication inputs without compiling Core ML or publishing:

```sh
bash scripts/build-model-assets.sh --gigaam MODEL_GGUF OUTPUT_DIR PACKAGE_DIR
```

The output contains the GGUF, deterministic license/provenance archive, digest
list, review plan and model-manifest entry. The dedicated publisher verifies
both public downloads before emitting a verified entry for activation.
See the exact assets, coordinates and commands in
[the publication review](model-assets/GIGAAM-600M-F16.md).

## Automated checks

`make test` covers capability policy, captured routing, dictionary behavior,
shared loading, cancellation, leases, generation guards, verified local
installation, existing Whisper behavior, and Meeting timing fallback decisions.
`make build` checks app wiring. `make integration-test` checks the hosted app,
framework embedding, local installation and both native load orders.
Prepare isolated fixtures with `scripts/prepare-gigaam-hosted-fixtures.sh`.
Its Whisper fixture contains only the GGML weights, so the coexistence test
uses the Metal encoder and does not load or compile a Core ML companion.
The production Whisper installation policy is unchanged.

Xcode normally overrides framework lookup to its build-products directory.
The ordinary hosted check compares loaded and embedded GigaAM payloads.
To require the actual embedded framework in a copied app, first run
`make integration-test INTEGRATION_TEST_ACTION=build-for-testing`, then use
`Tools/GigaAMIntegration/prepare_hosted_run.py` with that generated xctestrun,
the built app and a new temporary output directory. Execute its result with
`make integration-test INTEGRATION_TEST_ACTION=test-without-building
INTEGRATION_TEST_RUN=ABSOLUTE_RELOCATED_XCTESTRUN`. This test requires the
framework path inside the copied app, a matching embedded digest, bounded
execution and a runtime PATH containing only `/usr/bin:/bin`.

`scripts/run-gigaam-coexistence.sh` separately builds and runs a relocated C
consumer with both native frameworks, both load orders, cancellation/reuse,
private-symbol/class checks and no global Metal resource override.

Run the production adapter on the frozen saved ASR inputs with:

```sh
VOICEPEN_GIGAAM_EVALUATION_DATASET=ABSOLUTE_DATASET_JSON \
VOICEPEN_GIGAAM_MODEL=ABSOLUTE_GGUF \
VOICEPEN_GIGAAM_MODEL_ENTRY=ABSOLUTE_MODEL_ENTRY_JSON \
VOICEPEN_GIGAAM_OUTPUT=ABSOLUTE_PRIVATE_ADAPTER_OUTPUT_JSON \
make test TEST_FILTER=GigaAMOfflineEvaluationTests.productionAdapterRunsFrozenPreprocessedInputs

uv --native-tls run --no-project --python 3.13 \
  --with soundfile==0.14.0 --with jiwer==4.0.0 \
  Tools/GigaAMIntegration/score_adapter.py \
  --dataset DATASET_JSON --adapter ADAPTER_OUTPUT_JSON \
  --native EXACT_NATIVE_EVALUATION_JSON --output PRIVATE_REPORT_JSON
```

The Swift test validates audio hashes, calls the production adapter directly
without another preprocessing pass, and stores raw text before post-filtering
or dictionary replacement. The scorer verifies the frozen policy digests,
requires per-file base-normalized native equality, and reports all four frozen
WER/CER protocols. Outputs stay in ignored private storage.

The candidate.2 local adapter run passed all 27 recordings with complete sample
counts and stable raw output over three warm calls per recording. Its model SHA
is `06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae`;
its framework SHA is
`f2fe97a8a947483484d60c8af5e4179b26355387c2765cf83d62a7a83dbb3330`.
Base WER/CER was 8.084239% / 4.298487%; alias-normalized WER/CER was
5.513955% / 1.905637%. The hesitation-filtered variants had the same scores.
The isolated test measured cold load at 4.370 seconds, median warm adapter time
at 0.486 seconds, and median adapter overhead above reported native compute at
0.224 seconds, with 2,530,836,480 bytes peak process RSS. These include the
Swift test host and file decoding; they are not a UI latency guarantee.
Private evidence is in
`.local/asr-quality/gigaam-app-adapter-v3/evaluation-complete.json` and
`adapter-corpus-complete.json`. This is adapter evidence for the exact candidate,
not native-package acceptance or delivery approval.

`Tools/GigaAMIntegration/prepare_stress.py` creates a 120-minute master with
the same saved speech at the start and end and silence between them. The
optional `VOICEPEN_GIGAAM_STRESS_INPUT`, `VOICEPEN_GIGAAM_STRESS_SPEECH` and
`VOICEPEN_GIGAAM_STRESS_OUTPUT` environment variables enable its production
adapter test. It requires both speech occurrences, records peak RSS and wall
time, and reports resource/runtime failures explicitly. A two-hour fixture is
separate evidence from the ordinary corpus, whose maximum is 81.152 seconds.
The candidate.2 run completed the two-hour request in 113.454 seconds, with
4,348,739,584 bytes peak process RSS and both speech anchors preserved.
`Tools/GigaAMIntegration/check_stress.py` verified continuous retention across
343 native windows through all 180,000 encoder frames, each bounded to 25
seconds. This sparse-speech stress fixture establishes duration and memory
coverage; it is not a two-hour continuous-speech quality benchmark.

## Ownership and rollback

GigaAM requests share tracked loads by model version, digest and package ID.
A prepared request keeps a context lease. A cancellation token belongs to one
request; canceled queued work cannot cancel another request. The shared native
gate prevents expensive Whisper and GigaAM work from overlapping. Native work
stays tracked until it returns, including after a UI timeout. Model deletion
waits for an unused native context and removes only that model's directory.

Routine diagnostics contain model/package identities, effective options and
stage/timing information. They do not contain audio or transcript content.

Roll back the application and native package together using the previous
accepted wrapper manifest, GGUF digest and distributable model manifest.
Preserve user history and installed model files. An older app follows its
existing unsupported-selection recovery. No settings schema migration or
automatic model migration is introduced.
