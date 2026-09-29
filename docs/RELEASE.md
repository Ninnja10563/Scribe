Scribe 0.12.0 expands native paragraph-style editing.

- Create styles from the current text formatting. A native two-tab editor provides font family and face, traits, colors, spacing, indents, alignment and outline level, with a preview.
- Creating and applying a style is one undoable operation. Duplicate style names are rejected. Definition changes update inherited formatting while preserving direct overrides.
- Native format v10 distinguishes explicitly removed highlighting from inherited highlighting; DOCX retains highlight and superscript/subscript resets. Earlier native versions migrate in memory.
- The style picker now follows the actual selected paragraph, including immediately after outline navigation. Initial typing inherits the opening paragraph’s formatting.
- Paragraph spacing and indentation changes are undoable and mark empty documents for autosave. Invalid geometry remains in the dialog for correction.
- Includes the 0.11.1 native rich-clipboard image correction.

This remains a development release. A draggable ruler, style-parent editor, floating images, independent sections, track changes, footnotes/endnotes, equations and shapes remain unfinished. Tall cells cannot continue across pages; unsafe PDF/print output is blocked. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
