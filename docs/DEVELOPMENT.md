# Repository assessment and development plan

## Starting point

Inspected on 28 September 2026. HEAD was `6591ce4` (Initial commit). The entire tracked repository contained LICENSE only. There were no source files, build configuration, tests, application, tags, releases, or existing version. No working implementation was replaced. The development host is ARM64 Debian Linux without Xcode/AppKit. An existing-app build, test run, and launch were impossible because no app existed.

## Architecture decisions

- Swift Package Manager, Swift 6 toolchain, macOS 14 minimum, Apple Silicon release builds. Swift 5 language mode currently avoids making the AppKit integration contingent on a full Swift 6 concurrency audit.
- DocumentCore is Foundation-only: semantic paragraphs/runs, sections/page settings, stable IDs, named styles with direct overrides, comments/bookmark anchor types, search, validation, atomic native saves, and recovery storage. Comments are implemented with native editing associations; named bookmarks identify stable paragraph locations.
- ImportExport implements actual OPC ZIP/XML for a limited DOCX subset, without launching third-party converters. Stored and DEFLATE ZIP inputs are supported. Paths are never extracted to disk. CRC checks, size limits, duplicate path rejection and disabled external XML entities constrain hostile files.
- AppKit owns windows, responders, NSDocument lifecycle, selection, input methods, accessibility, rich clipboard, spelling and undo. A shared NSTextStorage feeds an NSLayoutManager with fixed-size linked NSTextContainers. Containers are physical writing areas, not independent text boxes. TextKit determines glyph overflow and page boundaries.
- TextKit 1 is a deliberate initial choice: its linked container/text view support provides a proven native pagination path. TextKit 2 viewport layout is a future profiling-led migration, not an assumption that modern API names alone guarantee professional pagination.
- The editor's attributed text is a projection. The native file stores semantic JSON, not an opaque attributed-string archive. Direct formatting inherits from named styles when equal to the style's definition.
- Screen, PDF and print use the same glyph layout. Native format writes are atomic. Recovery writes are debounced into a separate Application Support directory and never overwrite source documents.

## Milestones

1. **Native foundation:** buildable application, styled paragraphs, flowing pages, native lifecycle, file validation, basic interoperability, release automation.
2. **Editing hardening:** manual IME/VoiceOver/selection/undo testing, list behavior, clipboard provenance, incremental paragraph projection, page virtualization, long-document profiling.
3. **Structured objects:** basic cell operations, embedded assets, accessible inline images and proportional geometry editing are delivered in v0.2, with a native v1→v2 migration. Remaining work includes merge/split, floating anchors/exclusion paths, shapes, and more table-layout coverage.
4. **Document structure:** independent sections, editable running content, page fields, TOC, bookmarks, links, footnote/endnote layout and reference numbering.
5. **Review:** anchored comments with edit transforms and a native sidebar are delivered in v0.4. Reversible tracked operations, acceptance/rejection and grammar engines remain future work.
6. **Interoperability:** Word/Pages/LibreOffice fixture corpus, table/image/numbering/section/header relationships, OOXML preservation of unsupported parts where safe, Markdown syntax coverage, PDF links and export options.
7. **Distribution:** Developer ID signing and notarization once credentials are available, update strategy, crash reporting with consent and privacy controls.

Each substantial, validated update should advance the version and publish a tagged DMG release. Do not publish a release merely because source files were generated. The CI release job depends on tests, an arm64 bundle, launch, pagination, native save, PDF output and rendering checks.

## List interoperability and editing update

Native v3 adds optional list-series identities and explicit restart markers. v1/v2 files migrate in memory, retaining legacy contiguous-list numbering. DOCX import resolves abstract definitions, concrete numbering instances, level/start overrides and numbering inherited from paragraph styles. Export gives independent lists separate instances and uses editor counters to preserve starts. Common decimal, upper/lower letter and Roman lists are supported; compound marker text and custom level-restart rules produce explicit import warnings.

Return within one list item preserves formatted runs and UTF-16 selection boundaries. Empty items exit/outdent; Backspace at the content start outdents. These operations participate in semantic undo. Selections spanning list paragraphs and physical input methods remain validation work.

