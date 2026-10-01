# Shared Transcript Workspace Specification

## Purpose

VoicePen has multiple saved-text screens that need the same reading workflow:
find a saved transcript, inspect the main text, and use domain-specific actions
without duplicating layout, search, grouping, and read-only text behavior.

## Requirements

### Requirement: Shared Transcript Workspace

VoicePen SHALL preserve the behavior contract for this capability.

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

#### Scenario: Screen adopts the shared transcript workspace

- **WHEN** a screen adopts the shared transcript workspace
- **THEN** VoicePen shall show a searchable dated list, center read-only text workspace, and collapsed metadata/actions sidebar rail by default.

#### Scenario: Entries span multiple local calendar days

- **WHEN** entries span multiple local calendar days
- **THEN** the shared list shall group visible entries by local day while preserving source order within each group.

#### Scenario: Search query is empty or whitespace-only

- **WHEN** the search query is empty or whitespace-only
- **THEN** the shared search matcher shall return entries unchanged.

#### Scenario: Search query has text

- **WHEN** the search query has text
- **THEN** the shared matcher shall use localized standard containment across the searchable fields provided by the adopting screen.

#### Scenario: No entries exist

- **WHEN** no entries exist
- **THEN** the workspace shall show the adopting screen's empty state.

#### Scenario: Entries exist but search has no matches

- **WHEN** entries exist but search has no matches
- **THEN** the workspace shall show the adopting screen's no-match state.

#### Scenario: Workspace is visible and the user presses Command-F

- **WHEN** the workspace is visible and the user presses Command-F
- **THEN** VoicePen shall show and focus the workspace search field.

#### Scenario: Workspace search field is visible and the user presses Escape

- **WHEN** the workspace search field is visible and the user presses Escape
- **THEN** VoicePen shall hide the search field, clear the query, and show the unfiltered list.

#### Scenario: Selected visible row changes

- **WHEN** the selected visible row changes
- **THEN** the center text workspace and right sidebar shall update to that entry.

#### Scenario: Selected entry disappears because entries or search results changed

- **WHEN** the selected entry disappears because entries or search results changed
- **THEN** VoicePen shall select the first visible entry or show no selection if none remain.

#### Scenario: Sessions or Meetings show the right metadata/actions sidebar rail

- **WHEN** Sessions or Meetings show the right metadata/actions sidebar rail
- **THEN** the user shall be able to show and hide the entire sidebar without changing the selected entry.

#### Scenario: Center text changes or the selected entry changes

- **WHEN** the center text changes or the selected entry changes
- **THEN** the center text surface shall clear text selection.

#### Scenario: User drags across the center text surface

- **WHEN** the user drags across the center text surface
- **THEN** VoicePen shall select the corresponding text range without moving the main window.

#### Scenario: User copies from the center text surface with no selected text

- **WHEN** the user copies from the center text surface with no selected text
- **THEN** VoicePen shall run the adopting screen's full-text copy action and show stable copied feedback.

#### Scenario: User copies while text is selected in the center text surface

- **WHEN** the user copies while text is selected in the center text surface
- **THEN** VoicePen shall copy the selected text instead of running the full-text copy action.

#### Scenario: Adopting screen enables line numbers for the center text surface

- **WHEN** an adopting screen enables line numbers for the center text surface
- **THEN** it shall show stable line numbers and remain smooth while scrolling with hundreds of lines.

#### Scenario: Center text surface is updated by SwiftUI without changed text

- **WHEN** the center text surface is updated by SwiftUI without changed text
- **THEN** it shall use a lightweight text revision instead of comparing or rescanning the full transcript string.

#### Scenario: Center text footer renders line and character totals

- **WHEN** the center text footer renders line and character totals
- **THEN** it shall read precomputed transcript metrics instead of recomputing them from the full transcript in `body`.

#### Scenario: Shared workspace list renders

- **WHEN** the shared workspace list renders
- **THEN** visible entry IDs and day groups shall come from a prepared list model rather than being rebuilt inside the shared workspace `body`.

#### Scenario: Shared workspace

- **WHEN** this capability applies
- **THEN** The shared workspace shall not read, decompress, or request hidden full text payloads for entries unless the adopting screen injects that behavior for the focused entry.
