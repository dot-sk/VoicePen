# Audio Capture And Transcription Architecture

This document is a C4-inspired component view of the current VoicePen audio
implementation. Product behavior remains defined by the specs; this page maps
that behavior to runtime objects, local files, queues, and model boundaries.

Related behavior and decisions:

- [Push-To-Talk Dictation Pipeline](../Specs/2026-05-02-push-to-talk-dictation-pipeline.md)
- [Meeting Recording Mode](../Specs/2026-05-05-meeting-recording-mode.md)
- [Audio Settings And Voice Processing](../Specs/2026-05-05-audio-settings-voice-processing.md)
- [Meeting Recording Capture And Privacy ADR](adr/2026-05-05-meeting-recording-capture-and-privacy.md)

## System Context

VoicePen is one local macOS process. Audio capture, audio processing, ASR, and
optional diarization run on the Mac. The transcription path does not call a
cloud service.

```mermaid
flowchart LR
    user["User"]
    target["Frontmost macOS application"]
    macos["macOS<br/>CoreAudio, AVFoundation, AudioToolbox"]
    models["Local models<br/>RNNoise, Whisper, Silero VAD, SpeakerKit"]
    files["Local files<br/>temporary, recovery, saved recordings"]
    database["Local SQLite<br/>settings and history"]

    subgraph app["VoicePen.app"]
        surfaces["SwiftUI and AppKit surfaces<br/>hotkey, overlay, Meetings UI"]
        controller["AppController<br/>composition root and app facade"]
        dictation["DictationPipeline"]
        meetingStore["MeetingRecordingStore<br/>Meeting lifecycle state"]
        meeting["MeetingPipeline"]
        capture["Audio capture components"]
        processing["Audio processing components"]
        transcription["RoutingTranscriptionClient<br/>WhisperCppTranscriptionClient"]
        history["VoiceHistoryStore<br/>MeetingHistoryStore"]
    end

    user --> surfaces
    surfaces --> controller
    controller --> dictation
    controller --> meetingStore
    meetingStore --> meeting
    dictation --> capture
    meeting --> capture
    capture --> macos
    dictation --> processing
    meeting --> processing
    processing --> models
    dictation --> transcription
    meeting --> transcription
    transcription --> models
    dictation -. "result" .-> controller
    controller --> history
    meeting --> history
    history --> database
    capture --> files
    processing --> files
    dictation --> target
```

## Composition And Startup

`AppController.live()` is the composition root. It creates separate microphone
capture instances for dictation and Meetings, but shares the selected
transcription router and RNNoise denoiser.

```mermaid
flowchart TB
    launch["VoicePenApp launches"]
    compose["AppController.live()"]
    controller["AppController"]
    appStart["AppController.start()"]

    settings["AppSettingsStore"]
    voiceHistory["VoiceHistoryStore"]
    meetingHistory["MeetingHistoryStore"]
    paths["AppPaths"]

    rnnoise["RNNoiseAudioDenoiser<br/>one shared model instance"]
    dictationPreprocessor["Dictation LiveAudioPreprocessingClient<br/>RNNoise and silence trimming"]
    meetingPreprocessor["Meeting LiveAudioPreprocessingClient<br/>silence analysis and trimming"]
    meetingChunker["AVFoundationMeetingAudioChunker<br/>microphone RNNoise and timeline mixing"]

    whisper["WhisperCppTranscriptionClient actor<br/>cached WhisperCppContext"]
    router["RoutingTranscriptionClient<br/>selected model routing"]
    dictationPipeline["DictationPipeline"]
    meetingPipeline["MeetingPipeline"]
    meetingStore["MeetingRecordingStore"]

    load["Create directories and clean old temp files<br/>load config, settings, dictionary, and histories"]
    warmup["Warm installed Whisper model<br/>warm SpeakerKit when enabled"]
    permissions["Request microphone and accessibility permissions<br/>install Push-to-Talk hotkey"]

    launch --> compose
    compose --> paths
    compose --> settings
    compose --> voiceHistory
    compose --> meetingHistory
    compose --> rnnoise
    rnnoise --> dictationPreprocessor
    rnnoise --> meetingChunker
    compose --> meetingPreprocessor
    compose --> whisper
    whisper --> router
    router --> dictationPipeline
    router --> meetingPipeline
    dictationPreprocessor --> dictationPipeline
    meetingPreprocessor --> meetingPipeline
    meetingChunker --> meetingPipeline
    dictationPipeline --> controller
    meetingPipeline --> meetingStore
    meetingStore --> controller
    compose --> controller
    controller --> appStart
    appStart --> load
    load --> warmup
    load --> permissions
```

