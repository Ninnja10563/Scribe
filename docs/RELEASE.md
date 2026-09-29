Scribe 0.20.0 improves structured editing, note drafts and long-document layout.

- Ordinary list joins and replacements now preserve semantic text, comments, bookmarks and exact Undo. Generated numbering no longer becomes saved text when deleting a list boundary.
- Typing, formatting, paste and native marked-input composition protect generated list markers. Cross-list composition keeps a stable document snapshot until committed and can be cancelled without changing the document.
- All footnote and endnote drafts share the native semantic editor. Lists introduced through paste support paragraph joins, Return, keyboard indentation and Undo. Apply commits marked input; Cancel discards the private draft.
- Existing wide or tall images and equations expand the private note draft's writing area without changing their stored sizes or the parent document's page settings. Wide drafts offer horizontal scrolling.
- Ordinary body layout can continue in scheduled batches, while export and explicit navigation complete layout synchronously. Document capture reuses repeated formatting conversions and recovery snapshots avoid duplicate capture work.
- Includes the 0.19.2 document-window lifetime fix and expanded native, sanitizer, package and rendered-output regressions.

Native format advances to v14 with explicit migrations from earlier formats. Earlier documents continue opening; files saved in v14 require Scribe 0.20 or later. Track Changes remains disabled while remaining editing paths and DOCX revision interoperability are completed. Internal review controls and tests are not a public Track Changes feature.

This is a development release for Apple Silicon, macOS 14+. Builds are ad-hoc signed, not notarized. Independent sections, floating objects, shapes and other professional features remain in development. Physical-Mac input/accessibility, manual Word/Pages and physical-printer validation remain pending. See docs/FEATURES.md and docs/VALIDATION.md.
