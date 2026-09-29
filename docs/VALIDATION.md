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

### Independent Office XML schema validation

Microsoft Open XML SDK 3.5.1 found 24 schema errors in the pre-release 0.4 smoke DOCX: paragraph/style/run/table property ordering and missing shading values. The writer now emits schema-ordered properties and explicit clear shading. A combined-formatting/list/table regression export passes Office 2013 validation locally, and 40 portable tests pass (one additional AppKit-only skip). CI now validates both that regression package and the optimized macOS app's smoke DOCX before allowing publication. This adds schema/semantic checks, not manual Word visual certification. The development-only validator and locked dependencies are in `tools/OOXMLValidation`; no .NET runtime ships in the app.

- Corrected export revision `df49e30` passed [macOS and independent schema CI](https://github.com/Ninnja10563/Scribe/actions/runs/36494097509). Both the optimized app's smoke DOCX and the combined-formatting regression package report zero Office 2013 schema/semantic errors. Independent PDF/package inspection again verified 14 source pages, a matching two-page selection, lists, tables, images and both comments. Tag `v0.4.0` points to that validated revision.

### Search/statistics follow-up

A semantic text snapshot now excludes generated list/page-break prefixes from Find and statistics while mapping Unicode matches back to AppKit UTF-16 selections. The snapshot is cached by editor revision; ordinary literal text resembling a list marker remains searchable. Native tests cover generated-versus-literal Roman numbers, multi-paragraph mapping and replacement/undo. This follow-up is after the v0.4.0 tag; macOS validation is pending.

- [Scribe v0.4.0](https://github.com/Ninnja10563/Scribe/releases/tag/v0.4.0) was published by [release run 36494356424](https://github.com/Ninnja10563/Scribe/actions/runs/36494356424), including the independent schema gate. The published arm64 DMG was downloaded and its SHA-256 verified. The subsequent semantic Find/statistics changes passed [macOS run 36494378619](https://github.com/Ninnja10563/Scribe/actions/runs/36494378619).

### Font-face persistence (v0.5 development)

Native v5 adds optional PostScript face identities, preserving weights/widths beyond bold/italic. v4 migration retains previous family/trait semantics. Native regression tests cover Medium/Light/Condensed faces through capture/save/reopen, style inheritance, family overrides and missing-face retention. These tests are awaiting macOS CI. DOCX still approximates concrete faces using family and bold/italic information; the export dialog discloses this when applicable.

- Font-face persistence passed [macOS run 36494732575](https://github.com/Ninnja10563/Scribe/actions/runs/36494732575), including native Medium/Light/Condensed round trips, style inheritance and missing-font retention. The independent DOCX schema check also passed.
- Inline DOCX page-break import previously moved preceding text to the next page by incorrectly setting paragraph.pageBreakBefore. The fix retains native inline flow controls and exports actual Office break elements. New native tests check projection, caret insertion/undo and PDF page placement; validation is pending.

- Inline page-break projection, caret insertion/undo and actual PDF page placement passed [macOS run 36495065947](https://github.com/Ninnja10563/Scribe/actions/runs/36495065947). The regression DOCX containing an inline page break also passed the independent schema validator.

### Internal heading links (v0.5 development)

The native Insert → Link to Heading dialog uses stable paragraph IDs. DOCX exports real bookmark/anchor links and resolves imported bookmark destinations to paragraph starts (mid-paragraph destinations produce an approximation warning). PDF exports named internal destinations; page-range exports omit clickable annotations whose destinations were excluded. Portable tests and independent Office XML validation pass for the exported internal-link package. Native dialog/navigation/undo and PDF destination tests are awaiting CI.

The first heading-link CI exposed an ambiguous menu selector, then PDF assertions exposed an AppKit-generated private URL annotation alongside the correct PDF destination. Downloaded failing test PDFs were independently inspected with PyMuPDF: the full PDF contained both a `scribe:` URL and a valid GoTo action; the partial export incorrectly retained the private URL. PDF finalization now removes only those AppKit private URL annotations using PDFKit, preserving actual document destinations and vector content. Native tests also verify metadata and absence of private URLs; independent smoke checks cover full and selected-page navigation.

- Final v0.5 candidate [36496454750](https://github.com/Ninnja10563/Scribe/actions/runs/36496454750) passed **77 macOS tests**, the native launch/render/export smoke check and independent Office XML validation. Its native heading-link dialog capture was inspected. PyMuPDF/python-docx checks verified 14 full pages, selected first/last pages, metadata, table/image, comments and working internal links without private application URLs. The 256-page hosted debug benchmark measured **0.599 seconds initial layout and 4.1 ms for an end edit**, not an end-to-end input latency guarantee.
- [Scribe v0.5.0](https://github.com/Ninnja10563/Scribe/releases/tag/v0.5.0) was published by successful [release run 36496698300](https://github.com/Ninnja10563/Scribe/actions/runs/36496698300), from the validated `fca9427` revision.
- The published v0.5.0 arm64 DMG was downloaded again and verified against its published SHA-256 checksum.

## Automatic contents work (v0.6 development)

Portable tests cover generated title/page updates, stable entry IDs, preservation of ordinary notes, removed headings, detached review text and v5→v6 migration. DOCX tests inspect actual field markers, right-aligned tab stops and cached-text import. Native tests exercise a 30-heading document, actual page labels with Roman numbering, grouped undo/redo, renamed headings and user text inserted after generated entries. Native validation is pending.

- The first TOC native tests passed, but the release-app smoke check stalled on quit after semantic editing. Its direct file write did not clear NSDocument's edited state. The smoke test now uses the real asynchronous native save operation and checks that edited state clears before exporting and quitting. A 90-second launch deadline retains a process sample and log on future stalls.
- Run [36498144968](https://github.com/Ninnja10563/Scribe/actions/runs/36498144968) completed the native tests and real save/quit/export smoke path. Its actual page rendering was inspected: the TOC has linked entries and right-aligned page labels. Independent checks verified the 14-page PDF, selected-page/internal-link output, comments, table/image, and actual Word TOC field. Options-dialog editing/undo is being added before release.

- Candidate [36499752574](https://github.com/Ninnja10563/Scribe/actions/runs/36499752574) passed **87 macOS tests**, three additional repetitions of the native TOC tests, native launch/save/quit, Office XML validation and independent PDF/DOCX inspection. The actual rendered PDF was inspected; linked TOC entries now retain the editor’s blue underline in print output. The hosted 256-page debug benchmark measured 0.956 seconds initial layout and 4.6 ms for an end edit.
- One preceding macOS run terminated with SIGBUS during the native TOC dialog test. Explicit window ownership was hardened and subsequent full/targeted runs passed, but the original crash had no retained stack trace and its cause is not established. CI now retains crash reports and retries failed native tests with Objective-C zombie diagnostics while preserving the original failure. Continued lifecycle regression monitoring is required.
- The independent PDF/package reader checks now run in CI as a release gate, including TOC field content, internal destinations and link appearance. The latest Linux run passed 53 portable tests with one AppKit-only skip.

## Named paragraph bookmarks (next development update)

Bookmarks now identify paragraph starts, with Add, Go To, Insert Link, Rename and Delete commands. Stable bookmark IDs keep links valid through renaming. Missing paragraphs leave bookmarks visible and recoverable by undo. DOCX uses actual named bookmarks and anchors; imported mid-paragraph locations explicitly warn about paragraph-start approximation. PDF links resolve to the same native paragraph destinations. Character-range bookmarks are not implemented. Portable, native dialog/deletion/undo and actual output regression coverage is being validated.

- [Scribe v0.6.0](https://github.com/Ninnja10563/Scribe/releases/tag/v0.6.0) was published by successful [release run 36500547860](https://github.com/Ninnja10563/Scribe/actions/runs/36500547860), from validated revision `f591ccd`. The published arm64 DMG was downloaded and its SHA-256 verified.
- Initial bookmark CI passed native navigation, text deletion/undo reattachment and actual PDF destinations. Its dialog test incorrectly grouped three directly invoked commands into one test event before Undo; the test now isolates the Delete command, as other native undo tests do. The corrected test is awaiting CI.

- Corrected bookmark and custom-page tests passed in [36500987368](https://github.com/Ninnja10563/Scribe/actions/runs/36500987368). Native tests verified custom PDF media-box dimensions, retained fractional margins and layout undo. Fit Page/Fit Width resizing and pinch-mode tests then passed in [36501146886](https://github.com/Ninnja10563/Scribe/actions/runs/36501146886). The new custom-paper and named-bookmark DOCX regression packages report zero Office 2013 validation errors locally. Combined release-smoke validation is in progress.
- Narrow custom pages exposed two additional table limits: creating/adding columns could fall below the native minimum width, and inserting a row before the first row omitted its cells. The core now rejects undersized columns without mutation and correctly inserts leading rows; table-property dialogs preserve fractional widths. Regression tests cover both cases.
