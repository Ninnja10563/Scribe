Scribe 0.17.0 adds first-page and odd/even headers and footers.

- Headers and Footers offers Default, First Page and Even Pages settings. Empty first-page fields can leave the cover's running text blank; page numbers remain separately configured.
- Alternate text is retained when its display option is switched off. Custom starting page numbers determine odd/even parity, with the first-page setting taking precedence.
- Screen, PDF and printing use the same page-specific running text. Changes participate in document undo, autosave and native save/reopen.
- DOCX uses real first/default/even header and footer parts, section title-page settings and document even/odd settings. Import retains those variants and custom starting parity.
- Overlong or multiline running text produces a warning and blocks PDF/printing instead of silently losing text. Dormant variants do not block output.
- Even-numbered starts have a compatibility notice: Scribe follows Word’s documented numbering-based header parity; LibreOffice uses physical page order.
- Native format v11 migrates earlier versions in memory without rewriting source files.

This remains a development release. Headers and footers currently contain single-line plain text; direct on-page editing, rich formatting and metadata fields remain unfinished. Imported Word running fields remain cached text with a warning. Track changes, notes, independent section editing, floating objects, shapes and equations are still pending. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Physical-Mac input/accessibility and manual Word/Pages validation remain pending.
