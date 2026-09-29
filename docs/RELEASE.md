Scribe 0.16.0 adds native hierarchical outline navigation.

- Headings form a tree based on their levels, with native disclosure controls. Skipped levels attach to the nearest preceding lower-level heading.
- Collapsed headings and selected heading identity survive text changes, renames and outline refreshes within the document window.
- View → Focus Outline supports keyboard navigation. Left/Right collapse or expand, Up/Down select headings, Return moves into the document and Escape returns to editing.
- Clicking navigates while keeping the outline focused; double-clicking begins editing at the heading. The context menu expands or collapses all headings.
- Long heading titles remain available through tooltips and native accessibility labels.

This remains a development release. Collapsing the outline does not hide document text. Track changes, footnotes/endnotes, independent section layout, floating objects, shapes and equations remain unfinished. DOCX interoperability and physical-Mac input/accessibility testing remain ongoing areas. See docs/FEATURES.md and docs/VALIDATION.md.

For Apple Silicon, macOS 14+. Development builds are ad-hoc signed, not notarized. Native file format remains v10.
