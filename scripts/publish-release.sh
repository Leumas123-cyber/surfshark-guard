#!/bin/bash
# Attach the two versioned DMGs to a GitHub Release tag.
# Creates the release if it does not exist yet.
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: publish-release.sh v1.3}"
VERSION="${TAG#v}"
ARM="build/SurfsharkGuard-${VERSION}-arm64.dmg"
UNI="build/SurfsharkGuard-${VERSION}-universal.dmg"

if [ ! -f "$ARM" ] || [ ! -f "$UNI" ]; then
  echo "error: missing $ARM or $UNI — run scripts/make-app.sh first" >&2
  exit 1
fi

NOTES="$(cat <<EOF
Unofficial menu-bar helper. Ad-hoc signed — right-click → Open the first time.

These DMGs were built by GitHub Actions (macos-14), not a personal Mac.

## Downloads (pick one)
- **SurfsharkGuard-${VERSION}-arm64.dmg** — Apple Silicon only
- **SurfsharkGuard-${VERSION}-universal.dmg** — Apple Silicon + Intel (\`arm64\` + \`x86_64\`)

Same app, two separate binaries. macOS 13+.

Still lawful-use only. Not a Surfshark, Mullvad, Proton, or qBittorrent product. No support — fix it yourself if it breaks.
EOF
)"

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "▸ Updating existing release $TAG…"
  gh release upload "$TAG" "$ARM" "$UNI" --clobber
  gh release edit "$TAG" --notes "$NOTES"
else
  echo "▸ Creating release $TAG…"
  gh release create "$TAG" \
    --title "Surfshark Guard ${VERSION}" \
    --notes "$NOTES" \
    "$ARM" "$UNI"
fi

echo "✅ https://github.com/${GITHUB_REPOSITORY:-Leumas123-cyber/surfshark-guard}/releases/tag/${TAG}"
