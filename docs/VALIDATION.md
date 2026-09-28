# Validation

Tests cover native semantic round trips, style inheritance, future-version refusal, invalid geometry, duplicate IDs, Unicode/UTF-16 search, statistics, atomic recovery isolation, malformed snapshots, large-document serialization/search, OPC package structure, DOCX text/style/link round trips, unsafe/corrupt ZIP inputs, unsupported-content warnings, malformed XML and basic Markdown import.

The macOS suite additionally checks attributed-text projection, style inheritance, flowing pages, glyph coverage without gaps/overlap, repagination after changing margins, shrinking documents, explicit page breaks and PDF creation.

The release smoke test launches the app, constructs a multi-page document, creates a native save and PDF, and renders a PNG of the actual window. These artifacts are uploaded with each successful CI build.

## Required manual release testing

Automated tests do not establish interactive usability. Before a production release, test on physical Apple Silicon Macs:

- Typing and undo across page boundaries; Shift/Command/Option selection; drag selection; dead keys and CJK composition.
- Rich copy/paste from Word, Pages, Safari and Notes; paste-and-match-style; trailing empty paragraphs.
- VoiceOver reading order, toolbar names, keyboard-only focus/navigation, large text and high contrast.
- Save As, versions/revert, disk-full failures, process-kill recovery, multiple unsaved windows and clean quit.
- Lists: Return, empty-item exit, nested Tab/Shift-Tab, continuation/restart, renumbering after edits.
- 10/50/100/200+ page typing latency, scrolling, memory and Instruments profiling; no current latency guarantee.
- PDF visual comparison and printer output; Word/Pages/LibreOffice opening exported DOCX.

Results from the current development run will be recorded after CI completes. Do not confuse a configured test with a passed test.
