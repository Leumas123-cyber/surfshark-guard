#!/bin/bash
# Build two portable app bundles (Apple Silicon only, and universal) with
# no local machine paths or debug residue in the binaries.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
ARM_APP="build/SurfsharkGuard-arm64.app"
UNI_APP="build/SurfsharkGuard.app"
ARM_DMG="build/SurfsharkGuard-${VERSION}-arm64.dmg"
UNI_DMG="build/SurfsharkGuard-${VERSION}-universal.dmg"

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

echo "▸ Selftest (parsers, keychain, detector, webui, updates)…"
mkdir -p .build
swiftc -parse-as-library -O -target arm64-apple-macos13 \
  -o .build/selftest \
  Sources/SurfsharkGuard/Parsers.swift \
  Sources/SurfsharkGuard/Detector.swift \
  Sources/SurfsharkGuard/QBittorrent.swift \
  Sources/SurfsharkGuard/WebUI.swift \
  Sources/SurfsharkGuard/Keychain.swift \
  Sources/SurfsharkGuard/VPNProvider.swift \
  Sources/SurfsharkGuard/UpdateCheck.swift \
  Sources/SurfsharkGuard/MenuBarTooltip.swift \
  scripts/selftest.swift
./.build/selftest

find_release_bin() {
  local scratch="$1"
  local found=""
  while IFS= read -r cand; do
    found="$cand"
  done < <(find "$scratch" -type f -name SurfsharkGuard \
            ! -path '*.dSYM*' ! -path '*Index*' 2>/dev/null | sort)
  if [ -n "$found" ]; then
    printf '%s' "$found"
    return 0
  fi
  return 1
}

build_arch() {
  local arch="$1"
  local scratch=".build/${arch}"
  echo "▸ Building release ($arch, no debug info)…"
  swift build -c release --arch "$arch" --scratch-path "$scratch" \
    -Xswiftc -gnone \
    -Xswiftc -O \
    -Xswiftc -target \
    -Xswiftc "${arch}-apple-macos13" \
    -Xswiftc -file-prefix-map \
    -Xswiftc "${ROOT}=." \
    -Xcc "-ffile-prefix-map=${ROOT}=."
  local src
  src="$(find_release_bin "$scratch")" || {
    echo "error: $arch release binary not found under $scratch" >&2
    exit 1
  }
  local got
  got="$(lipo -archs "$src")"
  echo "   $src ($got)"
  echo "$got" | grep -q "$arch" || {
    echo "error: expected $arch, got: $got" >&2
    exit 1
  }
  cp "$src" ".build/SurfsharkGuard-$arch"
  file ".build/SurfsharkGuard-$arch"
}

write_plist() {
  local dest="$1"
  shift
  cp scripts/Info.plist "$dest"
  /usr/libexec/PlistBuddy -c "Delete :LSArchitecturePriority" "$dest" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority array" "$dest" >/dev/null
  local i=0
  for arch in "$@"; do
    /usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority:$i string $arch" "$dest" >/dev/null
    i=$((i + 1))
  done
}

package_app() {
  local bin="$1"
  local dest="$2"
  shift 2
  local expected="$*"
  rm -rf "$dest"
  mkdir -p "$dest/Contents/MacOS" "$dest/Contents/Resources"
  cp "$bin" "$dest/Contents/MacOS/SurfsharkGuard"
  write_plist "$dest/Contents/Info.plist" "$@"
  if [ -f "Assets/AppIcon.icns" ]; then
    cp Assets/AppIcon.icns "$dest/Contents/Resources/AppIcon.icns"
  fi
  strip -xS "$dest/Contents/MacOS/SurfsharkGuard"
  codesign --force --sign - --timestamp=none "$dest"
  xattr -cr "$dest" 2>/dev/null || true
  touch "$dest"

  local arches
  arches="$(lipo -archs "$dest/Contents/MacOS/SurfsharkGuard")"
  echo "   $dest arches: $arches"
  for arch in $expected; do
    echo "$arches" | grep -q "$arch" || {
      echo "error: $dest missing $arch slice" >&2
      exit 1
    }
  done
  if [ "$expected" = "arm64" ] && echo "$arches" | grep -q x86_64; then
    echo "error: arm64 build unexpectedly contains x86_64" >&2
    exit 1
  fi

  if strings "$dest/Contents/MacOS/SurfsharkGuard" \
       | grep -E '/Users/|/home/|anonymous|Samuel|zcode' >/dev/null; then
    echo "error: $dest still contains a local path or personal token" >&2
    strings "$dest/Contents/MacOS/SurfsharkGuard" \
      | grep -E '/Users/|/home/|anonymous|Samuel|zcode' >&2
    exit 1
  fi
}

make_dmg() {
  local src_app="$1"
  local dmg="$2"
  local stage="build/dmg-root"
  echo "▸ Creating ${dmg}"
  rm -rf "$stage" "$dmg"
  mkdir -p "$stage"
  cp -R "$src_app" "$stage/SurfsharkGuard.app"
  ln -s /Applications "$stage/Applications"
  find "$stage" -name '.DS_Store' -delete
  xattr -cr "$stage" 2>/dev/null || true
  hdiutil create -volname "Surfshark Guard" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null
  xattr -cr "$dmg" 2>/dev/null || true
  rm -rf "$stage"
}

build_arch arm64
build_arch x86_64
lipo -create \
  .build/SurfsharkGuard-arm64 \
  .build/SurfsharkGuard-x86_64 \
  -output .build/SurfsharkGuard-universal

echo "▸ Packaging Apple Silicon app…"
package_app .build/SurfsharkGuard-arm64 "$ARM_APP" arm64
echo "▸ Packaging universal app…"
package_app .build/SurfsharkGuard-universal "$UNI_APP" arm64 x86_64

make_dmg "$ARM_APP" "$ARM_DMG"
make_dmg "$UNI_APP" "$UNI_DMG"

echo "✅ Apple Silicon: $ARM_APP"
echo "   DMG:           $ARM_DMG"
echo "✅ Universal:     $UNI_APP"
echo "   DMG:           $UNI_DMG"
echo "   Install:  open either DMG and drag the app into Applications"
