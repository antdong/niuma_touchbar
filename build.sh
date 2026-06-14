#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

ARCH="$(uname -m)"
APP="build/NiuMaBar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O \
  -target "$ARCH-apple-macosx12.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/NiuMaBar"

codesign --force --sign - "$APP"
echo "✓ Built $APP"
