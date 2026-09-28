# Working on Scribe

Scribe is a native Swift/AppKit document-authoring app for Apple Silicon, not a web application. Preserve the structured model, native input/selection behavior and non-destructive file handling.

- Read README.md, docs/FEATURES.md and docs/DEVELOPMENT.md before changing architecture.
- Keep document semantics and serialization in DocumentCore; keep Office XML/ZIP handling in ImportExport; keep AppKit projection and interaction in Scribe.
- Run `swift test` and the native launch smoke test on macOS. Linux verifies only the portable core and interchange modules. Do not claim a macOS launch from a Linux build.
- Add regression coverage for format changes, object operations, pagination and data-loss bugs. Preserve earlier native format versions through explicit in-memory migrations.
- Test actual exported packages and rendered output; compilation alone is insufficient.
- The owner requested that changes be committed and pushed, and substantial validated updates published as DMG releases. Update Resources/Info.plist and docs/RELEASE.md, wait for macOS CI, then push a matching `vX.Y.Z` tag. The workflow builds and publishes the DMG. Never tag a known-failing revision.
- Development builds are ad-hoc signed. Do not claim Developer ID signing, notarization, manual interoperability or accessibility validation without evidence.
- Keep docs/FEATURES.md and docs/VALIDATION.md honest about implemented behavior, measured results and remaining work.
