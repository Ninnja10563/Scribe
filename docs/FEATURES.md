# Feature status — Scribe 0.11 development (latest release: 0.10)

This is a foundation release. “Implemented” means there is working code and an exposed editing path, not that the feature has the interoperability coverage of a mature word processor.

| Area | Implemented | Still needed |
| --- | --- | --- |
| Native application | Swift/AppKit, arm64 bundle, document windows and tabs, menus, native spelling with per-document language, title/author properties, focus mode, persistent Fit Page/Fit Width and fixed zoom, light/dark chrome | Physical-Mac keyboard/IME/VoiceOver audit, mixed-language runs, richer preferences |
| Document model | Versioned semantic paragraphs/runs, sections, styles, tables/cell references, inline images, IDs; v1–v8→v9 migrations; TOC definitions and entries | More block types, independent section editing, preservation of future extension payloads |
| Pagination | Shared TextKit layout across actual page containers; A4/Letter/Legal, custom dimensions, orientation, fractional margins, page breaks | Virtualization, widow/orphan controls, configurable hyphenation, typography audit |
| Formatting | Fonts/size and concrete faces/weights via native panel, common traits, color/highlight, super/subscript, alignment, spacing and indents | Draggable ruler, dedicated inline font-weight controls |
| Styles | Built-in headings/title/body/quote/caption, custom creation/modification/deletion, live definition updates, outline navigation | Style inheritance editor, collapsible heading content |
| Lists | Bullets, decimal/letter/Roman numbering, independent series, restart/continuation commands, nesting, Return split/empty-item exit, Backspace outdent | Physical-Mac input audit, custom compound markers, selection spanning multiple list items |
| Tables | Editable cells, insertion, add/delete rows/columns, Tab navigation, column widths, cell backgrounds/borders/padding/vertical alignment, minimum row heights, header shading, rectangular merge/split and span-aware grid edits; TextKit layout | Drag sizing, cell-range selection, nested tables, cells taller than one page (PDF/print blocked when text overflows) |
| Images | PNG/JPEG/HEIC/TIFF insertion, Finder drop, image paste, inline layout, proportional resizing by handles or dialog, alt text; reversible crop, clockwise rotation and opacity | Floating placement/wrapping, visual crop handles |
| Running content | Text headers/footers; top/bottom, left/centre/right page numbers and formats, custom start | Direct-on-page editing, first/odd/even variants, document metadata fields |
| Navigation | Clickable outline, case/whole-word find/replace, match highlights, semantic statistics; heading links with DOCX/PDF destinations; automatic TOC/update from layout; named paragraph bookmarks with rename/delete/navigation and DOCX/PDF links | Character-range bookmarks, editing existing link targets, imported live TOC reconstruction |
| Review/references | Native anchored comments with multi-paragraph associations, detached-text retention, sidebar edit/delete/resolve/reopen; named paragraph bookmarks and modular grammar protocol | Modern Word reply threads and collaboration metadata, track changes, footnotes/endnotes, equation layout |
| DOCX | Real OPC ZIP/XML; common text, headings, lists/tables/images, anchored comments and resolved state, page geometry, running content, fields on export; import warnings | More Word/Pages/LibreOffice fixture coverage, advanced styles, custom compound numbering and restart rules, nested tables, tracked changes/notes, newer review metadata, field import, exact line-spacing fidelity |
| Other formats | Basic RTF (image omission disclosed), RTFD clipboard images, Markdown subset, UTF-8 text; native copies protect originals | RTF table import, complete CommonMark, external Markdown image bundles |
| Output | PDF vector text/links and native images/tables; page-range selection and metadata; native printing; shared glyph layout | PDF image-quality presets, PDF accessibility tags, color-management audit |
| Reliability | NSDocument lifecycle/autosave, native undo plus document transactions, atomic saves, separate recoverable snapshots, archive validation | Crash/power-loss/disk-full fault injection, long-session memory testing |
| Distribution | macOS CI, launch/render smoke artifacts, verified DMGs, versioned pre-releases and checksums | Developer ID signing, notarization, automatic updater |

Limits: 128 MB native/decompressed archive safety limit; 32 MB and 64 megapixels per decoded image; 100 rows and 20 columns per table; 2,000 page-layout containers. These are explicit implementation bounds, not performance guarantees. An unlayable object is reported and PDF/print is blocked rather than silently truncated.