Important ownership details:

- Dictation uses RNNoise during offline preprocessing after capture.
- Meeting RNNoise runs inside the chunker only for microphone samples, before
  microphone and system audio are mixed. The raw captured source files and
  recovery copies remain unchanged.
- `MeetingPipeline` uses a separate preprocessor without RNNoise because the
  microphone has already been denoised by the chunker.
- Both pipelines create a `TranscriptionRequest` and use the same
  `RoutingTranscriptionClient`. The underlying actor reuses the loaded Whisper
  context for the selected model.

## Push-To-Talk Flow

The hotkey starts capture on key-down and stops capture and starts processing on
key-up. A UI command can call the same `AppController` facade methods.

```mermaid
flowchart TB
    down["Hotkey key-down"]
    start["AppController.startRecording()"]
    guard["Check runtime state, permissions, and installed model"]
    pipelineStart["DictationPipeline.start()"]
    gain{"Input gain boost enabled<br/>and no active Meeting capture?"}
    boost["CoreAudioDefaultInputGainController<br/>boost default input gain"]
    recorderStart["LiveAudioRecordingClient.startRecording()"]
    hal["CoreAudioMicrophoneCapture<br/>HAL Audio Unit"]
    callback["Serial microphone callback queue"]
    converter["PCMStreamConverter<br/>native format to 16 kHz multichannel Float32"]
    mixer["ActiveChannelMonoMixer<br/>select active channel and produce mono"]
    wav["AVAudioFile<br/>16 kHz mono Float32 WAV"]

    up["Hotkey key-up"]
    stop["AppController.stopRecordingAndProcess()"]
    recorderStop["Stop Audio Unit<br/>wait submitted callbacks and drain callback queue"]
    result["RecordingResult"]
    preprocess["LiveAudioPreprocessingClient"]
    denoise["RNNoiseAudioDenoiser<br/>best effort"]
    trim["AudioSilenceTrimmer<br/>reject no speech and trim edges"]
    request["TranscriptionRequest<br/>glossary and language<br/>options empty"]
    asr["RoutingTranscriptionClient"]
    whisper["WhisperCppTranscriptionClient<br/>WhisperCppContext"]
    filter["TranscriptionPostFilter"]
    normalize["DeveloperModeProcessor<br/>dictionary, aliases, TextOutputNormalizer"]
    insert["PasteboardTextInsertionClient"]
    history["AppController records VoiceHistoryEntry"]
    restore["Restore original input gain"]

    down --> start --> guard --> pipelineStart --> gain
    gain -- "yes" --> boost --> recorderStart
    gain -- "no" --> recorderStart
    recorderStart --> hal --> callback --> converter --> mixer --> wav

    up --> stop --> recorderStop
    wav --> recorderStop
    recorderStop --> result --> preprocess --> denoise --> trim --> request
    request --> asr --> whisper --> filter --> normalize --> insert --> history
    history --> restore
    stop -. "after success or failure" .-> restore
```

`CoreAudioMicrophoneCapture.stop()` is the synchronization boundary: after it
returns, no previously submitted callback can still write to the recording
session. This lets `LiveAudioRecordingSession` finish its `AVAudioFile` without
an additional queue or polling.

Push-to-Talk deliberately sends no VAD option to Whisper. RNNoise failure is
logged and falls back to the captured audio; a no-speech result ends without
transcription or insertion.

## Meeting Capture Flow

