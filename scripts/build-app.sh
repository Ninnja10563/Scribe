#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Scribe.app requires macOS and Xcode Command Line Tools." >&2
  exit 1
fi
swift build -c release --arch arm64
binary_dir="$(swift build -c release --arch arm64 --show-bin-path)"
app_dir="$PWD/build/Scribe.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Scribe" "$app_dir/Contents/MacOS/Scribe"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
mkdir -p "$app_dir/Contents/Frameworks"
sparkle_framework=$(find .build/artifacts -type d -path '*/macos-arm64_x86_64/Sparkle.framework' -print -quit)
test -n "$sparkle_framework"
ditto "$sparkle_framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
cp LICENSE "$app_dir/Contents/Resources/LICENSE"
cp Resources/Sparkle-LICENSE.txt "$app_dir/Contents/Resources/Sparkle-LICENSE.txt"
cp -R Sources/Scribe/Resources/MathFont "$app_dir/Contents/Resources/"
swift scripts/make-icon.swift build/Scribe.iconset
iconutil -c icns build/Scribe.iconset -o "$app_dir/Contents/Resources/Scribe.icns"
codesign --force --deep --sign "${SCRIBE_SIGNING_IDENTITY:--}" "$app_dir"
codesign --verify --deep --strict "$app_dir"
file "$app_dir/Contents/MacOS/Scribe"
echo "Built $app_dir"
