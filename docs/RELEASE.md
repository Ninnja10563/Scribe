Scribe 0.11.1 fixes adjusted-image copying.

Ordinary macOS Copy requested a legacy RTFD type name that bypassed the 0.11 image exporter. Copies could paste the original, uncropped image. Scribe now handles both current and legacy RTFD requests, and regression tests exercise the full native Copy path. Native documents, DOCX and PDF were unaffected.

This release includes the reversible crop, clockwise rotation and opacity controls introduced in 0.11.0. Rich-text clipboard images are flattened at 144 dpi, bounded to 16 megapixels; original source data remains in the Scribe document.

This remains a development release. Floating image wrapping, independent sections, track changes, footnotes/endnotes, equations and shapes remain unfinished. Tall cells cannot continue across pages; unsafe PDF/print output is blocked. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