Starting a Meeting goes through `MeetingRecordingStore`, which owns the
UI-facing state, consent, permission checks, capture timeout, maximum-duration
monitor, cancellation, and processing timeout.

```mermaid
flowchart TB
    startCommand["Meetings UI or Command-R"]
    facade["AppController.startMeetingRecording()"]
    store["MeetingRecordingStore.start()"]
    preflight["Consent, microphone permission,<br/>system-audio source preflight, start timeout"]
    pipeline["MeetingPipeline.start()"]
    composite["CompositeMeetingRecordingClient.start()"]

    subgraph mic["Microphone source"]
        micSource["CoreAudioMicrophoneMeetingAudioSource"]
        micHAL["CoreAudioMicrophoneCapture<br/>HAL Audio Unit"]
        micQueue["Serial callback queue"]
        micStream["MeetingMicrophoneStream"]
        micConvert["PCMStreamConverter<br/>native rate to 16 kHz"]
        micMix["ActiveChannelMonoMixer<br/>active channel to mono"]
        micSink["MeetingAudioBufferFileSink"]
        micFile["ExtendedAudioFileWriter<br/>async 16 kHz mono Int16 WAV"]
        micSource --> micHAL --> micQueue --> micStream --> micConvert --> micMix --> micSink --> micFile
    end

    subgraph system["System-audio source"]
        systemSource["CoreAudioSystemOutputSource"]
        tapPlan["MeetingSystemAudioTapPlan<br/>all, selected, or excluded apps"]
        tap["CoreAudio process tap<br/>private aggregate device and IOProc"]
        systemQueue["Serial system-audio callback queue"]
        systemSink["MeetingAudioBufferFileSink"]
        systemFile["ExtendedAudioFileWriter<br/>async 16 kHz mono Int16 CAF"]
        systemSource --> tapPlan --> tap --> systemQueue --> systemSink --> systemFile
    end

    status["MeetingSourceStatus<br/>health and levels for both sources"]

    startCommand --> facade --> store --> preflight --> pipeline --> composite
    composite --> micSource
    composite --> systemSource
    micSink --> status
    systemSink --> status
    status --> store
```

The writer's client format is the callback/processing format. Its file format is
always 16 kHz mono Int16. `ExtAudioFileWriteAsync` performs the final file-side
conversion and uses Core Audio's internal asynchronous ring; VoicePen does not
maintain another realtime buffer queue.

Stopping preserves the last callback:

```mermaid
flowchart LR
    stop["Stop Meeting"]
    micStop["Stop microphone Audio Unit"]
    micDrain["Wait submitted microphone callbacks<br/>and drain callback queue"]
    systemStop["Stop IOProc and destroy<br/>aggregate device and process tap"]
    systemDrain["Drain system callback queue"]
    finish["MeetingAudioBufferFileSink.finish()"]
    dispose["ExtAudioFileDispose<br/>flush pending async writes"]
    recording["MeetingRecordingResult<br/>source chunks and source health"]

    stop --> micStop --> micDrain --> finish
    stop --> systemStop --> systemDrain --> finish
    finish --> dispose --> recording
```

On cancel, both writers are closed and their temporary files are deleted. On a
write or close failure, the sink keeps the first failure, deletes the invalid
file, and marks that source failed.

## Meeting Processing Flow

`MeetingPipeline.stopAndProcess()` first stops capture, then processes the
returned timeline. Processing is chunked into 60-second windows.

