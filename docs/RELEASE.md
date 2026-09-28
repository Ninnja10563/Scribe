Scribe 0.3.0 improves native list editing, Word numbering interoperability, and PDF export.

- Continue independent numbered lists across body paragraphs, restart at a chosen value, and use upper/lower letter or Roman numbering. Format → List Options exposes nesting, starts and removal; Continue Previous List reconnects a separated item.
- Return splits a list item while preserving formatted Unicode text. Return on an empty item exits/outdents; Backspace at the content start outdents. These commands support undo/redo.
- DOCX import resolves actual numbering definitions, level/start overrides and numbering inherited through paragraph styles. Export preserves independent lists and restarts instead of sharing one numbering instance across every list.
- PDF export now accepts page ranges such as 1, 3–5 and title, author, subject and keywords. Selected pages retain original page numbers, vector text and image quality. Invalid ranges cannot overwrite an existing output file.
- Native format v3 preserves list identities and restarts. Earlier v1/v2 documents migrate in memory; opening does not overwrite their original bytes. Saving in v3 requires Scribe 0.3 or newer to reopen.
- Includes the existing native pagination, styles, tables, inline images, outline, search, recovery, tabs, printing and interchange features.

For Apple Silicon and macOS 14+. This is an early development release. Review UI, tracked changes, notes, equations, automatic TOC, merged/nested tables, floating objects and wrapping remain unfinished. DOCX custom compound markers, custom nested restart rules and advanced styles remain limited; known import losses are disclosed. PDF image-quality presets remain pending. Physical-Mac input/accessibility testing and manual Word/Pages/LibreOffice interoperability have not been completed.

The DMG is ad-hoc signed and not notarized. A SHA-256 checksum is provided with the installer. See docs/VALIDATION.md for automated and independent artifact checks.
