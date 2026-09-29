# Floating image development

This work starts from the published 0.21 release and includes the subsequently validated paragraph-review integration. Existing images are semantic text-run objects projected as native attachments. Shared TextKit containers paginate body glyphs; footnotes reserve actual container height. PageCanvas draws page furniture and native text views draw body text. PrintRenderer draws the same glyph layout separately. Image selection/resize, original assets, adjustments and clipboard metadata already exist and must be preserved.

The first model step adds optional, bounded image placement in native v16. An absent placement remains inline through an in-memory migration. A floating image keeps its semantic text anchor; its position is measured from the writing margins of the page containing that anchor. Square wrapping, behind-text and in-front modes share the same placement model. Initial floating anchors are restricted to ordinary body paragraphs, outside notes, tables and generated contents. Native opening/recovery and DOCX export are gated until rendering and interchange are ready; no floating editing UI is exposed yet.

Implementation sequence:

1. Preserve placement, asset bytes and identities through native serialization, Undo and clipboard versions. Keep inline behavior unchanged.
2. Project a semantic floating anchor without making the image occupy an inline line box. Use common image drawing for the page, PDF and print; separate behind/front layers from native text selection.
3. Resolve the anchor's physical page using TextKit glyph layout. Square wrapping uses actual [NSTextContainer exclusion paths](https://developer.apple.com/documentation/appkit/nstextcontainer/exclusionpaths). Reflow must converge under a bounded pass count; unresolved anchors or overflow must block output, never silently disappear.
4. Add native placement controls, selection and reversible drag/resize with keyboard/accessible alternatives. Preserve original crop/rotation/opacity data.
5. Implement real Office anchored-drawing positions/wrap settings and explicit import warnings for unsupported reference systems. Extend package, PDF and independent Office regression fixtures.
6. Test page-boundary typing, anchor deletion/Undo, notes sharing a page, multiple objects, pagination stability, close lifetime and large documents before removing gates or publishing a release.

Current layout batches only ordinary body flow. Complex floating layout may initially use a complete pass, as notes and tables currently do. Virtualization and tight contours remain separate work. This is a development plan, not an implemented floating-layout claim.

The initial native prototype uses zero-size attachment cells to retain text anchors and cache source images. Behind/front page drawing and PDF drawing use the same resolved frames; square mode still blocks output until exclusions are implemented. Floating clipboard payloads use v4; external RTFD copies contain a visible inline rendering. Each text occurrence is its own layout anchor. Image asset UUIDs may repeat, matching existing copy behavior, so shared asset identity must not be mistaken for a duplicate anchor. Native projection, frame, clipboard and PDF tests are awaiting macOS execution.

Behind/front native projection passed targeted macOS tests and measured PDF inspection. The square-wrap prototype now iterates real container exclusions until image page assignments settle, clears exclusions when converting back to inline, and blocks output on a repeated or over-budget layout state. Native square wrapping, mutation/Undo and page-boundary coverage are the next checks; public gates remain unchanged.

Square-wrap screen/PDF inspection and independent geometry, text and paint-order verification passed at `6bc3de9`. Anchor typing/deletion/Undo and overflow refusal are under native test; the merged portable suite passes 236 tests (one platform placeholder skipped). Multiple occurrences of one asset and footnotes sharing a page now have a combined native regression. Public placement controls, object gestures and Office anchored-drawing interchange remain unimplemented.
