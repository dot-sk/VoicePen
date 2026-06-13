---
id: ADR-0008
status: accepted
date: 2026-06-13
---

# STTextView Transcript Display

## Context

VoicePen's shared transcript workspace displays long saved dictation and meeting
texts. The previous AppKit bridge maintained a custom `NSTextView`, selection
tracking, full-text copy behavior, and a local line-number ruler. That kept the
dependency surface small but pushed editor layout and gutter behavior into app
code.

STTextView provides a maintained TextKit 2 text surface with built-in line
numbers, wrapping, selection, and AppKit integration. VoicePen still needs to
own its product behavior: transcripts remain read-only, selectable, copyable,
and wired through the shared workspace contract.

STTextView is GPLv3/commercial dual-licensed. VoicePen can use it while the
project remains GPL-compatible, but a closed-source or paid proprietary
distribution requires a commercial STTextView license or replacing the
dependency before distribution.

## Decision

Use STTextView for the shared transcript text surface and remove VoicePen's
custom line-number ruler/index code.

Keep the integration behind `TranscriptTextEditor` so Meetings and Sessions do
not depend directly on STTextView APIs. Preserve the existing copy semantics:
selected text copies normally, and Command-C with no selection runs the
screen-provided full-transcript copy action.

## Consequences

VoicePen delegates line-number rendering and TextKit 2 layout behavior to
STTextView, reducing local editor infrastructure.

Build and release workflows now depend on the STTextView Swift package and its
transitive packages.

Closed-source or paid proprietary releases must treat STTextView licensing as a
release gate. The rollback path is to remove the package and restore the local
`NSTextView` bridge if the dependency, UX, or license constraints stop fitting
the product.

## Links

- [SPEC-015 Shared Transcript Workspace](../../Specs/2026-05-15-shared-transcript-workspace.md)
- `VoicePen/App/TranscriptTextEditor.swift`
- https://github.com/krzyzanowskim/STTextView
