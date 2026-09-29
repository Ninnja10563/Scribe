# Track changes implementation plan

The review work is isolated on `development/review`; it is not an exposed editor feature yet.

The current editor uses semantic paragraphs/runs projected into a shared AppKit text storage. Native character formatting goes through NSTextView, while styles, lists and structural operations also use document transactions. Comments already preserve associations through attributed metadata. Track changes must cover both editing paths and retain native undo, input methods and selection.

The first implementation adds versioned run review metadata and core decisions for insertions, deletions and character formatting. Pending deletions retain original rich runs. Authors have stable identities independently of display names. Formatting decisions replay field differences in order, so rejecting an old bold change does not discard a later font-size change or a later accepted decision. Accept/reject operations must also rebase comments and reconcile deleted note references atomically.

Remaining integration:

1. Track paragraph separators explicitly, including split/merge semantics and paragraph formatting changes. Run-level operations alone cannot implement document-wide tracked typing.
2. Project review metadata without confusing author formatting with revision decoration. Preserve metadata through native undo, recovery and clipboard; do not inherit another author's revision when typing.
3. Integrate native typing, deletion, marked-text composition, formatting and document transactions. Group related typing changes without coalescing different authors or unrelated edits.
4. Expose Track Changes, previous/next, accept/reject current and all, with readable revision presentation and keyboard-accessible navigation. Test edits around pending deletions and accept/reject undo.
5. Implement actual Office XML insertion/deletion/format revision structures, author/date preservation and regression fixtures. Until supported, DOCX export of pending revisions must fail explicitly.
6. Validate native save/reopen/recovery, exported packages and screen/PDF output; profile large revision collections. Remove temporary editor gates only after native editing is safe.

Native format v14 is confined to this development branch. Existing v13 documents migrate in memory, with no pending review metadata. The application currently refuses to open pending revisions while interaction support is incomplete; attributed projection is being tested separately for lossless preservation. No track-changes release or manual Word/accessibility validation is claimed.
