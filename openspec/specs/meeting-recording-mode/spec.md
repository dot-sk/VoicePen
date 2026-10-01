# Meeting Recording Mode Specification

## Purpose

VoicePen needs a meeting workflow that records longer conversations with both
the user's microphone input and system output audio from other apps. This must
stay distinct from push-to-talk dictation because meeting output is sensitive,
should not auto-paste into the active app, and must not flow through hosted LLM
providers.

## Requirements

### Requirement: Meeting Recording Mode

VoicePen SHALL preserve the behavior contract for this capability.

VoicePen provides Meeting Mode as an explicit menu and in-app action. Before the
first meeting recording, VoicePen shows a consent reminder. Recording starts
only when Microphone permission is available and system output audio capture can
start. Meeting Mode v1 uses audio-only capture backends and shall not create a
screen capture stream.

During recording, VoicePen shows a persistent status panel with elapsed active
time, the meeting recording limit in minutes, microphone status, system audio
status, and a non-intrusive red recording pulse. The Meetings header changes its
start action to stop while recording, shows a pulsing recording icon in the stop
action, and shows a compact cancel action. Cancel deletes temporary audio and
creates no history entry. Stop runs local transcription and saves a meeting
history entry. Successful processing deletes temporary audio immediately but
keeps a local recovery audio copy for retry for 24 hours. Failed or partial
processing deletes temporary audio but keeps a local recovery audio copy for
retry for 7 days. While stopped meeting audio is processing, the
persistent status panel shows that transcript processing is underway instead of
showing microphone and system audio as unavailable.

Meeting history is separate from dictation history. It stores transcript text,
duration, creation date, source flags, product status, errors, timings, detected
speaker count when diarization provides one, and the local model and VoicePen app
version used for transcription with a separate transcript storage budget.
`Partial Transcript` means VoicePen saved non-empty transcript text but did not
process the full meeting. `Failed` means no usable transcript text was saved.
Meeting entries are excluded from dictation usage totals and milestones. Meeting
transcripts can be copied, but Meeting Mode never auto-pastes output or exposes
an Insert Transcript action.

On desktop, the Meetings screen adopts the shared transcript workspace from
`shared-transcript-workspace` capability. Meetings provides meeting-specific rows, metadata, actions, search
fields, and focused-entry transcript loading to that shared layout. Search
filters loaded meeting summaries and previews locally by the transcript preview
or full text already available in an entry, recording date/time, status, error,
duration, audio source labels, ASR model, and app version. Opening the Meetings
screen must not read or decompress every saved full transcript.

Meeting Mode v1 captures both microphone input and system output audio where
available without requesting Apple system voice processing for microphone
capture. It automatically stops live recording at 120 minutes, composes the
captured sources into one continuous master recording, and sends that complete
master through one local transcription request so the ASR decoder keeps context
across the meeting. VoicePen does not split transcription into application-owned
fixed-duration windows; the local ASR runtime owns any internal inference
windowing. Raw, mastered, and recovery meeting audio is stored as 16 kHz mono
16-bit PCM so long recordings use less disk space without lowering ASR sample
rate. The 120 minute limit applies to live capture only; local processing and
retry shall process available recovery audio beyond that duration. Meeting
system audio can be configured before
recording to capture all system audio, capture selected apps only, or capture
all system audio except selected apps. Selected apps are persisted by bundle
identifier with a display name for settings UI. If VoicePen cannot apply the
selected filter at recording start because the selected list is empty or no
selected-only app is currently running, it switches the setting back to all
system audio, surfaces a warning, and starts recording with all system audio.
v1 does not provide summaries,
action items, ticket drafts, engineering notes, pause, resume, playback,
waveforms, an audio player, export, speaker profiles, voice-profile linking or
creation, or transcript editing.

#### Scenario: Meeting Mode starts before consent acknowledgment

- **WHEN** Meeting Mode starts before consent acknowledgment
- **THEN** VoicePen shall show the consent reminder first.

#### Scenario: Microphone permission is missing

- **WHEN** microphone permission is missing
- **THEN** VoicePen shall not start recording and shall identify microphone as missing.

#### Scenario: System output audio capture cannot start because permission is missing

- **WHEN** system output audio capture cannot start because permission is missing
- **THEN** VoicePen shall identify system audio permission as missing.

#### Scenario: Microphone permission is available and system output audio capture starts

- **WHEN** microphone permission is available and system output audio capture starts
- **THEN** VoicePen shall start one meeting session that captures microphone and system audio.

#### Scenario: Meeting Mode

- **WHEN** this capability applies
- **THEN** Meeting Mode shall not request Apple system voice processing for microphone or system audio capture.

#### Scenario: During Meeting recording, VoicePen

