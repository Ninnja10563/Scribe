Scribe 0.11.0 adds reversible image adjustments.

- Image Properties provides crop percentages for each original edge, clockwise rotation, opacity, size and accessibility descriptions. Reset restores uncropped proportions. Changes support Undo/Redo, and source image bytes remain intact.
- Inline layout and PDF use the adjusted image frame; large images are scaled to fit the writing area. DOCX uses real DrawingML crop, rotation and alpha transforms with the original asset.
- Rich-text clipboard copies retain the adjusted appearance as a flattened image (144 dpi, bounded to 16 megapixels), without altering the native document. RTF export explicitly discloses image omission; DOCX and PDF retain images.
- Native format v9 migrates earlier documents in memory. Distinct images sharing an identifier no longer overwrite each other during DOCX export.

This remains a development release. Crop handles and floating image wrapping remain unfinished. Tall cells cannot continue across pages; unsafe PDF/print output is blocked. Independent sections, track changes, footnotes/endnotes, equations and shapes also remain unfinished. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
