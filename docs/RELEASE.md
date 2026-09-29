Scribe 0.21.0 adds explicit paragraph line heights and improves Word document fidelity.

- Paragraph and style dialogs now offer natural, multiple, minimum and exact line heights. Formatting applies through native layout, style inheritance, Undo and PDF output.
- Existing additional line gaps retain their meaning. Older Scribe documents migrate without changing their spacing; export explains when additional gaps cannot transfer to Word.
- DOCX imports and exports use Office's actual line-height rules and units, including document defaults, default paragraph styles and inherited line-height settings.
- Note clipboard data preserves the new paragraph formatting with a versioned payload.
- Expanded internal review interchange covers text, inline objects, notes, character formatting and paragraph-boundary revisions. Track Changes remains disabled while the remaining editing and interoperability work is completed.

Native format advances to v15. Earlier documents continue opening; files saved in v15 require Scribe 0.21 or later. Native and independently rendered LibreOffice fixtures verify the three explicit line-height modes. The macOS suite also checks dialog application, style controls, clipboard preservation and Undo.

This is a development release for Apple Silicon, macOS 14+. Builds are ad-hoc signed, not notarized. Independent sections, floating objects, shapes and other professional features remain in development. Physical-Mac input/accessibility, manual Word/Pages and physical-printer validation remain pending. See docs/FEATURES.md and docs/VALIDATION.md.