- **WHEN** this capability applies
- **THEN** During Meeting recording, VoicePen shall not change, mute, duck, restore, or call CoreAudio output-volume or output-mute APIs for the user's speaker or other output device.

#### Scenario: Push-to-talk may run while meeting capture is recording or processing and

- **WHEN** this capability applies
- **THEN** Push-to-talk may run while meeting capture is recording or processing and shall not pause, stop, or restart meeting capture.

#### Scenario: Meeting capture is recording or processing

- **WHEN** the meeting capture is recording or processing
- **THEN** push-to-talk shall not run its own default-input gain boost and shall not restore output-related gain levels.

#### Scenario: Meeting capture is active

- **WHEN** the meeting capture is active
- **THEN** push-to-talk output may be present in meeting audio; V1 does not filter out meeting-side dictation speech.

#### Scenario: Push-to-talk and meeting ASR requests

- **WHEN** this capability applies
- **THEN** Push-to-talk and meeting ASR requests shall share the existing `RoutingTranscriptionClient` + `WhisperCppTranscriptionClient` actor path and be serialized by it; a PTT timeout remains a PTT timeout.

#### Scenario: If push-to-talk errors or times out during Meeting recording/processing, meeting capture state and processing

- **WHEN** this capability applies
- **THEN** If push-to-talk errors or times out during Meeting recording/processing, meeting capture state and processing state shall stay unchanged.

#### Scenario: Meeting audio is written to temporary, mastered, or recovery files

- **WHEN** meeting audio is written to temporary, mastered, or recovery files
- **THEN** VoicePen shall store it as 16 kHz mono 16-bit PCM.

#### Scenario: Meeting microphone and system-audio capture

- **WHEN** this capability applies
- **THEN** Meeting microphone and system-audio capture shall preserve sequential converter state and shall not perform synchronous disk writes from a realtime audio callback.

#### Scenario: Normal Meeting stop

- **WHEN** this capability applies
- **THEN** Normal Meeting stop shall stop each Core Audio source, drain callback work already submitted by that source, and close its asynchronous writer before processing begins.

#### Scenario: Shall reject an affected source as incomplete when its finalized readable audio duration materially

- **WHEN** this capability applies
- **THEN** VoicePen shall reject an affected source as incomplete when its finalized readable audio duration materially differs from the duration accepted by its capture writer or from the source capture timeline instead of silently treating time-compressed audio as synchronized.

#### Scenario: Meeting audio capture does not start within 10 seconds

- **WHEN** meeting audio capture does not start within 10 seconds
- **THEN** VoicePen shall leave the recording state and surface a capture timeout error.

#### Scenario: Meeting audio capture start is canceled or times out after one source has started

- **WHEN** meeting audio capture start is canceled or times out after one source has started
- **THEN** VoicePen shall stop any partially started audio sources before leaving the recording state.

#### Scenario: Meeting Mode v1

- **WHEN** this capability applies
- **THEN** Meeting Mode v1 shall not request or use screen capture for meeting recording.

#### Scenario: Recording is active

- **WHEN** the recording is active
- **THEN** the Meetings header shall keep a compact cancel action and switch the primary start recording button in place to Stop instead of showing a separate Stop button.

#### Scenario: Recording is active 2

- **WHEN** the recording is active
- **THEN** VoicePen shall show a pulsing recording indicator in the Meetings header stop action and in the persistent status panel so users can notice that capture is still running.

#### Scenario: Recording is active 3

- **WHEN** the recording is active
- **THEN** the persistent status panel shall show the meeting recording limit in minutes.

#### Scenario: Recording is canceled

- **WHEN** recording is canceled
- **THEN** VoicePen shall delete temporary audio and not create meeting history.

#### Scenario: Saved Meeting recordings are enabled

- **WHEN** saved Meeting recordings are enabled
- **THEN** VoicePen shall schedule one best-effort asynchronous copy of the mastered, pre-leveling Meeting audio that proceeds to transcription.

#### Scenario: Saved Meeting audio copying or pruning is scheduled

- **WHEN** saved Meeting audio copying or pruning is scheduled
- **THEN** VoicePen shall continue voice leveling, transcription, retry, recovery audio, and history handling without waiting for that saved-audio work to finish.

#### Scenario: Meeting saved-audio copying fails

- **WHEN** Meeting saved-audio copying fails
- **THEN** VoicePen shall log the failure asynchronously and continue Meeting processing without changing transcription, retry, recovery audio, or history behavior.

#### Scenario: Saved Meeting audio copy succeeds for a recording that creates a meeting history entry

- **WHEN** a saved Meeting audio copy succeeds for a recording that creates a meeting history entry
- **THEN** VoicePen shall associate the archived audio file with that meeting history entry.

#### Scenario: Retrying a failed or partial Meeting recording

- **WHEN** this capability applies
- **THEN** Retrying a failed or partial Meeting recording shall not create a duplicate saved Meeting master when audio was already saved during the original processing attempt.

