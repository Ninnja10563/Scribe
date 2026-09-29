# Software updates

Scribe 0.22 introduces Sparkle 2.10.0. Install this release manually once when upgrading from an older version, then keep Scribe in Applications rather than on its mounted DMG.

The Scribe menu provides **Check for Updates…**, **Automatically Check for Updates**, and **Automatically Download and Install Updates**. Checking is enabled by default; automatic downloading/installation is optional. Sparkle stores these preferences and uses the normal application termination flow when installation requires quitting.

## Release publishing

1. Increase both the marketing version and build number in `Resources/Info.plist`, and update `docs/RELEASE.md`. Build numbers must increase so existing installations recognize the update.
2. Commit and push the candidate. Wait for full macOS, startup, installer and independent Office validation to pass.
3. Push the matching `vX.Y.Z` tag for the validated revision. The release workflow builds and tests the DMG, publishes its asset and checksum, then advances the HTTPS appcast on the `updates` branch.
4. Download the published DMG and checksum. Verify the checksum and appcast signature against `SUPublicEDKey` in the released app's configuration before announcing the release.

After downloading the DMG and adjacent `.sha256` file, run `python scripts/verify-published-update.py /path/to/Scribe-X.Y.Z-arm64.dmg` from the released checkout (with `cryptography` installed). Use `--info-plist` to specify the configuration from another released checkout. The verifier checks the actual public feed, version/build, asset URL, size, checksum and Ed25519 signature.

The release job reads `SCRIBE_UPDATE_PRIVATE_KEY` from repository secrets. Only its public key is embedded in the app. Keep that public key stable: replacing it requires a planned key-rotation migration for existing installations. The publishing script refuses to sign with a key that does not match the app and refuses to move the feed to a lower build number.

## Validation and signing scope

`verify-updater.py` compiles the upstream Sparkle diagnostic CLI against the bundled framework. It uses disposable app copies and an ephemeral key to reject a forged signature, install a correctly signed DMG, verify the installed bundle and executable, and launch the installed app. Production signing credentials are not used by that test.

Update-package Ed25519 signatures are separate from Apple's Developer ID signing and notarization. Current development DMGs remain ad-hoc signed. The automated installer test does not establish physical-Mac Gatekeeper or notarization validation.
