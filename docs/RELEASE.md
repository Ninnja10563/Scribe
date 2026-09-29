# Scribe 0.22.0 — Launch and software updates

Fixed an ownership-registration bug that created editor windows without adding them to their document’s window list. Scribe now opens a blank editable document immediately at startup, before recovery scanning. Reopening Scribe from the Dock restores an existing window or opens a document when none remain. A dedicated packaged-app startup check covers window visibility, typing and reopening, separately from the document-rendering smoke test.

The Scribe menu adds Check for Updates, automatic checking and optional automatic downloading/installation through Sparkle 2.10.0. Update packages are verified with an embedded Ed25519 public key. The release workflow publishes the update feed only after the release DMG exists and required checks pass. Unsaved documents use the normal macOS document termination flow.

Install this version manually once: older Scribe builds do not contain an updater. Drag Scribe.app from the DMG into Applications. Subsequent compatible releases can use the new updater. Automatic installation is optional and can be changed in the Scribe menu.

This remains an ad-hoc-signed Apple Silicon development release for macOS 14 or later, not a Developer ID-signed or notarized build. Native format v15 remains unchanged. Floating-image development remains on its separate branch; this release does not enable floating images or Track Changes.

