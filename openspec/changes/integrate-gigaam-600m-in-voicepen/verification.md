# Local integration evidence

Status: the exact candidate.2 pair is accepted for local use on the tested Mac.
The model and license archive were published with user authorization on
2026-10-19, verified by public readback, and activated in the bundled selector.
Native distribution acceptance for macOS 15 remains unverified; no native
framework or application update was published.

## Exact local inputs

- Runtime package: `voicepen-gigaam-600m-0.1.0-candidate.2`.
- Runtime binary SHA-256:
  `f2fe97a8a947483484d60c8af5e4179b26355387c2765cf83d62a7a83dbb3330`.
- Canonical package manifest SHA-256:
  `7738da1d56246941906071a4177dd5586dd02c5560df4d97eb6fee72b52626e8`.
- Model SHA-256:
  `06b1224edb7eb9b9b797c5d25539b6aa852e6a069fbfdce706760a3135e26cae`.
- Model size: 1,172,222,176 bytes.
- Package provenance: `Vendor/transcribe.spm/candidate-manifest.json`.
- Local publication inputs:
  `.local/asr-quality/gigaam-app-publication-inputs-v3/`.
- Frozen ASR snapshot:
  `c49eabd7e9a517bb85185f61c7b182af127071d3eaaa8ec49f8fc624fdec4561`.

## Completed checks

- `make test`: 693 tests in 77 suites passed before the complete-read fix.
  Log: `/tmp/gigaam-app-unit-v3.log`.
- Complete-read regression was red on all four synthetic frame counts before
  the fix. The focused `make test
  TEST_FILTER='GigaAMAudioReadTests|GigaAMLifecycleTests|GigaAMIntegrationTests'`
  then passed 11 tests in three suites. Logs:
  `/tmp/gigaam-read-before.log`, `/tmp/gigaam-read-after.log`.
- `make test TEST_FILTER=productionAdapterRunsFrozenPreprocessedInputs` passed
  against candidate.2 after the fix. Each of the 27 recordings had its full
  declared sample count, one first-shape call and three stable warm calls.
  Log: `/tmp/gigaam-app-corpus-complete-v3.log`.
- `Tools/GigaAMIntegration/score_adapter.py` found 27/27 raw adapter/native
  base-normalized matches and no failures. Base WER/CER:
  8.084239% / 4.298487%; aliases: 5.513955% / 1.905637%. The two
  hesitation-filtered protocols had the same corresponding scores. Policy and
  reference hashes were unchanged. Report:
  `.local/asr-quality/gigaam-app-adapter-v3/evaluation-complete.json`.
- Cold load: 4.370 s; median warm adapter: 0.486 s; median adapter overhead
  above native compute: 0.224 s; peak test-process RSS: 2,530,836,480 bytes.
  These measurements include Swift/file IO, and do not promise UI latency.
- Strict change validation, `git diff --check`, shell syntax checks and scoped
  Swift formatting checks passed.
- The bounded two-hour production-adapter run completed in 113.454 seconds
  (118.025 seconds including setup), submitting all 115,200,000 samples.
  It retained both eight-word speech anchors, produced text only, and reached
  4,348,739,584 bytes peak process RSS. `check_stress.py` verified all 343 native
  windows had continuous retention from frame 0 through 180,000 and respected
  the 25-second encoded-window bound. Evidence:
  `.local/asr-quality/gigaam-app-adapter-v3/meeting-120min-result.json`,
  `meeting-120min-coverage.json`, `/tmp/gigaam-app-stress-v3.log`.
- Plain `make build` passed after narrow Xcode 27 actor/region-isolation
  compatibility fixes. Log: `/tmp/gigaam-app-build-7.log`. App:
  `/private/tmp/VoicePenDerivedData/Build/Products/Debug/VoicePen.app`.
  Its embedded GigaAM binary digest matches the exact candidate.2 runtime;
  app linkage includes both `@rpath/VoicePenGigaAM.framework` and Whisper.
- `make test
  TEST_FILTER='WhisperCppModelDownloadClientTests|retryCapturesNewRecognizerCapabilitiesAndMetadata'`
  passed all three cases. The retry switches from failed text-only GigaAM to
  Whisper and captures its timing, VAD, glossary and history identity anew.
- `make integration-test INTEGRATION_TEST_ACTION=build-for-testing` and
  `make integration-test INTEGRATION_TEST_ACTION=test-without-building
  INTEGRATION_TEST_RUN=/private/tmp/voicepen-gigaam-relocated-v3/relocated.xctestrun`
  passed all three hosted cases in 27.522 seconds. The app/test bundle was
  copied out of DerivedData; the strict loaded-image path and embedded digest
  check passed. Both native models produced stable, nonempty output in both
  load orders. The fixture uses Whisper Metal without a Core ML companion,
  isolated model/audio paths, and a runtime PATH without Python/MLX.
  Log: `/tmp/gigaam-app-hosted-relocated.log`; result:
  `/tmp/VoicePenDerivedData/Logs/Test/Test-VoicePen-2026.10.19_18-09-52-+0400.xcresult`.
