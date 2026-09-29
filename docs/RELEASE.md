Scribe 0.7.0 adds named paragraph bookmarks and improves page layout.

- Insert → Bookmark This Paragraph creates a named location. Bookmarks lets you navigate, insert a link, rename or delete it. Renaming preserves links; deleted paragraphs leave visible missing destinations that undo can restore.
- Word export uses actual named bookmarks and anchor links; PDF exports clickable destinations. Imported bookmarks inside paragraphs navigate to the paragraph start, with an import warning. Character-range bookmarks are not yet supported.
- Page Layout accepts custom paper dimensions and preserves fractional margins. Shrinking tables keeps their columns valid; image resizing preserves the original embedded bytes. Layout changes remain undoable.
- Fixes a crash caused by delayed editor callbacks after closing a document window; native lifecycle tests now run under Address Sanitizer.
- Fit Page considers both page dimensions. Fit Page and Fit Width follow window and paper-size changes; Actual Size restores 100%. Pinch zoom switches to a fixed scale.

The native document schema remains v6; v1–v5 files still migrate in memory. This is a development release. Independent sections, track changes, footnotes/endnotes, equations, shapes, floating objects and advanced tables remain unfinished. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages/LibreOffice validation remain pending.