```mermaid
flowchart TB
    recording["MeetingRecordingResult<br/>raw microphone and system source chunks"]
    chunker["AVFoundationMeetingAudioChunker<br/>build 60-second timeline windows"]
    rnnoise["RNNoise on microphone samples only<br/>best effort, duration preserving"]
    mix["Emit source-only windows or mix overlaps<br/>clip mixed samples to the valid range"]
    chunks["16 kHz mono Int16 processing chunks<br/>plus MeetingAudioSourceSpan mapping"]
    archive["Optional SavedAudioArchive<br/>post-chunking audio"]

    loop["For each ordered chunk"]
    silence["LiveAudioPreprocessingClient<br/>detect silence and trim when timeline may move"]
    preserve{"Timecodes or diarization enabled?"}
    originalTimeline["Use the untrimmed processing chunk<br/>to preserve meeting-relative time"]
    trimmed["Use the trimmed chunk"]
    leveling{"Meeting voice leveling enabled?"}
    level["SystemVoiceLevelingProcessor<br/>dynamics and peak limiting, best effort"]
    options["TranscriptionOptions<br/>always VAD; timestamps when timecodes or diarization"]
    transcribe["Shared RoutingTranscriptionClient"]
    segments["Text and timestamped segments"]

    diarize{"Diarization enabled<br/>and ASR timestamps usable?"}
    fullTimeline["Rebuild full 16 kHz mono timeline<br/>without compacting speech regions"]
    speakerKit["SpeakerKitMeetingDiarizationClient"]
    format["MeetingTranscriptFormatter<br/>timecodes and speaker assignment"]
    save["MeetingHistoryStore<br/>completed, partial, or failed entry"]
    recovery["MeetingRecoveryAudioStore<br/>retryable original source audio"]
    cleanup["Delete temporary processing files"]

    recording --> chunker --> rnnoise --> mix --> chunks
    chunks -. "when enabled" .-> archive
    chunks --> loop --> silence --> preserve
    preserve -- "yes" --> originalTimeline --> leveling
    preserve -- "no" --> trimmed --> leveling
    leveling -- "yes" --> level --> options
    leveling -- "no" --> options
    options --> transcribe --> segments --> diarize
    diarize -- "yes" --> fullTimeline --> speakerKit --> format
    diarize -- "no" --> format
    format --> save
    recording --> recovery --> save
    save --> cleanup
```

The Meeting preprocessor still runs when the original timeline must be
preserved: its silence analysis decides whether to skip the chunk, while the
untrimmed file is sent to ASR so timestamps remain meeting-relative.

## Shared Transcription And VAD

Both pipelines use the same request object and routing boundary:

```mermaid
flowchart LR
    ptt["DictationPipeline<br/>options empty"]
    meeting["MeetingPipeline<br/>VAD plus conditional timestamps"]
    request["TranscriptionRequest<br/>audioURL, glossaryPrompt, language, options"]
    router["RoutingTranscriptionClient<br/>resolve selected ModelManifestModel"]
    client["WhisperCppTranscriptionClient actor<br/>load or reuse model context"]
    vadModel{"VAD requested and bundled<br/>Silero model exists?"}
    vadDecode["Whisper decode with Silero VAD"]
    ordinary["Ordinary Whisper decode"]
    retry{"VAD decode status nonzero?"}
    result["TranscriptionClientResult<br/>text, segments, model metadata"]
    error["TranscriptionError"]

    ptt --> request
    meeting --> request
    request --> router --> client --> vadModel
    vadModel -- "yes" --> vadDecode --> retry
    vadModel -- "no" --> ordinary
    retry -- "no" --> result
    retry -- "yes, exactly once" --> ordinary
    ordinary -- "success" --> result
    ordinary -- "failure" --> error
```

The VAD fallback belongs to `WhisperCppVoiceActivityDetection`: a missing model
causes one ordinary decode, while a failed VAD decode causes exactly one retry
without VAD. Push-to-Talk never requests VAD.

## Component Map