- Relocated C consumer passed both load orders with both models alive,
  identical per-backend raw outputs, GigaAM abort/reuse, hidden private ggml
  exports and no native Objective-C resource classes. Current Whisper's binary
  also has no `GGMLMetalClass`; the check permits absence and requires Whisper
  ownership if the class exists. Both backends used Metal; native logs report
  embedded kernel sources. Evidence:
  `/private/tmp/voicepen-gigaam-combined-v3b/result.json`, `run.log`,
  `exports.txt`, `objc-classes.txt`, `dependencies.txt`.
- Final plain `make test` passed 697 tests in 78 suites in 17.084 seconds,
  plus the existing 11 ASR tooling tests and strict main-spec validation.
  Log: `/tmp/gigaam-app-unit-final.log`.
- A separate APFS-cloned app copy passed
  `codesign --force --deep --strict --sign -` and
  `codesign --verify --strict --deep --verbose=2`, including GigaAM, Whisper,
  Sparkle and their nested code. Copy:
  `/private/tmp/voicepen-gigaam-signing-v3/VoicePen.app`.
  The corpus/framework pin and previously tested relocated app were unchanged.
  This checks local ad-hoc signing, not notarization or a signed release.

The earlier actual-count gate deliberately failed on six recordings (18 warm
call assertions) despite matching raw text. `AVAudioFile.read` returned a short
buffer before EOF. The existing complete-frame reader now handles this path;
the failing evidence remains in `/tmp/gigaam-app-corpus-v3.log` and
`.local/asr-quality/gigaam-app-adapter-v3/adapter-corpus.json`.

## Remaining checks and delivery

- Actual native runtime execution on macOS 15 before claiming that platform's
  distribution acceptance. Host-local acceptance is recorded for macOS 26.6.2.
- Sync deltas only after implementation acceptance; do not archive this change
  or publish a signed app as part of local verification.

The predecessor has now recorded host-local acceptance in
`.local/asr-quality/native-gigaam-600m/host-local-acceptance.json`
(SHA `f83c682dc7a37f2e1b8be461ab2925f72a0e8d479846e55871e4ba7917983b40`).
It separately accepts the model artifact and the native package on this host;
native distribution acceptance remains false pending actual macOS 15 runtime
verification. Canonical binary/model/manifest hashes have not changed.

Model-only publication is fully prepared as two assets, with exact coordinates,
sizes, digests, license archive and commands in
[the publication review](../../../Docs/model-assets/GIGAAM-600M-F16.md).
The legacy publisher dispatches `--gigaam` to a dedicated fail-closed command;
its default is offline dry-run. Local archive/schema, immutability and simulated
readback checks passed. The new release/tag were absent before publication.
Both assets are now published in `model-assets-gigaam-600m-f16-v1`, release ID
`417433070`, and public GET/size/SHA verification passed. Task 1.3 is complete.

The first hosted attempt stopped during a first Core ML companion load, without
changing installed models. Only the owned test app/controller were stopped.
The final isolated fixture is bin-only and exercises Whisper Metal instead.
Normal Xcode hosted lookup may select a build-products framework; that mode
checks embedded/loaded payload equality. The relocated run additionally removes
those search paths and requires the actual framework inside its copied app.
No Core ML compilation command was run. No production app process, settings,
database or installed model was modified. The separately authorized new
model-only release contains precisely the GGUF and license/provenance ZIP;
existing application/model releases were not changed.

## Publication and selector activation

- User authorized publication of the prepared model and license archive.
- Release:
  https://github.com/dot-sk/VoicePen/releases/tag/model-assets-gigaam-600m-f16-v1.
- Exact model and notices sizes/digests match the publication plan. Public
  downloads passed full SHA-256 readback through `--verify-only`; receipt and
  verified model entry are in the private publication-input directory.
- The initial publisher stopped on GitHub's draft-by-tag 404 after upload.
  Both files were inspected by release ID before publishing that same draft.
  The publisher now finds existing drafts and uses numeric IDs for new draft
  verification/publication. Offline regression checks cover this real path.
  Logs: `/private/tmp/gigaam-publication-20261019.log`,
  `/private/tmp/gigaam-public-readback-20261019.log`,
  `/private/tmp/gigaam-publication-regression-20261019.log`.
- `VoicePen/Resources/model-manifest.json` includes the verified GigaAM entry
  without changing the recommended Whisper entry. The manifest contract test
  failed before activation and passed in the full unit run after activation.
  `make test` passed 697 tests in 78 suites, plus 11 tooling tests and strict
  main-spec validation. Logs: `/private/tmp/gigaam-manifest-before.log`,
  `/private/tmp/gigaam-activation-unit-20261019.log`.
- `make build` passed with the active GigaAM entry. Log:
  `/private/tmp/gigaam-activation-build-20261019.log`.
