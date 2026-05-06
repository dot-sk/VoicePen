---
id: SPEC-013
status: active
updated: 2026-05-06
tests: []
---

# Main Window Scroll Indicators

## Problem

VoicePen's main window uses dense sidebar and text surfaces where persistent
scroll indicators add visual noise, but fully hidden indicators make scrollable
areas harder to discover while interacting.

## Behavior

Scrollable lists and text surfaces in the main window keep ordinary mouse,
trackpad, keyboard, selection, and copy behavior, while using system overlay
scroll indicators that appear during scrolling and disappear when inactive.

## Acceptance Criteria

- Main window sidebar, Dictionary list, Meetings list, and History list shall use automatic scroll indicators while remaining scrollable and selectable.
- Main window scrollable text surfaces and import preview examples shall use automatic scroll indicators while preserving text selection and copy actions.

## Examples

| Case | Input | Expected |
| --- | --- | --- |
| Scroll a list | User scrolls a populated History, Meetings, Dictionary, or sidebar list | Content scrolls and the system scrollbar appears during scrolling, then disappears when inactive |
| Scroll transcript text | User scrolls a transcript or raw transcript text area | Text scrolls and remains selectable, with the system scrollbar shown only while scrolling |

## Test Mapping

- Manual: open populated sidebar, Dictionary, Meetings, History, transcript, raw transcript, and dictionary import preview surfaces; verify scrolling still works and scroll indicators appear during scrolling, then disappear when inactive.

## Notes

This is a presentation-only behavior. It shall not change saved data, filtering,
selection, copy, insert, or retry behavior.

## Open Questions

- None.
