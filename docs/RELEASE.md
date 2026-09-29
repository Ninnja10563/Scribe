Scribe 0.14.0 adds a native paragraph ruler.

- Drag first-line, left and right indent markers; a page guide previews the position. Each completed drag is one undoable edit. Escape cancels.
- Indents follow page centering, zoom and horizontal scrolling. Mixed selections are indicated, and changing one indent preserves the other paragraph settings.
- View → Focus Ruler (⇧⌘R) provides keyboard access. Arrow keys move by one point; Shift-arrow moves by six. Escape returns to the document. Native accessibility slider actions are also supported.
- Focus mode hides the ruler and restores its previous visibility. View → Toggle Ruler controls it independently.
- Empty-paragraph indents survive saving and subsequent typing. Native, DOCX and PDF retain first-line, hanging and right indents.

The ruler currently edits ordinary and heading paragraphs. Lists, tables and generated table-of-contents entries use their existing controls. Custom tab stops are not yet supported.

This remains a development release. Floating images, independent sections, track changes, footnotes/endnotes, equations and shapes remain unfinished. Tall cells cannot continue across pages; unsafe PDF/print output is blocked. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
