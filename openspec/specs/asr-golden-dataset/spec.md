# ASR Golden Dataset Specification

## Purpose

Build a private, manually verified audio/reference corpus so recognition experiments can compare quality and latency against stable inputs.

## Requirements

### Requirement: Prepare a private draft corpus

The tooling SHALL prepare local copies of long saved dictations and draft reference text without modifying the source recordings or application database. Selection SHALL respect the configured minimum duration measured from audio samples and SHALL NOT fill the corpus with shorter examples. Possible repetition indicators SHALL be labeled as review hints, not proven recognition errors. It SHALL record audio fingerprints and whether inputs are already processed. Generated personal data SHALL be excluded from Git.

#### Scenario: Prepare saved dictations
- **WHEN** the user prepares a corpus from available saved dictations
- **THEN** each selected recording has a local audio copy, provenance, a fingerprint, and an unconfirmed draft reference

#### Scenario: Select difficult long candidates
- **WHEN** the user requests recordings above a minimum audio duration
- **THEN** the corpus includes only available recordings meeting that threshold, ordered longest first, and reports fewer examples instead of adding short ones

#### Scenario: Prepare over existing work
- **WHEN** the destination already contains a corpus or review work
- **THEN** preparation fails without replacing the existing corpus or references

### Requirement: Human review establishes references

The local review page SHALL offer audio playback, editable reference text, notes, exclusion, and explicit confirmation. Edits SHALL persist across reloads. An empty confirmed reference SHALL require an explicit no-speech choice. Concurrent stale saves SHALL fail without replacing newer edits.

#### Scenario: Correct and confirm a reference
- **WHEN** the reviewer corrects a draft and confirms it
- **THEN** the corrected text and confirmed state survive a new review session

#### Scenario: Confirm no speech
- **WHEN** the reviewer confirms an empty reference with the no-speech choice
- **THEN** the recording is retained as a confirmed no-speech example

#### Scenario: Reject an accidental blank or stale save
- **WHEN** a confirmation has an unmarked empty reference or an outdated revision
- **THEN** the save fails and the last saved reference remains unchanged

### Requirement: Export reproducible confirmed snapshots

The tooling SHALL export only confirmed examples, with their reference text, audio, fingerprints, and a deterministic snapshot identity. It SHALL reject empty exports and changed audio. Later review edits SHALL not mutate an existing exported snapshot.

#### Scenario: Export a mixed review corpus
- **WHEN** confirmed, draft, and excluded examples exist
- **THEN** the export contains only confirmed examples and identifies their exact audio and reference version

#### Scenario: Edit after export
- **WHEN** a reference changes after a snapshot was exported
- **THEN** the previous snapshot remains unchanged and a new confirmed export has a new identity

#### Scenario: Reject incomplete or damaged inputs
- **WHEN** no references are confirmed or a selected audio file no longer matches its fingerprint
- **THEN** export fails without producing a golden snapshot

### Requirement: Review remains local

The review server SHALL bind only to loopback, serve only corpus resources, and accept mutations only from its own origin. Seeking within audio playback SHALL be supported.

#### Scenario: Local review and seeking
- **WHEN** the browser requests a recording or a byte range within it
- **THEN** the server returns the requested corpus audio bytes without exposing arbitrary filesystem paths

#### Scenario: Reject unrelated access
- **WHEN** a request attempts a non-corpus path or a mutation from another origin
- **THEN** the server rejects it without changing review data
