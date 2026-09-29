Scribe 0.9.0 adds merged table cells.

- Merge a rectangle starting at the current cell, preserving all text, paragraph identities, comments and bookmarks.
- Split a merged cell back into its grid; existing text stays in the first cell.
- Row/column edits resize intersected spans and preserve content when a merged anchor survives deletion.
- Native table layout and Tab navigation understand merged cells. DOCX uses actual gridSpan and vMerge properties, with an independent import fixture.
- Native format v8 migrates v1–v7 documents in memory.

This remains a development release. Cell-range selection, drag sizing and nested tables remain unfinished, along with independent sections, track changes, footnotes/endnotes, equations, shapes and floating objects. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages/LibreOffice validation remain pending.
