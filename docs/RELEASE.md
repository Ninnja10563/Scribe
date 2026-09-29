Scribe 0.19.1 adds search and replace inside footnotes and endnotes.

- Find includes note text in reference order, with case and whole-word matching. Navigation reveals the actual page containing a result, including long-note continuation pages. Generated note numbers and list markers are excluded.
- Replace and Replace All preserve note identities, formatting and list definitions. All proposed replacements are validated before the document changes, and a batch is one undoable action.
- Command-G and Shift-Command-G navigate results; Enter and Shift-Enter work in the Find field. Match feedback distinguishes note results, and the status bar identifies their page.
- Find highlights refresh asynchronously after pagination and remain editing-only.
- Listed notes now shift their tab stops with the note indentation, preventing an unnecessary wrap after generated markers.

Native format remains v13. This is a development release for Apple Silicon, macOS 14+. Builds are ad-hoc signed, not notarized. Track changes, independent section editing, floating objects, shapes and other professional features remain in development. Physical-Mac input/accessibility and manual Word/Pages validation remain pending. See docs/FEATURES.md and docs/VALIDATION.md.
