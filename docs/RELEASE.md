Scribe 0.13.0 improves superscript/subscript rendering and font-state reliability.

- Superscript and subscript use reduced native glyphs and size-relative baseline offsets on screen and in vector PDF/print output. Format → Normal Baseline restores ordinary text.
- Repeated script commands do not compound font scaling. Font-family, size and trait editing use the logical font; the Font panel reports that size and genuine mixed-font selections.
- Native files, DOCX and rich-text clipboard exports retain semantic script levels and logical sizes. RTF/RTFD copying avoids double scaling.
- Character formatting in an empty paragraph survives saving, reopening and subsequent typing. Font/script changes there are undoable and mark the document for autosave.
- Unchanged formatting no longer adds redundant undo operations.

This remains a development release. A draggable ruler, paragraph-mark background refinement, floating images, independent sections, track changes, footnotes/endnotes, equations and shapes remain unfinished. Tall cells cannot continue across pages; unsafe PDF/print output is blocked. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