#### Scenario: Canceling an active Meeting recording

- **WHEN** this capability applies
- **THEN** Canceling an active Meeting recording shall not save Meeting audio.

#### Scenario: Recording is stopped and audio is not discarded as all-silent preprocessing

- **WHEN** recording is stopped and audio is not discarded as all-silent preprocessing
- **THEN** VoicePen shall transcribe locally and save a meeting entry.

#### Scenario: Recording is stopped and decoding returns model metadata

- **WHEN** recording is stopped and decoding returns model metadata
- **THEN** VoicePen shall save the app version used for that decoding alongside the local model metadata.

#### Scenario: Recording is stopped

- **WHEN** recording is stopped
- **THEN** the saved meeting duration shall use the active wall-clock recording duration, not the sum of microphone and system audio source durations.

#### Scenario: Active recording reaches the 120 minute limit

- **WHEN** active recording reaches the 120 minute limit
- **THEN** VoicePen shall automatically stop recording and start local transcription.

#### Scenario: Active recording is still running 5 minutes before the 120 minute limit

- **WHEN** active recording is still running 5 minutes before the 120 minute limit
- **THEN** VoicePen shall show one non-blocking user notification that recording is still running and shall open the VoicePen window to the Meetings screen when the user clicks it.

#### Scenario: Active recording stops or is canceled before the 5-minute reminder point

- **WHEN** active recording stops or is canceled before the 5-minute reminder point
- **THEN** VoicePen shall not show the limit reminder for that recording.

#### Scenario: Configured live recording limit is shorter than the reminder lead time

- **WHEN** a configured live recording limit is shorter than the reminder lead time
- **THEN** VoicePen shall skip the reminder and keep automatic stop behavior unchanged.

#### Scenario: Recording reaches the 120 minute limit and transcription produces usable transcript text

- **WHEN** recording reaches the 120 minute limit and transcription produces usable transcript text
- **THEN** VoicePen shall save the meeting without marking it failed or partial solely because the limit was reached.

#### Scenario: Recovered audio metadata extends beyond the readable audio frames

- **WHEN** recovered audio metadata extends beyond the readable audio frames
- **THEN** VoicePen shall clamp mastering to readable source audio and preserve the remaining meeting timeline as silence.

#### Scenario: Retrying a failed or partial meeting with available recovery audio longer than 120 minutes

- **WHEN** retrying a failed or partial meeting with available recovery audio longer than 120 minutes
- **THEN** VoicePen shall process the available recovery audio beyond 120 minutes instead of rejecting or truncating it because of the recording limit.

#### Scenario: Local transcription runs but produces no usable transcript text

- **WHEN** local transcription runs but produces no usable transcript text
- **THEN** VoicePen shall save the meeting as failed even if capture or processing was incomplete.

#### Scenario: Meeting history rows

- **WHEN** this capability applies
- **THEN** Meeting history rows shall not let technical incomplete-capture or incomplete-processing flags override the product status shown to the user.

#### Scenario: Saved meeting duration is shorter than one minute

- **WHEN** a saved meeting duration is shorter than one minute
- **THEN** meeting history items shall display the duration in seconds instead of fractional minutes.

#### Scenario: Stopped meeting audio is processing

- **WHEN** the stopped meeting audio is processing
- **THEN** VoicePen shall show that transcript processing is underway in the persistent status panel without showing microphone or system audio as unavailable.

#### Scenario: Stopped meeting audio is processing 2

- **WHEN** the stopped meeting audio is processing
- **THEN** VoicePen shall report phase progress without inventing fixed-duration ASR chunk progress.

#### Scenario: Meeting diarization is expected after ASR

- **WHEN** Meeting diarization is expected after ASR
- **THEN** determinate processing progress shall not show 100% until speaker analysis, transcript formatting, and saving have finished.

#### Scenario: The complete Meeting master is inside one local ASR request

- **WHEN** the the complete Meeting master is inside one local ASR request
- **THEN** VoicePen shall show generic transcript processing status without a determinate percentage.

#### Scenario: Transcription completes successfully

- **WHEN** transcription completes successfully
- **THEN** VoicePen shall delete temporary audio and shall keep recovery audio retryable for 24 hours from successful processing completion.

#### Scenario: Transcription fails or saves only a partial transcript

- **WHEN** transcription fails or saves only a partial transcript
- **THEN** VoicePen shall delete temporary audio but keep a local recovery audio copy for retry for 7 days.

#### Scenario: Cleans stale temporary audio on startup

- **WHEN** VoicePen cleans stale temporary audio on startup
- **THEN** it shall remove old VoicePen-owned meeting `.caf` temporary audio as well as old VoicePen-owned `.wav` temporary audio.

#### Scenario: Retry processing succeeds

