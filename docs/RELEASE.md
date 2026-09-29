Scribe 0.18.0 adds editable native equations.

- Insert → Equation provides mathematical source input, structure templates, size controls and a live preview. Format → Edit Equation and the contextual menu reopen an existing equation.
- Fractions, square/indexed roots, powers, subscripts, sums, products, integrals and Greek symbols use native vector layout. A bundled math font keeps rendering independent of installed fonts.
- Equations retain editable source through native save/reopen, autosave, undo and copying between Scribe windows. Other rich-text recipients receive a visible PNG; plain-text/Markdown/RTF exports retain readable source.
- DOCX contains real Office Math objects. Supported objects import as editable equations; unsupported constructs retain readable text with a warning.
- Oversized equations block PDF/printing before an existing export is overwritten. Native saving preserves the source.
- Native format v12 migrates earlier versions in memory without rewriting the original file.

This remains a development release. The equation engine implements a bounded mathematical subset, not full TeX. Matrices, accents, equation numbering, structural visual editing, advanced math kerning and multiline formulas remain unfinished. Equation color/weight controls and broad Word/Pages interoperability also remain future work. Track changes, notes, independent section editing, floating objects and shapes are still pending. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
