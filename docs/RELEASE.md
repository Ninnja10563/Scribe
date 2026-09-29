Scribe 0.19.2 fixes a document-window lifetime crash.

- Closed window controllers now detach from their document before it can deallocate. This prevents a stale document reference during subsequent key/main-window transitions.
- Regression coverage repeatedly opens and closes visible documents in one process, alongside the existing native lifecycle and editor tests.

Native format remains v13. Existing documents and editing features are unchanged. This is a development release for Apple Silicon, macOS 14+. Builds are ad-hoc signed, not notarized. Track changes, independent section editing, floating objects, shapes and other professional features remain in development. Physical-Mac input/accessibility and manual Word/Pages validation remain pending. See docs/FEATURES.md and docs/VALIDATION.md.
