# Installing Scribe

Scribe requires an Apple Silicon Mac and macOS 14 or later. Drag Scribe.app into Applications.

This is an early development build. Releases are ad-hoc signed, not Developer ID signed or notarized. macOS may block the first launch. Only if you trust this download, use System Settings → Privacy & Security → Open Anyway. Do not disable Gatekeeper globally.

The native .scribe format retains Scribe's supported document structure. Imported Word, RTF, Markdown, and text files open as new documents. Save a native copy before editing important work. Import warnings explain known fidelity losses.

To build yourself, install Xcode Command Line Tools and Swift 6, then run:

```sh
swift test
./scripts/build-app.sh
open build/Scribe.app
```

Starting with 0.22, use **Scribe → Check for Updates…** for manual checks. The same menu controls automatic checking and optional automatic downloading/installation. Install 0.22 manually once if upgrading from an older release. Keep the app in Applications rather than launching it from the mounted DMG so it can be updated. Update packages have Ed25519 signatures; these are separate from Apple's Developer ID signing and notarization.