- **WHEN** retry processing succeeds
- **THEN** VoicePen shall update the same meeting history entry and keep recovery audio retryable for 24 hours from successful retry completion.

#### Scenario: Retry processing succeeds from an existing recovery audio copy

- **WHEN** retry processing succeeds from an existing recovery audio copy
- **THEN** VoicePen shall refresh the recovery manifest expiration without duplicating the retained audio files.

#### Scenario: Retry processing fails

- **WHEN** retry processing fails
- **THEN** VoicePen shall keep the same meeting history entry retryable without extending the original recovery audio expiration.

#### Scenario: Recovery audio expires

- **WHEN** recovery audio expires
- **THEN** VoicePen shall delete the audio, keep the meeting history entry, and make retry unavailable.

#### Scenario: Meeting processing does not complete within the processing timeout

- **WHEN** meeting processing does not complete within the processing timeout
- **THEN** VoicePen shall cancel processing, leave the meeting processing state, surface a timeout error, and keep recovery audio retryable instead of saving a completed meeting transcript.

#### Scenario: Stopped meeting audio is processing 3

- **WHEN** the stopped meeting audio is processing
- **THEN** VoicePen shall expose a compact cancel action in the persistent status panel.

#### Scenario: User cancels stopped meeting processing

- **WHEN** the user cancels stopped meeting processing
- **THEN** VoicePen shall cancel the in-flight local processing immediately, leave the meeting processing state, clear processing progress and temporary processing artifacts, and keep the meeting audio retryable.

#### Scenario: User cancels retry processing for an existing meeting entry

- **WHEN** the user cancels retry processing for an existing meeting entry
- **THEN** VoicePen shall cancel the in-flight retry processing, clear retry processing artifacts, and leave the existing meeting entry and recovery audio unchanged.

#### Scenario: Default meeting processing timeout

- **WHEN** this capability applies
- **THEN** The default meeting processing timeout shall be sized for the 120-minute recording limit and shall be at least 4 hours, so valid long local ASR plus diarization runs are not canceled solely because they are slower than short dictation.

#### Scenario: One captured source is silent but another source contains speech

- **WHEN** one captured source is silent but another source contains speech
- **THEN** VoicePen shall keep the audible source in the mastered recording and continue processing the meeting.

#### Scenario: Microphone and system audio overlap

- **WHEN** microphone and system audio overlap
- **THEN** VoicePen shall normalize their useful speech levels independently, mix them with headroom, and prevent sample clipping before transcription.

#### Scenario: Meeting mastering

- **WHEN** this capability applies
- **THEN** Meeting mastering shall use one consistent gain across the complete timeline so internal processing-block boundaries do not introduce level jumps or clicks.

#### Scenario: Meeting voice leveling is enabled

- **WHEN** Meeting voice leveling is enabled
- **THEN** VoicePen shall best-effort render the complete mastered recording through system dynamics and peak limiting once before transcription.

#### Scenario: Meeting voice leveling fails

- **WHEN** Meeting voice leveling fails
- **THEN** VoicePen shall continue transcribing the ordinary mastered recording and keep a diagnostic note.

#### Scenario: All captured sources are rejected as audio silence before local transcription

- **WHEN** all captured sources are rejected as audio silence before local transcription
- **THEN** VoicePen shall delete temporary audio, show an informational alert, and not save a meeting entry or recovery audio.

#### Scenario: Local transcription returns empty text or text that is fully removed as known transcript

- **WHEN** local transcription returns empty text or text that is fully removed as known transcript artifacts
- **THEN** VoicePen shall keep the failed meeting entry path.

#### Scenario: Local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал

- **WHEN** local transcription returns known short subtitle or outro artifact lines such as "Субтитры сделал ...", "Субтитры создавал ...", "Добавил субтитры ...", or "Продолжение следует..."
- **THEN** VoicePen shall remove those lines from meeting transcripts before saving history.

#### Scenario: Meeting system audio source is set to all system audio

- **WHEN** Meeting system audio source is set to all system audio
- **THEN** VoicePen shall build a global system output tap.

#### Scenario: Meeting system audio source is set to selected apps only

- **WHEN** Meeting system audio source is set to selected apps only
- **THEN** VoicePen shall build a non-exclusive app-filtered system output tap for the selected bundle identifiers.

#### Scenario: Meeting system audio source is set to all except selected apps

- **WHEN** Meeting system audio source is set to all except selected apps
- **THEN** VoicePen shall build an exclusive app-filtered system output tap excluding the selected bundle identifiers.

#### Scenario: Current macOS release does not support bundle-ID system audio taps

- **WHEN** the current macOS release does not support bundle-ID system audio taps
- **THEN** VoicePen shall resolve selected bundle identifiers to CoreAudio process object IDs and build the app-filtered tap instead of failing capture solely because bundle-ID filtering is unavailable.

