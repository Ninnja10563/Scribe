#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
scribe_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT
ditto build/Scribe.app "$staging_dir/Scribe.app"
ln -s /Applications "$staging_dir/Applications"
cp docs/INSTALL.md "$staging_dir/Read Me.md"
hdiutil create -volname "Scribe $scribe_version" -srcfolder "$staging_dir" -ov -format UDZO "build/Scribe-$scribe_version-arm64.dmg"
hdiutil verify "build/Scribe-$scribe_version-arm64.dmg"
(cd build && shasum -a 256 "Scribe-$scribe_version-arm64.dmg" > "Scribe-$scribe_version-arm64.dmg.sha256")
