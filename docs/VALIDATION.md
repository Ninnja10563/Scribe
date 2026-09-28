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

## Recorded development results (28 September 2026)

- Latest Linux ARM64 verification: 20 core/interchange tests passed; the AppKit-only target was explicitly skipped. A stale incremental build following a public struct-layout change initially crashed; cleaning the build resolved it. Native CI always uses a fresh checkout/build.
- macOS run [36403618750](https://github.com/Ninnja10563/Scribe/actions/runs/36403618750) passed 30 tests, including native document factory creation/save/reopen, formatting undo/redo, search navigation after deletion, tables, images and PDF link annotations. The suite also verifies malformed-image preservation and combining-mark boundaries.
- The same macOS run built an arm64 app and verified DMG, launched the app, saved a 14-page native document, exported DOCX/PDF, and captured light/dark window images. The actual captures were visually inspected.
- An independent python-docx reader opened the exported DOCX and verified the table cells and inline image. This is not a Microsoft Word compatibility certification.
- An independent PyMuPDF reader verified all 14 PDF pages, the final paragraph, page labels, table text, and an embedded image. Its rendered first page was compared visually with the editor.
- Both v0.1.0 and [v0.2.0](https://github.com/Ninnja10563/Scribe/releases/tag/v0.2.0) DMGs were published. The v0.2.0 [release workflow](https://github.com/Ninnja10563/Scribe/actions/runs/36403913442) passed. The published DMG was downloaded again and verified against its published SHA-256 checksum.
- The 256-page native benchmark initially measured ~0.9 seconds for initial layout and ~190 ms for an edit near the end. After restarting layout near the edited page and eliminating repeated paragraph flattening, the cited run measured **0.791 seconds initial layout and 4.6 ms for the end edit**. These are debug-build timings on a hosted macOS runner, not an end-to-end input-latency guarantee. Editing near the beginning, complex objects, and physical-Mac memory/scrolling behavior need further profiling.

Developer ID signing, notarization, physical-Mac input/VoiceOver testing, and manual Word/Pages/LibreOffice round trips have not been completed.
