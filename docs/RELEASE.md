Scribe 0.4.0 adds anchored comments and native review controls.

- Select text and choose Review → Add Comment (Command–Shift–M), or use the text context menu. The comments sidebar supports navigation, editing, deletion, resolution and reopening, with a filter for resolved comments.
- Comments can span paragraphs and overlap. Associations follow native text editing and semantic list splits. Deleting their text retains detached comments; native undo can restore the association. Comment operations themselves are undoable.
- DOCX imports/exports actual comment parts, author/text data and range markers. Word 2013 resolved status is retained through the commentsExtended part. Namespace aliases and relationship-specified comment/style/numbering filenames are supported.
- Native format v4 preserves multi-paragraph and detached anchors. v1/v2/v3 documents migrate in memory without overwriting their original bytes. Files saved in v4 require Scribe 0.4 or newer.
- Empty final paragraphs retain their style and identity when focus moves away. Review navigation keeps keyboard focus in the sidebar and remembers the selected document page.
- Includes the existing pagination, styles, lists, tables, inline images, search, recovery, tabs, printing and DOCX/PDF/text interchange. PDF export supports page ranges and metadata.

For Apple Silicon and macOS 14+. This remains a development release. Track changes, footnotes/endnotes, equations, automatic TOC, merged/nested tables, floating objects, wrapping and independent section layout remain unfinished. DOCX reply threads are flattened with a warning; newer collaboration metadata is limited. Detached comments are preserved in the package but may be hidden by other editors. Physical-Mac input/accessibility audits and manual Word/Pages/LibreOffice checks remain pending.

The DMG is ad-hoc signed and not notarized. A SHA-256 checksum is provided. See docs/VALIDATION.md for automated native tests and independent package/PDF checks.