#### Scenario: Selected apps only has no selected apps at recording start

- **WHEN** selected apps only has no selected apps at recording start
- **THEN** VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.

#### Scenario: Selected apps only has no selected app running at recording start

- **WHEN** selected apps only has no selected app running at recording start
- **THEN** VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.

#### Scenario: All except selected apps has no selected apps at recording start

- **WHEN** all except selected apps has no selected apps at recording start
- **THEN** VoicePen shall persistently switch Meeting system audio source to all system audio, surface a warning, and start recording.

#### Scenario: Meeting system audio source mode and selected app list

- **WHEN** this capability applies
- **THEN** Meeting system audio source mode and selected app list shall persist across launches; invalid stored modes fall back to all system audio and invalid app entries are ignored.

#### Scenario: Meeting system audio source is set to all system audio 2

- **WHEN** Meeting system audio source is set to all system audio
- **THEN** the Settings screen shall hide the selected-app controls.

#### Scenario: Meeting system audio source is set to selected apps only or all except selected

- **WHEN** Meeting system audio source is set to selected apps only or all except selected apps
- **THEN** the Settings screen shall show selected-app controls and allow choosing one or more macOS `.app` bundles at once.

#### Scenario: Settings screen Meeting system audio source control changes

- **WHEN** the Settings screen Meeting system audio source control changes
- **THEN** VoicePen shall persist the selected mode and hide or show selected-app controls without SwiftUI publishing warnings.

#### Scenario: One source fails mid-recording

- **WHEN** one source fails mid-recording
- **THEN** VoicePen shall stop capture and preserve incomplete-source metadata without marking a successfully processed transcript as `Partial Transcript`.

#### Scenario: Microphone and system audio overlap 2

- **WHEN** microphone and system audio overlap
- **THEN** VoicePen shall merge their readable samples into one continuous timeline master so dialogue order follows meeting time instead of source order.

#### Scenario: Meeting processing

- **WHEN** this capability applies
- **THEN** Meeting processing shall make exactly one local ASR request for the complete mastered recording and shall not reset decoder context at fixed one-minute boundaries.

#### Scenario: Each initial or retry Meeting processing run

- **WHEN** this capability applies
- **THEN** Each initial or retry Meeting processing run shall snapshot the current custom dictionary once and pass its language-aware glossary prompt to that complete-master local ASR request.

#### Scenario: Meeting processing 2

- **WHEN** this capability applies
- **THEN** Meeting processing shall apply the same deterministic custom-dictionary normalization as dictation to recognized content before saving, without changing transcript timecodes or speaker labels.

#### Scenario: Push-to-talk may overlap the same default-input AudioUnit path with meeting microphone capture without requiring

- **WHEN** this capability applies
- **THEN** Push-to-talk may overlap the same default-input AudioUnit path with meeting microphone capture without requiring a manual double-capture gate.

#### Scenario: Meeting transcript timecodes

- **WHEN** this capability applies
- **THEN** Meeting transcript timecodes shall be controlled by a persistent Settings screen setting that is enabled by default.

#### Scenario: Meeting transcript timecodes are enabled

- **WHEN** Meeting transcript timecodes are enabled
- **THEN** meeting transcripts shall include meeting-relative timecodes for each transcribed segment returned by local transcription; audio without returned segments shall not receive synthetic timecodes.

#### Scenario: Meeting transcript timecodes are enabled 2

- **WHEN** Meeting transcript timecodes are enabled
- **THEN** VoicePen shall request fine-grained timestamp decoding from local models and shall trim leading or trailing inactive source-audio time from displayed segment intervals when source activity is available.

#### Scenario: Meeting diarization

- **WHEN** this capability applies
- **THEN** Meeting diarization shall be controlled by a persistent Settings screen setting in the Meeting features section.

#### Scenario: Meeting diarization settings help

- **WHEN** this capability applies
- **THEN** Meeting diarization settings help shall describe experimental speaker labels from a separate local diarization model.

#### Scenario: Meeting diarization is enabled and the local diarization model is installed

- **WHEN** Meeting diarization is enabled and the local diarization model is installed
- **THEN** VoicePen shall warm the diarization model automatically at app start, after enabling the setting, and after a successful diarization model download.

#### Scenario: Model settings

- **WHEN** this capability applies
- **THEN** Model settings shall keep the Meeting diarization model lifecycle limited to download, progress, status, and delete controls while warm-up remains automatic when diarization is enabled.

#### Scenario: User starts a Meeting diarization model download

- **WHEN** the user starts a Meeting diarization model download
- **THEN** VoicePen shall expose download progress state, retry transient artifact download failures, and log the download start, model artifact stages, retry attempts, completion, cancellation, and failure.

#### Scenario: Meeting diarization model installation

