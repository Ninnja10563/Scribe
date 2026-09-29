Scribe 0.10.0 adds document properties and spelling-language controls.

- File → Document Properties edits title, author and the document’s spelling language, with Undo/Redo.
- Native checking uses per-document orthography options; automatic language detection is available without changing the system spelling preference.
- The status bar displays the actual document language.
- DOCX carries title/author/language in real core properties and default spelling language in Word styles. Imports retain metadata and disclose mixed-language approximations.

This remains a development release. Tall cells cannot continue across pages; unsafe PDF/print output is blocked. Independent sections, track changes, footnotes/endnotes, equations, shapes and floating objects remain unfinished. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages/LibreOffice validation remain pending.
