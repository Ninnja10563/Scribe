# Scribe 0.23.0 — Formatting in your document window

Font controls now live in a document-local Format sidebar instead of a separate font panel. Open it with the toolbar’s text-format button or Command–T. Choose an installed font family, its typeface/weight and a fractional point size. Selection changes refresh the controls; mixed selections identify that the first character’s font is displayed.

The sidebar brings together bold, italic, underline, strikethrough, superscript/subscript, normal baseline, text and highlight colour palettes, all four alignments, six line-spacing presets, six list numbering formats, indentation, paragraph spacing and style editing. Detailed spacing and list settings retain their existing dialogs.

New commands increase/decrease font size, convert selections to uppercase/lowercase, copy/paste character formatting, clear direct character or paragraph formatting, indent/outdent and toggle a page break before selected paragraphs. Copying formatting preserves destination links and object identities. Clearing formatting restores the named style. Empty-paragraph formatting is saved and undoable.

The Format sidebar and Find bar use a short reveal animation. macOS Reduce Motion disables it. Focus mode hides and restores the Format sidebar.

This is a broader everyday formatting workspace, not complete Microsoft Word formatting parity. Advanced typography, custom tabs, paragraph borders/shading, columns, keep-with-next and widow/orphan controls remain future work. Native format v15 is unchanged. Apple Silicon/macOS 14+, ad-hoc signed; Developer ID signing and notarization are not configured. Existing 0.22 installations can receive this release through the signed updater after publication.