| Component | Responsibility | Main collaborators |
| --- | --- | --- |
| [`AppController`](../VoicePen/App/AppController.swift) | App facade and composition root | Both pipelines, stores, hotkey, permissions |
| [`MeetingRecordingStore`](../VoicePen/App/MeetingRecordingStore.swift) | Meeting UI state and lifecycle orchestration | `MeetingPipeline`, permissions, timeouts |
| [`DictationPipeline`](../VoicePen/Features/Pipeline/DictationPipeline.swift) | Push-to-Talk workflow from capture to insertion | Recorder, preprocessor, transcriber, normalizers |
| [`LiveAudioRecordingClient`](../VoicePen/Features/Recording/LiveAudioRecordingClient.swift) | Push-to-Talk recording session | Microphone capture, converter, mixer, `AVAudioFile` |
| [`CoreAudioMicrophoneCapture`](../VoicePen/Features/Recording/CoreAudioMicrophoneCapture.swift) | HAL microphone lifecycle and drained callback delivery | CoreAudio Audio Unit |
| [`CompositeMeetingRecordingClient`](../VoicePen/Features/Meetings/MeetingAudioSources.swift) | Start and stop both Meeting sources and aggregate health | Microphone and system-audio sources |
| [`MeetingMicrophoneStream`](../VoicePen/Features/Meetings/MeetingAudioSources.swift) | Per-callback Meeting microphone conversion and writing | Converter, active-channel mixer, sink |
| [`CoreAudioSystemOutputSource`](../VoicePen/Features/Meetings/MeetingAudioSources.swift) | Filtered CoreAudio process-tap capture | Tap plan, aggregate device, sink |
| [`MeetingAudioBufferFileSink`](../VoicePen/Features/Meetings/MeetingAudioFileIO.swift) | File lifecycle, level metering, first-failure handling | `ExtendedAudioFileWriter` |
| [`ExtendedAudioFileWriter`](../VoicePen/Features/Meetings/ExtendedAudioFileWriter.swift) | Async Core Audio file conversion and flush | `ExtAudioFileWriteAsync` |
| [`PCMStreamConverter`](../VoicePen/Features/AudioProcessing/PCMStreamConverter.swift) | Stateful sample-rate and PCM conversion | `AVAudioConverter` |
| [`LiveAudioPreprocessingClient`](../VoicePen/Features/AudioProcessing/LiveAudioPreprocessingClient.swift) | Optional best-effort denoising followed by speech detection and edge trimming | RNNoise, silence trimmer |
| [`AVFoundationMeetingAudioChunker`](../VoicePen/Features/Meetings/MeetingAudioChunker.swift) | Timeline windows, source-aware RNNoise, mixing | Audio file IO, RNNoise |
| [`MeetingPipeline`](../VoicePen/Features/Meetings/MeetingPipeline.swift) | Meeting chunk ASR, diarization, formatting, persistence | Chunker, transcriber, diarizer, stores |
| [`RoutingTranscriptionClient`](../VoicePen/Features/Transcription/RoutingTranscriptionClient.swift) | Route a request to the selected local backend | Model manifest, Whisper client |
| [`WhisperCppTranscriptionClient`](../VoicePen/Features/Transcription/WhisperCppTranscriptionClient.swift) | Own and reuse the loaded Whisper context | Whisper context, bundled Silero model |
| [`WhisperCppVoiceActivityDetection`](../VoicePen/Features/Transcription/WhisperCppVoiceActivityDetection.swift) | Locate Silero and apply one-retry decode policy | `WhisperCppContext` |
| [`SpeakerKitMeetingDiarizationClient`](../VoicePen/Features/Meetings/MeetingDiarization.swift) | Optional offline speaker-turn analysis | Local SpeakerKit model |

## Failure And Data-Lifetime Boundaries

| Boundary | Behavior |
| --- | --- |
| Capture callback vs. stop | Stop drains already submitted callback work before file finalization. |
| Async Meeting writer | Dispose flushes pending writes; the first write/close failure wins. |
| RNNoise | Missing model or processing failure falls back to original microphone samples. |
| Silence analysis | Dictation returns without insertion; Meetings skip silent chunks and discard an all-silent recording. |
| Meeting voice leveling | Failure is diagnostic only; ASR continues with the ordinary chunk. |
| Meeting VAD | Missing model uses ordinary decode; VAD failure gets one ordinary retry. |
| Diarization | Missing model, unusable timestamps, or runtime failure keeps the transcript without speaker labels. |
| Meeting processing failure | Except for the expected all-silence case, a failed or partial history entry is saved with retryable recovery audio when possible. |
| Successful cleanup | Meeting processing removes its tracked capture and derived files after persistence. Dictation temp files are swept by startup cleanup. Optional saved recordings and retained recovery files follow their own retention policies. |
