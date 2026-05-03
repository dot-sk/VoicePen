---
id: ADR-0001
status: accepted
date: 2026-05-03
---

# Compressed History Text Storage

## Context

VoicePen should keep local voice history rows without an application entry-count limit so usage duration remains complete. Raw and final transcription text can grow the SQLite database over time, but deleting old text would make older history less useful.

## Decision

Store history text in plain SQLite text columns for recent rows. When the plain text budget is exceeded after saving a new history entry, compress a fixed-size batch of oldest plain text-bearing rows into nullable BLOB columns and mark their text storage format. When the total plain plus compressed text payload budget is exceeded, evict a fixed-size batch of oldest text payloads while keeping the history rows.

Keep the original row metadata, duration, status, timing, model metadata, and recognized word count so usage duration and estimated time saved remain complete even after old text payloads are evicted from the local cache.

Use an app-level compression/decompression layer rather than relying on SQLite to compress individual fields.

## Consequences

Recent history remains directly readable in SQLite. Older history text remains recoverable through VoicePen while it is compressed; oldest text can eventually be removed from the local cache so the database does not grow without bound if the user dictates for a long time.

The persistence schema has to support plain, compressed, and text-evicted rows. Future tooling that reads history directly from SQLite must understand the text storage format before expecting text in `raw_text` and `final_text`.

## Links

- [SPEC-004 History And Settings Persistence](../../Specs/2026-05-02-history-settings-persistence.md)
- `VoicePen/Features/History/VoiceHistoryStore.swift`