- **WHEN** this capability applies
- **THEN** Meeting diarization model installation shall download one versioned GitHub Release archive described by a bundled manifest and shall not query or download from Hugging Face at runtime.

#### Scenario: Shall validate the diarization archive byte size and SHA-256 digest, extract it into a

- **WHEN** this capability applies
- **THEN** VoicePen shall validate the diarization archive byte size and SHA-256 digest, extract it into a temporary directory, verify every required SpeakerKit model path, and replace the model directory atomically before writing the completion marker.

#### Scenario: Proxy settings exist in the local environment settings file

- **WHEN** proxy settings exist in the local environment settings file
- **THEN** Meeting diarization model downloads shall use the same proxy configuration as transcription model downloads.

#### Scenario: Meeting diarization runs

- **WHEN** Meeting diarization runs
- **THEN** VoicePen shall log enough diagnostics to identify whether missing speaker labels came from model loading, backend pipeline execution, backend speaker-turn output, VoicePen turn postprocessing, or transcript speaker merge assignment.

#### Scenario: Meeting processing runs

- **WHEN** Meeting processing runs
- **THEN** VoicePen shall log diarization and complete-master transcription elapsed times so short-recording latency can be traced to the expensive stage.

#### Scenario: Meeting diarization is enabled and the local diarization model is available

- **WHEN** Meeting diarization is enabled and the local diarization model is available
- **THEN** VoicePen shall run diarization as a separate offline pass after ASR produces timestamped transcript regions.

#### Scenario: Meeting diarization 2

- **WHEN** this capability applies
- **THEN** Meeting diarization shall consume the full merged meeting timeline master in 16 kHz mono format, and VoicePen shall not compact ASR speech regions for diarization.

#### Scenario: Meeting diarization 3

- **WHEN** this capability applies
- **THEN** Meeting diarization shall use a VoicePen backend contract that returns speaker turns for the meeting timeline; VoicePen is responsible for remapping those turns to transcript regions before output formatting.

#### Scenario: Meeting diarization 4

- **WHEN** this capability applies
- **THEN** Meeting diarization shall use the `.speakerKit` backend.

#### Scenario: Meeting diarization UI

- **WHEN** this capability applies
- **THEN** Meeting diarization UI shall not expose a backend selector.

#### Scenario: Legacy stored backend values including pyannote, sortformer, and invalid values

- **WHEN** this capability applies
- **THEN** `legacy` stored backend values including `pyannote`, `sortformer`, and invalid values SHALL normalize to `.speakerKit`.

#### Scenario: For .speakerKit backend load/warm/diarize, VoicePen

- **WHEN** this capability applies
- **THEN** For `.speakerKit` backend load/warm/diarize, VoicePen shall use local-only files and pass `download: false`.

#### Scenario: Shall not prompt users for an expected Meeting diarization speaker count before running Meeting

- **WHEN** this capability applies
- **THEN** VoicePen shall not prompt users for an expected Meeting diarization speaker count before running Meeting diarization.

#### Scenario: Meeting diarization is enabled and ASR timestamp regions are usable

- **WHEN** Meeting diarization is enabled and ASR timestamp regions are usable
- **THEN** VoicePen shall request diarization even for short recordings.

#### Scenario: Shall store the detected speaker count returned in meeting transcript speaker labels as the

- **WHEN** this capability applies
- **THEN** VoicePen shall store the detected speaker count returned in meeting transcript speaker labels as the saved meeting speaker count.

#### Scenario: Meeting diarization postprocessing

- **WHEN** this capability applies
- **THEN** Meeting diarization postprocessing shall remove tiny turns, merge nearby turns from the same speaker, smooth short speaker flips, and avoid creating new speakers from uncertain regions.

#### Scenario: Meeting transcript speaker labels

- **WHEN** this capability applies
- **THEN** Meeting transcript speaker labels shall assign speakers from diarization turns by word timestamp overlap when word timestamps are available, and by ASR segment overlap or midpoint when word timestamps are unavailable; VoicePen shall not invent labels for transcript spans that have no diarization overlap.

#### Scenario: Meeting diarization model warmup and load diagnostics

- **WHEN** this capability applies
- **THEN** Meeting diarization model warmup and load diagnostics SHALL validate that the local `.speakerKit` pipeline can load and execute, and log timing and progress summaries to identify setup/load failures.

#### Scenario: Meeting transcript speaker labels 2

- **WHEN** this capability applies
- **THEN** Meeting transcript speaker labels shall avoid splitting ASR segments on every tiny speaker boundary; splits shall be limited to meaningful text/time groups.

#### Scenario: Consecutive timestamped transcript fragments have the same detected speaker and are separated only by

- **WHEN** consecutive timestamped transcript fragments have the same detected speaker and are separated only by a short pause
- **THEN** VoicePen shall combine them into readable bounded lines while preserving speaker changes and the combined time range.

