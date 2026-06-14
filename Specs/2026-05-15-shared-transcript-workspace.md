---
id: SPEC-015
status: implemented
updated: 2026-06-14
tests:
  - VoicePenTests/TranscriptWorkspace/TranscriptSearchFilterTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptEditorMetricsTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptTextUIStateTests.swift
  - VoicePenTests/TranscriptWorkspace/TranscriptDayGroupsTests.swift
  - VoicePenTests/App/VoicePenAppCommandTests.swift
---

# Shared Transcript Workspace

## Problem

VoicePen has multiple saved-text screens that need the same reading workflow:
find a saved transcript, inspect the main text, and use domain-specific actions
without duplicating layout, search, grouping, and read-only text behavior.

## Behavior

VoicePen provides a reusable transcript workspace for screens that display saved
transcription-derived text. The workspace is domain-agnostic: it owns the shared
layout and accepts screen-specific data, search fields, row content, metadata,
actions, placeholders, and loading behavior from the adopting screen.

On desktop, the workspace uses three vertical areas: a left searchable
date-grouped list, a center read-only text workspace, and a right
metadata/actions sidebar. The right sidebar is collapsed by default and can be
shown from its narrow rail. The center text workspace is primary and fills
remaining space, while the left and right areas are bounded side panels. The
panes scroll independently when visible.

Search is hidden by default and appears when the user presses Command-F. It
uses a screen-provided placeholder and screen-provided searchable text. The
shared matcher trims whitespace, keeps source ordering, returns all entries for
an empty query, and matches with localized standard containment. The shared
workspace does not load hidden full text payloads by itself; screens that need
lazy detail loading must inject that behavior.

The center text surface is selectable, copyable, read-only, monospaced, and
shows line count, character count, and stable copied feedback. If text is
selected, standard selected-text copy behavior takes priority over a full-text
copy action.

## Acceptance Criteria

- When a screen adopts the shared transcript workspace, VoicePen shall show a searchable dated list, center read-only text workspace, and collapsed metadata/actions sidebar rail by default.
- When entries span multiple local calendar days, the shared list shall group visible entries by local day while preserving source order within each group.
- When the search query is empty or whitespace-only, the shared search matcher shall return entries unchanged.
- When the search query has text, the shared matcher shall use localized standard containment across the searchable fields provided by the adopting screen.
- When no entries exist, the workspace shall show the adopting screen's empty state.
- When entries exist but search has no matches, the workspace shall show the adopting screen's no-match state.
- When the workspace is visible and the user presses Command-F, VoicePen shall show and focus the workspace search field.
- When the workspace search field is visible and the user presses Escape, VoicePen shall hide the search field, clear the query, and show the unfiltered list.
- When the selected visible row changes, the center text workspace and right sidebar shall update to that entry.
- When the selected entry disappears because entries or search results changed, VoicePen shall select the first visible entry or show no selection if none remain.
- When Sessions or Meetings show the right metadata/actions sidebar rail, the user shall be able to show and hide the entire sidebar without changing the selected entry.
- When the center text changes or the selected entry changes, the center text surface shall clear text selection.
- When the user copies from the center text surface with no selected text, VoicePen shall run the adopting screen's full-text copy action and show stable copied feedback.
- When the user copies while text is selected in the center text surface, VoicePen shall copy the selected text instead of running the full-text copy action.
- When an adopting screen enables line numbers for the center text surface, it shall show stable line numbers and remain smooth while scrolling with hundreds of lines.
- When the center text surface is updated by SwiftUI without changed text, it shall use a lightweight text revision instead of comparing or rescanning the full transcript string.
- When the center text footer renders line and character totals, it shall read precomputed transcript metrics instead of recomputing them from the full transcript in `body`.
- When the shared workspace list renders, visible entry IDs and day groups shall come from a prepared list model rather than being rebuilt inside the shared workspace `body`.
- The shared workspace shall not read, decompress, or request hidden full text payloads for entries unless the adopting screen injects that behavior for the focused entry.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Empty workspace | Adopting screen has no entries | The screen-specific empty state is shown |
| Search match | User searches for text included in a provided search field | Matching entries remain in source order |
| Search miss | User searches for text not included in provided fields | The screen-specific no-match state is shown |
| Search shortcut | User presses Command-F while the workspace is active | The workspace search field appears and becomes focused |
| Hide search | User presses Escape while workspace search is visible | The search field hides, the query clears, and the full list returns |
| Day groups | Visible entries span several local days | Entries appear under local day headers without reordering within a day |
| Selection changed | User clicks another visible row | Center text and sidebar update to that row |
| Sidebar default | User opens Sessions or Meetings | The right sidebar starts collapsed as a narrow rail |
| Sidebar toggle | User clicks the sidebar toggle in Sessions or Meetings | The entire right sidebar hides or shows while the selected transcript remains unchanged |
| Copy full text | User presses Copy in the center editor with no selection | The screen-provided full-text copy action runs and shows copied feedback |
| Copy selection | User selects part of the center text and presses Command-C | Only the selected text is copied |

## Test Mapping

- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptSearchFilterTests.swift` covers shared query trimming, empty-query passthrough, localized matching, stable order, and no-match behavior.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptEditorMetricsTests.swift` covers line and character counting.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptTextUIStateTests.swift` covers stable text revisions, content fingerprints for different displayed transcripts, revision changes when displayed text changes, metric snapshots, and transcript timecode detection snapshots.
- Automated: `VoicePenTests/TranscriptWorkspace/TranscriptDayGroupsTests.swift` covers local-day grouping and entry order preservation.
- Automated: `VoicePenTests/App/VoicePenAppCommandTests.swift` covers that Meetings and Sessions wire the shared transcript workspace while keeping their own domain actions, and that shared workspace search is shown by Command-F and hidden with a cleared query by Escape.
- Manual: open Meetings and Sessions with multiple entries and verify both use the same three-pane layout, the right sidebar starts collapsed as a narrow rail, search reveal shortcut, Escape-to-hide behavior, independent pane scrolling when the sidebar is shown, hide/show behavior for the whole right sidebar, center text copy behavior, and smooth scrolling in a transcript with hundreds of lines. Verify Meetings shows center text line numbers and Sessions does not show a line-number gutter.

## Notes

Keep domain-specific policy in the adopting screens or domain adapters. The
shared workspace should accept data and callbacks through dependency injection
instead of branching on Meeting, Session, or History concepts.

## Open Questions

- None.
