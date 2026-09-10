#!/bin/bash
# Attach the two versioned DMGs to a GitHub Release tag.
# Creates the release if it does not exist yet.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: publish-release.sh v1.4}"
VERSION="${TAG#v}"
ARM="build/SurfsharkGuard-${VERSION}-arm64.dmg"
UNI="build/SurfsharkGuard-${VERSION}-universal.dmg"
CHECKSUMS="build/SurfsharkGuard-${VERSION}-SHA256SUMS.txt"

if [ ! -f "$ARM" ] || [ ! -f "$UNI" ]; then
  echo "error: missing $ARM or $UNI — run scripts/make-app.sh first" >&2
  exit 1
fi

(
  cd build
  shasum -a 256 \
    "SurfsharkGuard-${VERSION}-arm64.dmg" \
    "SurfsharkGuard-${VERSION}-universal.dmg" \
    > "$(basename "$CHECKSUMS")"
)

NOTES="$(cat <<EOF
Unofficial menu-bar helper. Builds use Developer ID signing and notarization
when the repository's Apple release secrets are configured; otherwise they are
ad-hoc signed and require right-click → Open the first time.

These DMGs were built by GitHub Actions (macos-14), not a personal Mac.

## Downloads (pick one)
- **SurfsharkGuard-${VERSION}-arm64.dmg** — Apple Silicon only
- **SurfsharkGuard-${VERSION}-universal.dmg** — Apple Silicon + Intel (\`arm64\` + \`x86_64\`)

Same app, two separate binaries. macOS 13+.
Verify downloads with **SurfsharkGuard-${VERSION}-SHA256SUMS.txt**.

Still lawful-use only. Not a Surfshark, Mullvad, Proton, or qBittorrent product. No support — fix it yourself if it breaks.
EOF
)"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Updating existing release ${TAG}"
  gh release upload "$TAG" "$ARM" "$UNI" "$CHECKSUMS" --clobber
  gh release edit "$TAG" --notes "$NOTES"
else
  echo "Creating release ${TAG}"
  gh release create "$TAG" \
    --title "SurfsharkGuard V${VERSION}" \
    --notes "$NOTES" \
    "$ARM" "$UNI" "$CHECKSUMS"
fi

echo "✅ https://github.com/${GITHUB_REPOSITORY:-Leumas123-cyber/surfshark-guard}/releases/tag/${TAG}"
