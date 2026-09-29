Scribe 0.8.0 adds cell and row formatting.

- Table → Cell Properties controls backgrounds, borders, padding, vertical alignment and paragraph alignment. Apply settings to one cell, a row, a column or the whole table.
- Table → Row Height sets a minimum height while allowing text to grow. Clear the value to return to automatic height.
- Formatting follows cells when rows or columns are inserted or deleted, and changes support Undo/Redo.
- DOCX imports/exports cell shading, uniform borders/padding, vertical alignment and minimum row heights. Exact heights and different edge insets/borders are explicitly approximated. PDF uses the same native table layout as the editor.
- Native format v7 preserves cell/row properties; v1–v6 documents migrate in memory.

This remains a development release. Merge/split, cell-range selection and drag sizing remain unfinished, along with independent sections, track changes, footnotes/endnotes, equations, shapes and floating objects. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages/LibreOffice validation remain pending.