#### Scenario: Bundled model manifest

- **WHEN** this capability applies
- **THEN** The bundled model manifest shall expose transcription models independently from Meeting diarization models.

#### Scenario: Meeting transcription ends with repeated short identical transcript segments that are likely local model

- **WHEN** Meeting transcription ends with repeated short identical transcript segments that are likely local model silence hallucinations
- **THEN** VoicePen shall remove that repeated tail before saving the meeting transcript.

#### Scenario: Meeting diarization is enabled

- **WHEN** Meeting diarization is enabled
- **THEN** VoicePen shall request segment timestamps from the local transcription backend even when transcript timecodes are not displayed.

#### Scenario: Meeting diarization is unavailable or fails

- **WHEN** Meeting diarization is unavailable or fails
- **THEN** VoicePen shall keep the transcript rather than failing the meeting solely because speaker labels could not be produced.

#### Scenario: Meeting diarization produces structured speakers for a saved meeting

- **WHEN** Meeting diarization produces structured speakers for a saved meeting
- **THEN** VoicePen shall save the detected speaker count on that meeting history entry.

#### Scenario: Meeting recording starts while the selected transcription model warmup is in progress

- **WHEN** Meeting recording starts while the selected transcription model warmup is in progress
- **THEN** VoicePen shall keep that warmup running instead of canceling it, so first meeting processing can reuse the warmed model when possible.

#### Scenario: Transcript exists

- **WHEN** transcript exists
- **THEN** VoicePen shall let the user copy it without calling any LLM provider.

#### Scenario: Meetings opens on desktop

- **WHEN** Meetings opens on desktop
- **THEN** VoicePen shall use the shared transcript workspace described in `shared-transcript-workspace` capability.

#### Scenario: Meeting search

- **WHEN** this capability applies
- **THEN** Meeting search shall filter loaded meeting summaries and previews locally by transcript preview or full transcript text already available in an entry, recording date/time, status, error, duration, audio source labels, ASR model, and VoicePen app version.

#### Scenario: Meeting search 2

- **WHEN** this capability applies
- **THEN** Meeting search shall not read or decompress every saved full transcript when the Meetings screen opens.

#### Scenario: Meetings renders the shared transcript workspace

- **WHEN** Meetings renders the shared transcript workspace
- **THEN** VoicePen shall pass precomputed text metrics, text revision with content identity, visible entry IDs, day groups, and timecode presence snapshots so hover, selection, and metadata refreshes do not rescan every visible meeting entry or the focused full transcript while still updating the editor when two entries have the same local revision.

#### Scenario: Meeting search has no matches

- **WHEN** Meeting search has no matches
- **THEN** VoicePen shall show an empty state that communicates no meetings were found and suggests trying another query.

#### Scenario: Main VoicePen window is focused

- **WHEN** the main VoicePen window is focused
- **THEN** Command-R shall start Meeting recording when no capture is active and stop Meeting recording when capture is active, regardless of the selected section or active keyboard layout.

#### Scenario: Meeting detail

- **WHEN** this capability applies
- **THEN** Meeting detail shall show the focused transcript in the shared center workspace and copy the full saved transcript through the shared center copy action.

#### Scenario: Failed meeting has no transcript

- **WHEN** a failed meeting has no transcript
- **THEN** the center workspace shall show the saved error text.

#### Scenario: Meeting detail 2

- **WHEN** this capability applies
- **THEN** Meeting detail shall show Status, Recording, Duration, Audio sources, Processing, Speakers detected, and Actions in the right sidebar.

#### Scenario: Meeting detail 3

- **WHEN** this capability applies
- **THEN** Meeting detail shall keep the full-transcript Copy action in the editor header and avoid duplicating it in the right sidebar.

#### Scenario: Meeting detail 4

- **WHEN** this capability applies
- **THEN** Meeting detail shall keep Delete recording in the right sidebar as the bottom destructive action, after the scrollable metadata content.

#### Scenario: Meeting detail has one or more existing archived saved-recording audio files

- **WHEN** a Meeting detail has one or more existing archived saved-recording audio files
- **THEN** VoicePen shall show a Reveal in Finder action in the right sidebar after the metadata content.

#### Scenario: Meeting detail Reveal in Finder

- **WHEN** this capability applies
- **THEN** Meeting detail Reveal in Finder shall use only saved-recordings archive files and shall not reveal short-lived recovery audio retained for retry.

#### Scenario: Meeting detail has no archived saved-recording audio file, or all archived files no longer

- **WHEN** a Meeting detail has no archived saved-recording audio file, or all archived files no longer exist
- **THEN** VoicePen shall hide the Reveal in Finder action.

#### Scenario: Meeting detail Speakers detected

- **WHEN** this capability applies
- **THEN** Meeting detail Speakers detected shall show the saved structured speaker count when present, and `—` when a count was not produced.

