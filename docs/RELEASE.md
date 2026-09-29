Scribe 0.19.0 adds footnotes and endnotes.

- Insert → Footnote (⌥⌘F) and Insert → Endnote (⌥⌘E) create semantic references with automatic, independent numbering. Format → Edit Note, the reference context menu, or clicking a note on its page opens a native rich-text editor. Cancel preserves the document; Apply is undoable.
- Footnotes reserve measured space beneath their references. Long notes continue across pages using native line fragments. Endnotes flow through linked text containers after the document body.
- Deleting or moving references updates ownership and numbering. Undo restores both references and content. Copy/Paste between Scribe documents creates independent notes and preserves their appearance; external clipboard recipients receive readable citation text.
- Native format v13 preserves structured note content and migrates earlier documents in memory. Native saving, recovery copies and reopening retain notes.
- DOCX imports and exports real footnote/endnote parts with rich paragraphs, images, equations and links. Missing, duplicate and nested note references are rejected; unsupported note numbering and placement are disclosed.
- PDF and printing share note glyph layout. PDF reference numbers link to notes, note labels link back, and note hyperlinks retain their destinations. Page-range exports omit links to excluded destinations.

This remains a development release. Notes currently use continuous decimal numbering and document-wide placement. Custom marks, numbering restarts, section-specific notes, tables or review anchors within notes, and continuous inline editing of note text remain future work. Large collections of notes need further profiling on physical Macs. Track changes, independent section editing, floating objects and shapes are still pending. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
