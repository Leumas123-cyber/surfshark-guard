#!/bin/bash
# Build a portable Apple Silicon app bundle with no local machine paths
# or debug residue in the binary.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
APP="build/SurfsharkGuard.app"
BIN_OUT="$APP/Contents/MacOS/SurfsharkGuard"

if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

# Full Xcode (or GitHub's macos-14 image) can run XCTest. Command Line Tools
# alone often cannot load XCTest/Testing — skip locally, fail in CI.
if [ -n "${CI:-}" ] || [ -d /Applications/Xcode.app/Contents/Developer ]; then
  echo "▸ Testing…"
  swift test --arch arm64
else
  echo "▸ Skipping swift test (needs full Xcode; GitHub Actions still runs it)"
fi

echo "▸ Building release (arm64, no debug info)…"
swift build -c release --arch arm64 \
  -Xswiftc -gnone \
  -Xswiftc -O \
  -Xswiftc -file-prefix-map \
  -Xswiftc "${ROOT}=." \
  -Xcc "-ffile-prefix-map=${ROOT}=."

BIN_SRC=""
for cand in \
  .build/arm64-apple-macosx/release/SurfsharkGuard \
  .build/release/SurfsharkGuard \
  .build/out/Products/Release/SurfsharkGuard
do
  if [ -f "$cand" ]; then
    BIN_SRC="$cand"
    break
  fi
done
if [ -z "$BIN_SRC" ]; then
  echo "error: release binary not found" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_SRC" "$BIN_OUT"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# Drop leftover symbol / path tables that Swift may still emit.
strip -xS "$BIN_OUT"

# Ad-hoc sign so the bundle is a valid app on any Apple Silicon Mac.
# Recipients still need to right-click → Open the first time (Gatekeeper),
# or build from source on their own machine.
codesign --force --sign - --timestamp=none "$APP"
xattr -cr "$APP" 2>/dev/null || true

echo "▸ Checking the binary for local residue…"
if strings "$BIN_OUT" | grep -E '/Users/|/home/|anonymous|Samuel|zcode' >/dev/null; then
  echo "error: binary still contains a local path or personal token" >&2
  strings "$BIN_OUT" | grep -E '/Users/|/home/|anonymous|Samuel|zcode' >&2
  exit 1
fi

touch "$APP"

echo "▸ Creating DMG…"
STAGE="build/dmg-root"
DMG="build/SurfsharkGuard-1.1-arm64.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/SurfsharkGuard.app"
ln -s /Applications "$STAGE/Applications"
# Avoid copying Finder junk into the image.
find "$STAGE" -name '.DS_Store' -delete
xattr -cr "$STAGE" 2>/dev/null || true
hdiutil create -volname "Surfshark Guard" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
xattr -cr "$DMG" 2>/dev/null || true
rm -rf "$STAGE"

echo "✅ $APP"
echo "   DMG:      $DMG"
echo "   Install:  open $DMG  (drag the app into Applications)"