#### Scenario: Meeting detail 5

- **WHEN** this capability applies
- **THEN** Meeting detail shall not infer voice profiles or show speaker identity/profile actions.

#### Scenario: Meeting detail actions in this stage

- **WHEN** this capability applies
- **THEN** Meeting detail actions in this stage shall include Copy transcript in the editor and Delete recording in the right sidebar; existing retry may remain available for recoverable audio.

#### Scenario: Meeting detail 6

- **WHEN** this capability applies
- **THEN** Meeting detail shall not expose playback, waveform, audio player, export, speaker profile, voice-profile linking or creation, transcript editing, Insert Transcript, or auto-paste actions.

#### Scenario: Meeting detail Copy transcript action

- **WHEN** this capability applies
- **THEN** Meeting detail Copy transcript action shall show temporary copied feedback after copying a transcript.

#### Scenario: Meeting detail with saved transcript is open and Command-C is pressed while no focused

- **WHEN** a Meeting detail with saved transcript is open and Command-C is pressed while no focused text input or selected transcript range handles the copy command
- **THEN** VoicePen shall copy the full saved transcript regardless of the active keyboard layout.

#### Scenario: Transcript text is selected in the editor

- **WHEN** transcript text is selected in the editor
- **THEN** Command-C shall preserve the standard selected-text copy behavior instead of copying the full transcript.

#### Scenario: Meeting detail Command-C full-transcript copy

- **WHEN** this capability applies
- **THEN** Meeting detail Command-C full-transcript copy shall show the same temporary copied feedback as the editor Copy action.

#### Scenario: Copy transcript feedback

- **WHEN** this capability applies
- **THEN** Copy transcript feedback shall keep stable dimensions while switching between normal and copied states.

#### Scenario: Meetings screen opens

- **WHEN** the Meetings screen opens
- **THEN** VoicePen shall load meeting history list metadata and transcript previews without reading or decompressing every saved full transcript.

#### Scenario: Meeting history entry becomes focused

- **WHEN** a meeting history entry becomes focused
- **THEN** VoicePen shall load and decompress the full transcript for that focused entry only.

#### Scenario: New meeting history row appears in the Meetings list

- **WHEN** a new meeting history row appears in the Meetings list
- **THEN** its text shall be visible immediately without requiring the user to scroll the list first.

#### Scenario: Meeting list preview text

- **WHEN** this capability applies
- **THEN** Meeting list preview text shall omit leading transcript timecodes while preserving transcript text and speaker labels.

#### Scenario: Meetings list has entries from multiple local calendar days

- **WHEN** the Meetings list has entries from multiple local calendar days
- **THEN** VoicePen shall group the list into sticky day sections while preserving newest-first entry order within each day.

#### Scenario: Meeting detail 7

- **WHEN** this capability applies
- **THEN** Meeting detail shall not expose an Insert Transcript action and shall never auto-paste meeting output.

#### Scenario: Local ASR internally windows a long meeting master

- **WHEN** local ASR internally windows a long meeting master
- **THEN** VoicePen shall preserve chronological transcript order.

#### Scenario: Meetings are deleted

- **WHEN** meetings are deleted
- **THEN** VoicePen shall delete meeting rows and leave dictation history unchanged.

#### Scenario: Meeting detail 8

- **WHEN** this capability applies
- **THEN** Meeting detail shall show user-facing processing information: the local model that decoded the meeting, the app version used for decoding when it is known, the total processing time, and saved per-stage pipeline timings for preprocessing, ASR, and diarization when those timings were produced, without exposing backend/version metadata as a primary detail.

#### Scenario: Meeting detail 9

- **WHEN** this capability applies
- **THEN** Meeting detail shall show Meeting transcript timecode status only when the feature is unavailable or not produced for that saved transcript; when timecodes are present in the transcript, the detail shall not duplicate that obvious status as metadata.

#### Scenario: Meeting history

- **WHEN** this capability applies
- **THEN** Meeting history shall not contribute to the general dictation minutes, word counts, streaks, or milestones.

#### Scenario: Main window activity bar

- **WHEN** this capability applies
- **THEN** The main window activity bar shall place Meetings immediately after Home and before Sessions.

#### Scenario: Meeting Mode is recording or processing

- **WHEN** the Meeting Mode is recording or processing
- **THEN** VoicePen shall show meeting-specific status icons in the menu bar and main window navigation.

#### Scenario: Meeting Mode is actively recording

- **WHEN** the Meeting Mode is actively recording
- **THEN** the menu bar icon shall show a clear recording indicator with a non-intrusive red pulse so the user can notice that capture is still running.

#### Scenario: OpenRouter

- **WHEN** this capability applies
- **THEN** OpenRouter shall not be called anywhere in Meeting Mode v1.
