# Feature status — Scribe 0.2

This is a foundation release. “Implemented” means there is working code and an exposed editing path, not that the feature has the interoperability coverage of a mature word processor.

| Area | Implemented | Still needed |
| --- | --- | --- |
| Native application | Swift/AppKit, arm64 bundle, document windows and tabs, menus, native spelling, focus mode, zoom, light/dark chrome | Physical-Mac keyboard/IME/VoiceOver audit, richer preferences |
| Document model | Versioned semantic paragraphs/runs, sections, styles, tables/cell references, inline images, IDs; v1→v2 migration | More block types, independent section editing, preservation of future extension payloads |
| Pagination | Shared TextKit layout across actual page containers; A4/Letter/Legal, orientation, margins, page breaks | Virtualization, widow/orphan controls, configurable hyphenation, typography audit |
| Formatting | Fonts/size via native panel, common traits, color/highlight, super/subscript, alignment, spacing and indents | Draggable ruler, granular font-weight UI |
| Styles | Built-in headings/title/body/quote/caption, custom creation/modification/deletion, live definition updates, outline navigation | Style inheritance editor, collapsible heading content |
| Lists | Bullets/numbering, nested marker model, native list paragraphs, Tab/Shift-Tab indentation | Full restart/continuation UI and native Return/delete behavior audit |
| Tables | Editable cells, insertion, add/delete rows/columns, Tab navigation, column widths, padding/borders, header shading; TextKit layout | Merge/split, drag sizing, row-height control, cell-range selection, nested tables, merged-cell import |
| Images | PNG/JPEG/HEIC/TIFF insertion, Finder drop, image paste, inline layout, proportional resizing by handles or dialog, alt text | Cropping, rotation, opacity, floating placement/wrapping |
| Running content | Text headers/footers; top/bottom, left/centre/right page numbers and formats, custom start | Direct-on-page editing, first/odd/even variants, document metadata fields |
| Navigation | Clickable outline, case/whole-word find/replace, match highlights, statistics | Automatic TOC, bookmark UI, internal-link editing |
| Review/references | Comment/bookmark schema and modular grammar protocol only | Comment UI and edit-aware anchors, track changes, footnotes/endnotes, equation layout |
| DOCX | Real OPC ZIP/XML; common text, headings, basic lists/tables/images, page geometry, running content, fields on export; import warnings | Word/Pages/LibreOffice fixture coverage, advanced styles/numbering, merged/nested tables, review data, field import, exact line-spacing fidelity |
| Other formats | Basic RTF, Markdown subset, UTF-8 text; native copies protect originals | RTF table import, complete CommonMark, external Markdown image bundles |
| Output | PDF vector text/links and native images/tables; native printing; shared glyph layout | PDF page-range/quality UI, PDF accessibility tags, color-management audit |
| Reliability | NSDocument lifecycle/autosave, native undo plus document transactions, atomic saves, separate recoverable snapshots, archive validation | Crash/power-loss/disk-full fault injection, long-session memory testing |
| Distribution | macOS CI, launch/render smoke artifacts, verified DMGs, versioned pre-releases and checksums | Developer ID signing, notarization, automatic updater |

Limits: 128 MB native/decompressed archive safety limit; 32 MB per embedded image; 100 rows and 20 columns per table; 2,000 page-layout containers. These are explicit implementation bounds, not performance guarantees. An unlayable object is reported and PDF/print is blocked rather than silently truncated.