- `make integration-test` passed after activation, including selection of the
  actual bundled GigaAM entry in the app host, local installation/capability
  state, both native load orders, and existing app-host coverage. Log:
  `/private/tmp/gigaam-activation-hosted-20261019.log`.
- The separate ready-to-open copy is
  `/private/tmp/voicepen-gigaam-ready-20261019/VoicePen.app`. Ad-hoc deep signing
  and strict signature verification passed. Its relocated test-without-building
  run passed all four hosted tests, including real bundled selection and both
  native models, while requiring the GigaAM framework inside the copied app.
  Logs: `/private/tmp/gigaam-activation-sign-20261019.log`,
  `/private/tmp/gigaam-activation-relocated-20261019.log`.
- Strict change validation, `git diff --no-ext-diff --check`, publisher shell
  syntax, publication regression fixtures, and strict formatting of the two
  modified Swift test files passed after activation. No native code or model
  weights changed, so the accepted full-corpus evidence retains its exact pins.

## Application change files

Build and package wiring:
`Makefile`, `Package.swift`, `VoicePen.xcodeproj/project.pbxproj`,
`Vendor/transcribe.spm/Package.swift`, `Vendor/transcribe.spm/README.md`,
`Vendor/transcribe.spm/candidate-manifest.json`,
`Vendor/transcribe.spm/.gitignore`.

Application composition/settings:
`VoicePen/App/AppController.swift`, `VoicePen/App/AppModelRuntimeStore.swift`,
`VoicePen/App/SettingsViews.swift`, `VoicePen/App/TranscriptTextEditor.swift`,
`VoicePen/Core/VoicePenStatusMenuModel.swift`, `VoicePen/VoicePenApp.swift`.
The transcript shape change is only a Swift 6 isolation annotation.

Pipelines:
`VoicePen/Features/Meetings/MeetingAudioFileIO.swift`,
`VoicePen/Features/Meetings/MeetingDiarization.swift`,
`VoicePen/Features/Meetings/MeetingPipeline.swift`,
`VoicePen/Features/Pipeline/DictationPipeline.swift`.
The diarization protocol change is only Swift 6 compatibility.

Transcription service files under `VoicePen/Features/Transcription/`:
`GigaAMModelDownloadClient.swift`, `GigaAMNativeContext.swift`,
`GigaAMTranscriptionClient.swift`, `NativeExecutionGate.swift`,
`RecognitionCapabilities.swift`, `TranscriptionExecutionDiagnostics.swift`,
`ModelArtifactStatus.swift`, `ModelDownloadClient.swift`, `ModelManifest.swift`,
`ModelWarmupClient.swift`, `RoutingModelDownloadClient.swift`,
`RoutingTranscriptionClient.swift`, `TranscriptionClient.swift`,
`WhisperCppContext.swift`, `WhisperCppModelDownloadClient.swift`,
`WhisperCppTranscriptionClient.swift`.

Tests:
`VoicePenTests/App/AppControllerTests.swift`,
`VoicePenTests/Meetings/MeetingPipelineTests.swift`,
`VoicePenTests/Pipeline/DictationPipelineTests.swift`,
`VoicePenTests/TestDoubles/FakeAudioPreprocessingClient.swift`,
`VoicePenTests/TestDoubles/FakeTranscriptionClient.swift`,
`VoicePenTests/Transcription/RoutingModelDownloadClientTests.swift`,
`VoicePenTests/Transcription/GigaAMAudioReadTests.swift`,
`VoicePenTests/Transcription/GigaAMDownloadTests.swift`,
`VoicePenTests/Transcription/GigaAMIntegrationTests.swift`,
`VoicePenTests/Transcription/GigaAMLifecycleTests.swift`,
`VoicePenTests/Transcription/GigaAMOfflineEvaluationTests.swift`,
`VoicePenTests/Transcription/GigaAMOrderedWarmupProbe.swift`,
`VoicePenIntegrationTests/GigaAMHostedIntegrationTests.swift`.

Asset and verification tooling:
`scripts/build-model-assets.sh`, `scripts/prepare-gigaam-runtime.sh`,
`scripts/prepare-gigaam-model-assets.sh`,
`scripts/prepare-gigaam-hosted-fixtures.sh`,
`scripts/run-gigaam-coexistence.sh`,
`Tools/GigaAMIntegration/coexistence.c`,
`Tools/GigaAMIntegration/score_adapter.py`,
`Tools/GigaAMIntegration/prepare_stress.py`,
`Tools/GigaAMIntegration/check_stress.py`,
`Tools/GigaAMIntegration/prepare_hosted_run.py`.

Documentation/contracts:
`Docs/adr/2026-10-19-coexisting-local-asr-runtimes.md`,
`Docs/gigaam-integration.md`, this verification report, and this change's
`design.md`, `tasks.md`, `specs/local-transcription-model-handling/spec.md`.
Other pre-existing dirty files and the native predecessor remain separately
owned; this list does not attribute their changes to app integration.
