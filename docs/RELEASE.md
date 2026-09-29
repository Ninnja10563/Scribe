Scribe 0.15.0 improves long-document typing layout and image resize gestures.

- Ordinary text insertions reuse following pages once pagination reaches an unchanged boundary. Paragraph breaks, deletions, formatting, page geometry changes and documents containing tables use the existing full affected-range layout path.
- Initial opening and subsequent reflow now agree at page boundaries with mixed paragraph styles and line spacing. Creating another page also preserves the current typing font.
- Image corner handles respond to vertical as well as horizontal movement while preserving proportions. Escape cancels a resize without adding an undo step.
- A resize remains valid when shrinking the image moves it to an earlier page. Source image bytes, crop/rotation/opacity and native undo are retained.
- Selection handles appear only on the page containing the image.

This remains a development release. Page views are not yet virtualized, and the layout measurements do not cover all input, autosave or recovery costs. Floating images, independent sections, track changes, footnotes/endnotes, equations and shapes remain unfinished. Tall cells cannot continue across pages; unsafe PDF/print output is blocked. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
