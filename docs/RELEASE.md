Scribe 0.2.0 adds structured tables and inline images to the native macOS document workspace.

- Insert tables, edit cell text, use Tab/Shift-Tab between cells, add/delete rows and columns, and change widths, padding, borders, and header-row shading.
- Insert PNG/JPEG/HEIC/TIFF images, paste images, or drop image files from Finder. Resize images proportionally with selection handles or a dialog and edit accessibility descriptions.
- Save/reopen table and image structure in native format v2. Version 1 documents migrate in memory without overwriting their source.
- DOCX now contains genuine table, image, header/footer, and page-field parts. Basic tables and inline images also import.
- PDF export retains link annotations and uses the same glyph/table/image layout as the editor.
- Includes the v0.1 foundations: linked pages, named styles, outline, rich text, search/replace, page settings/numbers, native document lifecycle, recovery, focus mode, tabs, printing, and text interchange.

For Apple Silicon and macOS 14+. This is an early development release, not a finished Word/Pages replacement. Merged/nested-table fidelity, image cropping/rotation, floating objects, wrapping, shapes, review UI, track changes, footnotes, equations, and automatic TOC remain unimplemented. DOCX still approximates advanced styles/numbering and fields. Manual interoperability and accessibility validation are pending.

The DMG is ad-hoc signed and not notarized. See its installation instructions and the repository's validation notes. Use the supplied SHA-256 checksum to verify the downloaded installer.
