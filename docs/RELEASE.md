Scribe 0.6.0 development adds automatic tables of contents.

- Insert → Table of Contents creates entries from heading styles, with hierarchy, internal links and page labels from the actual document layout. Choose how many heading levels to include.
- Update Table of Contents refreshes names, entries and page numbers. Layout repeats until page labels settle, and the whole command is one undo operation. Ordinary paragraphs placed between generated entries are retained.
- Remove Table of Contents removes generated entries while preserving surrounding document text. Comments associated with regenerated text remain available as detached comments.
- Native format v6 stores TOC definitions and generated-entry associations; v1–v5 documents migrate in memory.
- DOCX exports a real Word TOC field with cached entries and bookmark links. Import currently retains the cached text/links and explains that a Scribe TOC must be inserted to regenerate it.

This update is under development. Generated TOC entry text is replaced on Update; keep notes in separate ordinary paragraphs and modify the Contents styles for consistent formatting. Independent section layout, track changes, named bookmark editing, notes, equations, shapes, floating objects and advanced tables remain unfinished. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages/LibreOffice validation remain pending.
