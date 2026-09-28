# Repository assessment and development plan

## Starting point

Inspected on 28 September 2026. HEAD was `6591ce4` (Initial commit). The entire tracked repository contained LICENSE only. There were no source files, build configuration, tests, application, tags, releases, or existing version. No working implementation was replaced. The development host is ARM64 Debian Linux without Xcode/AppKit. An existing-app build, test run, and launch were impossible because no app existed.

## Architecture decisions

- Swift Package Manager, Swift 6 toolchain, macOS 14 minimum, Apple Silicon release builds. Swift 5 language mode currently avoids making the AppKit integration contingent on a full Swift 6 concurrency audit.
- DocumentCore is Foundation-only: semantic paragraphs/runs, sections/page settings, stable IDs, named styles with direct overrides, comments/bookmark anchor types, search, validation, atomic native saves, and recovery storage. Comments/bookmarks are schema groundwork, not user-facing features yet.
- ImportExport implements actual OPC ZIP/XML for a limited DOCX subset, without launching third-party converters. Stored and DEFLATE ZIP inputs are supported. Paths are never extracted to disk. CRC checks, size limits, duplicate path rejection and disabled external XML entities constrain hostile files.
- AppKit owns windows, responders, NSDocument lifecycle, selection, input methods, accessibility, rich clipboard, spelling and undo. A shared NSTextStorage feeds an NSLayoutManager with fixed-size linked NSTextContainers. Containers are physical writing areas, not independent text boxes. TextKit determines glyph overflow and page boundaries.
- TextKit 1 is a deliberate initial choice: its linked container/text view support provides a proven native pagination path. TextKit 2 viewport layout is a future profiling-led migration, not an assumption that modern API names alone guarantee professional pagination.
- The editor's attributed text is a projection. The native file stores semantic JSON, not an opaque attributed-string archive. Direct formatting inherits from named styles when equal to the style's definition.
- Screen, PDF and print use the same glyph layout. Native format writes are atomic. Recovery writes are debounced into a separate Application Support directory and never overwrite source documents.

## Milestones

1. **Native foundation:** buildable application, styled paragraphs, flowing pages, native lifecycle, file validation, basic interoperability, release automation.
2. **Editing hardening:** manual IME/VoiceOver/selection/undo testing, list behavior, clipboard provenance, incremental paragraph projection, page virtualization, long-document profiling.
3. **Structured objects:** tables with cell operations and spanning, embedded assets, accessible inline images, editable geometry, floating anchors/exclusion paths, shapes. These require model and undo migrations before UI exposure.
4. **Document structure:** independent sections, editable running content, page fields, TOC, bookmarks, links, footnote/endnote layout and reference numbering.
5. **Review:** anchored comments with edit transforms, reversible tracked operations, acceptance/rejection, modular grammar engines.
6. **Interoperability:** Word/Pages/LibreOffice fixture corpus, table/image/numbering/section/header relationships, OOXML preservation of unsupported parts where safe, Markdown syntax coverage, PDF links and export options.
7. **Distribution:** Developer ID signing and notarization once credentials are available, update strategy, crash reporting with consent and privacy controls.

Each substantial, validated update should advance the version and publish a tagged DMG release. Do not publish a release merely because source files were generated. The CI release job depends on tests, an arm64 bundle, launch, pagination, native save, PDF output and rendering checks.
