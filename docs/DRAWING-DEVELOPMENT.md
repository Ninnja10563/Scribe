# Floating image development

This work starts from the validated 0.21 candidate. Existing images are semantic text-run objects projected as native attachments. Shared TextKit containers paginate body glyphs; footnotes reserve actual container height. PageCanvas draws page furniture and native text views draw body text. PrintRenderer draws the same glyph layout separately. Image selection/resize, original assets, adjustments and clipboard metadata already exist and must be preserved.

The first model step adds optional, bounded image placement in native v16. An absent placement remains inline through an in-memory migration. A floating image keeps its semantic text anchor; its position is measured from the writing margins of the page containing that anchor. Square wrapping, behind-text and in-front modes share the same placement model. Initial floating anchors are restricted to ordinary body paragraphs, outside notes, tables and generated contents. Native opening/recovery and DOCX export are gated until rendering and interchange are ready; no floating editing UI is exposed yet.

Implementation sequence:

1. Preserve placement, asset bytes and identities through native serialization, Undo and clipboard versions. Keep inline behavior unchanged.
2. Project a semantic floating anchor without making the image occupy an inline line box. Use common image drawing for the page, PDF and print; separate behind/front layers from native text selection.
3. Resolve the anchor's physical page using TextKit glyph layout. Square wrapping uses actual [NSTextContainer exclusion paths](https://developer.apple.com/documentation/appkit/nstextcontainer/exclusionpaths). Reflow must converge under a bounded pass count; unresolved anchors or overflow must block output, never silently disappear.
4. Add native placement controls, selection and reversible drag/resize with keyboard/accessible alternatives. Preserve original crop/rotation/opacity data.
5. Implement real Office anchored-drawing positions/wrap settings and explicit import warnings for unsupported reference systems. Extend package, PDF and independent Office regression fixtures.
6. Test page-boundary typing, anchor deletion/Undo, notes sharing a page, multiple objects, pagination stability, close lifetime and large documents before removing gates or publishing a release.

Current layout batches only ordinary body flow. Complex floating layout may initially use a complete pass, as notes and tables currently do. Virtualization and tight contours remain separate work. This is a development plan, not an implemented floating-layout claim.