PDF export uses a native save-panel accessory for page ranges and title/author/subject/keywords. Selected pages retain source page numbering and vector text. Invalid selections are rejected before replacing an output file. Image-quality presets remain pending; current output retains source assets. The save panel follows [Apple's URL validation delegate](https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:validate:)). Numbering follows the Office XML [concrete-instance and override model](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.leveloverride?view=openxml-3.0.1).

## Anchored review work in progress

Native v4 extends comment anchors across paragraphs and explicitly retains comments whose source text was deleted. Attributed comment IDs travel with native text edits and native undo; semantic list splits use a UTF-16 anchor transform. Review presentation is separate from text formatting. A native comments sidebar provides navigation, editing, resolution and reopening. macOS projection/undo tests and DOCX comment interchange are the next validation steps; this work is not part of the v0.3.0 release.

Classic DOCX comments now use actual comments parts, relationships, range starts/ends and references. Multi-paragraph and overlapping associations import/export, and detached comment text remains in the package. Word 2013 resolved state is preserved through the commentsExtended part and the last comment paragraph’s paraId. Reply hierarchy and newer collaboration/identity metadata remain limited and are disclosed on import. An independent python-docx comment fixture and semantic round-trip tests cover author/text/range preservation. Native insertion-boundary tests verify that typing next to a comment does not accidentally extend it.

Comment resolution follows Microsoft's [CommentEx definition](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.office2013.word.commentex?view=openxml-3.0.1) and [Open XML SDK part metadata](https://github.com/dotnet/Open-XML-SDK/blob/main/data/parts/WordprocessingCommentsExPart.json). Namespace aliases are normalized by URI before Office readers receive attributes, and comment/style/numbering parts are resolved through relationships instead of requiring fixed filenames.

## Typography and editing fidelity (v0.5 development)

Native v5 adds concrete PostScript font-face identity, with optional family/size/trait overrides. Missing faces render with a fallback while retaining the requested identity. Native font-panel selection now survives semantic capture and save/reopen for intermediate weights and condensed faces. DOCX remains family/trait based and discloses approximation on export. v1–v4 formats migrate in memory.

Find and statistics use a revision-cached semantic snapshot that omits generated list/page-break prefixes and maps content ranges to native UTF-16 selections. Literal text that resembles a generated marker remains content.

Inline page breaks use the native U+000C flow control inside text runs, separately from a paragraph's pageBreakBefore property. Office XML encodes them as actual `w:br type="page"` elements, never illegal literal XML controls. The editing projection labels generated paragraph-break prefixes so capture can distinguish them from inline breaks. Insert Page Break operates at the caret with native undo.

Internal heading links use `scribe://paragraph/<UUID>` within the native model. DOCX translates these into named zero-length bookmarks and `w:hyperlink w:anchor`, resolving import aliases back to newly assigned paragraph IDs. Named paragraph bookmarks were added during v0.7 development; mid-paragraph Word targets currently navigate to paragraph starts with an import warning. PDF uses Core Graphics [named destinations](https://developer.apple.com/documentation/coregraphics/cgcontext/setdestination(_:for:)); Word follows [BookmarkStart](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.bookmarkstart?view=openxml-3.0.1). Partial PDF exports suppress links to omitted pages.

## Automatic tables of contents (v0.6 development)

Native v6 stores TOC definitions separately from generated paragraph associations. Generated entries point to stable source-heading IDs and use the existing internal-link architecture. Ordinary paragraphs are not field content and survive refresh/removal. New paragraphs created by splitting a generated paragraph do not inherit its generated association. Regenerating changed entries detaches their associated review text instead of silently moving the annotation to different words.

AppKit renders TOC page labels using a right-aligned tab stop. Update reads actual glyph/container positions, refreshes the cached entries and repeats until heading page labels settle (up to six passes, with an explicit status if another refresh is needed). The operation is grouped as one undo step. DOCX exports a real TOC field around cached entries; import currently retains the cache and links with a disclosure, rather than claiming a live imported TOC.

## Named locations and custom layout (v0.7 development)

Bookmark links use `scribe://bookmark/<UUID>` and resolve through the bookmark to its paragraph ID. Renaming does not rewrite link text or targets. Deleting a paragraph retains the missing bookmark; native undo restores the paragraph identity. Bookmarks are paragraph locations, not character ranges. DOCX writes real bookmark names/anchors and imports visible named locations; mid-paragraph import approximation is disclosed. Export batches reuse an indexed destination resolver.

Page layout edits are transactional in DocumentCore. Custom dimensions and fractional margins use the existing native geometry schema. Table shrinkage reserves each column’s minimum width before redistributing remaining space; embedded image bytes remain unchanged. Fit Page uses both viewport dimensions, Fit Width follows viewport width, and both update after geometry/window changes. Pinch zoom returns to a fixed factor via AppKit’s [magnification notification](https://developer.apple.com/documentation/appkit/nsscrollview/didendlivemagnifynotification).

## Cell and row formatting (v0.8 development)

Native v7 stores sparse `TableCellStyle` overrides separately from paragraph text, and optional per-row minimum heights. Existing table definitions remain the defaults. Semantic row/column operations remap formatting coordinates. Cell properties can apply to a cell, row, column or whole table in one undoable transaction. Minimum heights allow text growth; fixed-height clipping is deliberately unsupported. Native projection uses [NSTextBlock dimensions](https://developer.apple.com/documentation/appkit/nstextblock/dimension), and DOCX uses schema-ordered `tcBorders`, `shd`, `tcMar`, `vAlign` and `trHeight` properties. Different edge borders/padding and exact-height imports disclose approximation. Merged cells remain future work.

## Merged cells (v0.9 development)

Native v8 adds rectangular spans. The anchor cell owns the original paragraphs, preserving their identities and runs. Split retains text in the anchor and creates empty surrounding cells; it does not guess how to redistribute content. Shared grid transforms update spans on insertion/deletion and retain a surviving merged anchor's content. DOCX encodes horizontal grid spans and vertical restart/continuation cells. The importer discards only required empty continuation paragraphs that have no bookmark/review association. Native TextKit blocks and keyboard navigation use semantic cell anchors. Nested tables and rectangular selection UI remain separate work. Core and package tests pass; native rendering validation is in progress.

## Document properties and spelling (v0.10 development)

The existing title, author and language fields now have native controls and DOCX interchange; no native schema change is needed. `und` requests automatic language detection. Explicit language requests supply an [orthography option](https://developer.apple.com/documentation/appkit/nsspellchecker/optionkey/orthography) and remove automatic orthography checking through the [text-view delegate](https://developer.apple.com/documentation/appkit/nstextviewdelegate/textview(_:willchecktextin:options:types:)). They do not change `NSSpellChecker`'s shared language preference. DOCX stores real Dublin Core metadata and a Word `docDefaults` language; style/run-specific languages are not represented by the current single-language model and disclose approximation.

## Native style editing and typography follow-up

Style definitions now have separate native Text/Paragraph controls, creation from current formatting and a single document transaction for create-and-apply. Empty-paragraph geometry also uses document transactions, so it is undoable and marked for autosave. Native v10 separates inherited highlighting from explicit removal; capture does not convert inherited highlight/baseline properties into accidental direct overrides.

Rendered validation exposed the next typography work: AppKit's semantic superscript attribute alone does not provide the desired reduced glyphs in the shared layout. The next projection will retain logical font sizes in the model while adding native scaled fonts and baseline offsets. Capture, font-panel editing and rich clipboard export must normalize those projection attributes to avoid shrinking fonts on each save or paste. This work is separate from the 0.12 release candidate.

ScriptProjection now keeps logical fonts and script levels separate from scaled native fonts/baseline offsets. CharacterFormattingCapture unwraps that projection, including empty runs; ExternalTextProjection restores standard attributes for RTF/RTFD. The native font commands use logical sizes and an explicit Normal Baseline action. This follows Apple's distinction between [semantic superscript levels and literal baseline offsets](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/AttributedStrings/Articles/standardAttributes.html). Empty-paragraph font changes use document transactions; ordinary insertion-point changes remain typing state.

## Paragraph ruler (0.14 development)

A custom AppKit NSRulerView exposes the three paragraph indents represented by the semantic model. Document-to-ruler coordinate conversion follows page centering, magnification and horizontal scrolling. Dragging previews a guide; mouse-up commits one document transaction. Escape and stale-selection/revision guards cancel a drag. Mixed values use outlined markers, and a multi-paragraph edit changes only the chosen indent. Lists, table cells and generated TOC paragraphs keep their existing contextual controls. Keyboard arrows, Shift-arrows and native accessibility slider actions provide alternate input. View → Focus Ruler enters the controls; Escape returns to the document. Focus mode restores ruler visibility on exit.

The native text view's automatic ruler update is overridden so it cannot introduce unrepresented tab stops. This uses Apple's [NSRulerView](https://developer.apple.com/documentation/appkit/nsrulerview) integration and [accessibility increment/decrement actions](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/accessibilityperformincrement()). Custom tab stops, list/table ruler editing and physical VoiceOver testing remain future work.

## Stable page boundaries and image gestures (0.15 development)

A conservative pagination fast path tracks UTF-16 page-end offsets for small plain-text insertions. It stops scanning once the layout passes every pending insertion and reaches the expected character boundary; subsequent containers retain their page identity and are laid out by TextKit as needed. Flow controls, deletions, formatting, geometry edits, tables and existing layout warnings invalidate this optimization. The structured document and native input model are unchanged. Regression comparisons check every page's glyph range and line baselines, then compare actual exported PDF word coordinates with a fresh full layout.

Cold layout also recalculates a terminal container once it gains an overflow successor. Otherwise TextKit can use different trailing line/paragraph spacing decisions on initial construction and later reflow. Adding text views preserves the shared typing attributes instead of resetting the active font to the opening paragraph's attributes.

Image corner drags use the dominant normalized movement on either axis, constrained to the page. Escape restores the original projection. Window-coordinate deltas remain valid if repagination removes the original text view; commit resolves the current text view again. Original asset bytes and semantic adjustments are retained.

## Hierarchical navigation (0.16 development)

DocumentOutlineView uses NSOutlineView's native hierarchy, selection, disclosure, keyboard and accessibility behavior. A heading attaches to the nearest previous lower-level heading, so missing heading levels do not create artificial document nodes. Stable paragraph IDs preserve node identity, expansion and selection across refreshes. Expansion is window UI state and does not alter the file or undo history. Passive navigation retains keyboard focus; Return/double-click explicitly returns it to the native document text view. Refresh and close suppress navigation callbacks.

## Running-content variants (0.17 development)

Native v11 adds optional first/even running text while retaining the existing default header/footer fields. Switches do not delete dormant text. One shared resolver is used for screen and PDF/print. First-page variants take precedence; even/odd selection uses the displayed numbering start. An imported start is retained even if no page-number field is displayed. Existing PageNumbering settings override that imported parity start.

DOCX uses actual [HeaderReference types](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.headerreference?view=openxml-3.0.1), `titlePg`, and [evenAndOddHeaders](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.evenandoddheaders). Word's even/odd switch is document-wide: when another section enables it, a section using one default header gets equivalent even-page parts to retain its display. In that mixed-section export, dormant even text from a disabled section cannot also occupy the active even part; the native original retains it. Editing multiple sections is not yet exposed. Import continues to flatten section layouts with a warning and imports running content as plain text; fields are cached text, not editable field objects.

Running text currently occupies one line. Its shared output validator checks only active page variants, rejects overlong/multiline text, and requires enough top/bottom margin to keep it out of the body. PDF validation occurs before writing, so a rejected export leaves the previous file intact. Screen drawing clips to the writing width while the status explains the problem; native saving still preserves all text. Multiline running layout and page-number/text collision handling remain future work.

Parity is an explicit interoperability exception: the [OOXML standard](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.evenandoddheaders) counts physical pages, while [Microsoft's Word implementation note](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/66274c6b-6552-47b6-a1b1-3cfcd9c064f4) uses the displayed starting number. Scribe follows Word's documented rule. LibreOffice 24.2.7.2 rendered the even-start fixture using physical order. Import/export disclose this case; validation separately checks the common start-at-1 output and each renderer's expected start-at-2 output. This is not manual Word validation.


## Equations (0.18 development)

Native v12 adds an optional equation to a text run containing one object-replacement character. Mathematical source is immutable and bounded to 8 KB, 2,048 nodes and 32 parser levels; JSON decoding reparses it rather than accepting arbitrary recursive object archives. The Foundation-only semantic tree supports rows, tokens, scripts, fractions, radicals, delimiters and large operators. Earlier files migrate in memory with no equation field.

The AppKit projection uses baseline-aware attachments and the same Core Text/Core Graphics display list for the preview, document and PDF. STIX Two Math is bundled unmodified under the SIL Open Font License with its pinned source/hash and copyright notice. Registration is process-local. The font's [OpenType MATH constants](https://learn.microsoft.com/en-us/typography/opentype/spec/math) guide fraction and script positioning. This is an initial renderer: full glyph assemblies, math kerning, matrices, accents and multiline math remain future work. Delimiters use larger font sizes and radicals use constructed vector strokes.

Standard RTFD clipboard data contains rendered PNG equations. A separate bounded, versioned JSON representation restores mathematical source and original image adjustments between Scribe windows; it is accepted only when its text and object positions match the RTFD. Plain-text, Markdown and RTF exports retain equation source instead of silently dropping objects. The native document remains authoritative. Equation color and font weight are not yet configurable.

DOCX writes actual Office Math fractions, radicals, scripts, delimiters and n-ary operators. Import isolates math runs from Word runs and bounds the XML subtree. Unsupported mathematical constructs retain readable text with a warning. Imported source is canonicalized; it need not match the original source spelling. Office Math styling and advanced layout remain an interoperability area. The independent fixture is authored with python-docx/lxml, not captured from Microsoft Word.

Office Math n-ary operators require a real operand: exporting an empty `m:e` produces a placeholder box in LibreOffice. The writer groups following row terms up to a relation or another large operator into that operand. Standalone operators use limit/script structures without inventing an operand. Normal text uses `m:nor`. Independent Office rendering remains essential in addition to schema validation; equation font size and spacing can differ between engines.

## Footnotes and endnotes (0.19 candidate)

Native format v13 stores note paragraphs independently from body references, with explicit v12 migration and validation of one reference per note. The attributed body carries note content alongside reference attachments so native deletion and Undo preserve ownership. Numbers are derived from live reference order, with separate footnote/endnote series.

Footnote page fitting chooses actual TextKit line prefixes, verifies references after reflow, and reserves measured note glyphs at the page bottom. Long notes continue by measured line fragments; an unlayable line/object blocks output. Endnotes use a separate linked native text flow after the body, counted in physical page totals and printing. Screen and PDF share glyphs; PDF references, return labels and source hyperlinks retain destinations. Native transparent buttons over note regions provide mouse and accessibility actions that open a separate rich editing session. This is not continuous inline note editing, and API checks are not a manual VoiceOver audit.

DOCX note interchange uses actual footnote/endnote parts, body references, automatic note labels, part-scoped relationships, and shared paragraph/run formatting. Images, equations, external links and links back to body bookmarks use the ordinary interchange modules. Normal-note IDs are independent of display numbering; missing, duplicate and nested references are rejected. Unreferenced definitions and unsupported numbering/placement settings are disclosed. The implementation follows Microsoft's [footnote model](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.footnote?view=openxml-3.0.1). Independent SDK validation, an original python-docx/lxml fixture, and rendered LibreOffice output complement semantic round-trip tests.

Note creation/editing, opening, recovery and exports are enabled on the development branch. A final full build, native app launch, rendered-output inspection and release validation are required before publishing 0.19. The latest published release remains 0.18.

## Explicit line-height semantics (development)

`ParagraphFormatting.lineSpacing` remains additional spacing in points. Native format v15 adds optional `ParagraphLineHeight` with multiple, minimum and exact modes; older documents migrate in memory without changing their additional spacing. Styles and direct formatting share the same model, native paragraph projection/capture and review replay. Paragraph and style dialogs expose the modes. Note clipboard payload v3 preserves the new formatting; old payloads remain readable.

DOCX uses `w:spacing` with 240ths of a line for multiples and twips for minimum/exact heights. Defaults and based-on line-height settings are inherited before direct properties. Additional gaps combined with explicit height cannot be represented exactly in Office XML; broader style inheritance and paragraph-spacing collapse remain limitations. Portable tests and Office schema validation pass; native controls, Undo and measured PDF output are undergoing macOS validation. This development format is not part of published 0.20.
