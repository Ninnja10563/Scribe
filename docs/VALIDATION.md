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

## List and PDF update (29 September 2026)

- Linux ARM64: 30 portable tests passed, with the AppKit test target explicitly skipped. Coverage includes native v2→v3 migration, list instances/restarts, Unicode splitting, independent compressed numbering fixtures, nested restart defaults and invalid PDF page ranges.
- macOS run [36487326588](https://github.com/Ninnja10563/Scribe/actions/runs/36487326588) passed 40 tests and the arm64 build/DMG/launch/export smoke checks. Native list Return, Backspace and undo/redo passed; PDFKit verified selected pages, metadata and non-destructive rejection of invalid selections. Release candidate [36487750983](https://github.com/Ninnja10563/Scribe/actions/runs/36487750983) then passed all 42 tests, including the independent numbering fixture and nested restart-default regression.
- The first macOS run exposed an NSString/Swift range-bridging difference that accepted a split inside an emoji. Explicit grapheme-boundary validation fixed it; the corrected regression passes on macOS and Linux.
- Independent PyMuPDF inspection verified 14 full-document pages, a two-page selection matching the first and last source pages exactly, original page labels and PDF metadata. The first rendered PDF page and actual native window were visually inspected.
- Independent python-docx/lxml inspection opened the produced package and verified table/image retention, upper-Roman/lower-letter definitions and starting values 4 and 9. The independent fixture generator is checked in; none of these checks constitute manual Word certification.

- [Scribe v0.3.0](https://github.com/Ninnja10563/Scribe/releases/tag/v0.3.0) was published after the matching revision passed macOS CI. Its [release workflow](https://github.com/Ninnja10563/Scribe/actions/runs/36487991871) also passed. The published DMG was downloaded and its SHA-256 verified.

## Comment review update in progress (29 September 2026)

- macOS run [36489585858](https://github.com/Ninnja10563/Scribe/actions/runs/36489585858) passed 52 tests, built the arm64 app and DMG, and launched/rendered the review sidebar. Tests cover multi-paragraph and overlapping anchors, native deletion/undo reattachment, insertion-edge affinity, list splits, classic DOCX range markers and an independently generated comment fixture.
- Actual light/dark window captures were inspected. Independent python-docx recovered the exported comment author and multiline body. PyMuPDF verified that review text did not enter the printed body and that selected-page output still matched the full PDF. These checks are reproducible with `scripts/verify-smoke.py` (development dependencies python-docx 1.2.0 and PyMuPDF 1.28.2).
- Sidebar Resolve/Reopen/Delete/Undo and commented table-row deletion tests passed in [36490011749](https://github.com/Ninnja10563/Scribe/actions/runs/36490011749) (54 macOS tests). Native Add/Edit/Cancel dialogs subsequently passed, and the final-paragraph test exposed missing identity attributes; those are corrected. A passive-navigation regression then exposed linked-view selection notifications overriding the remembered page. The correction and Word resolved-state/namespace-alias support passed in release-candidate run [36492085376](https://github.com/Ninnja10563/Scribe/actions/runs/36492085376), with 58 macOS tests. No physical-Mac input/accessibility or manual Word validation is implied.

- The 0.4 candidate's actual light/dark review interface was visually inspected. `scripts/verify-smoke.py` independently verified its 14-page PDF, matching two-page selection, metadata, lists, table/image and two comments, including the join between comment paragraph IDs and Word resolved-state metadata.
- The latest Linux run passed 39 portable tests, with one AppKit-only skip. The CDATA/namespace-rebinding regression passed in [36492472230](https://github.com/Ninnja10563/Scribe/actions/runs/36492472230), bringing the native suite to 59 tests. The release smoke test now also re-imports its generated DOCX using the optimized application binary, with explicit delegate-lifetime protection.
