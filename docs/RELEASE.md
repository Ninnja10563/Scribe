Scribe 0.5.0 development — typography and editing fidelity.

- Native saves retain concrete font faces such as Medium, Light and Condensed, alongside family, size and bold/italic overrides. Missing faces render with a fallback while preserving their original identity. Style faces remain inherited unless directly overridden.
- Native format v5 adds optional font-face identities. Earlier v1–v4 documents migrate in memory; their original files are not rewritten on opening. Files saved in v5 require Scribe 0.5 or newer.
- Find, Replace and statistics exclude generated list/page-break prefixes. Literal text resembling list numbers remains searchable. Unicode and multi-paragraph results map back to native selections.
- Page breaks inside Word paragraphs retain their position. Insert Page Break uses the current caret and native undo without adding an extra paragraph.
- Insert → Link to Heading creates stable internal destinations, including real Word bookmark links and PDF navigation. Duplicate heading names remain separate destinations.
- Includes anchored comments, flowing pages, styles, tables, inline images, recovery, native tabs, PDF/printing and DOCX interchange. Independent Office XML schema validation remains a release requirement.

This update is still under development. Specific font faces/intermediate weights may be approximated during DOCX export; the export dialog discloses this. Track changes, TOC, bookmarks, notes, shapes, equations, floating objects and advanced table/section layout remain unfinished. See docs/FEATURES.md and docs/VALIDATION.md for scope and measured results.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. No manual Word/Pages/LibreOffice or physical-Mac accessibility certification is claimed.
