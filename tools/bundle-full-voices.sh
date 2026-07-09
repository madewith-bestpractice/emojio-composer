#!/usr/bin/env bash
#
# Bundles a full voice bake into the Flutter app.
#
# One-time manual step first (fast only in a FOREGROUND browser tab — background
# tabs throttle Web Audio offline rendering to a crawl):
#   1. Open tools/bake-voices.html in a normal browser tab.
#   2. Click "Bake ALL voices" (~2 min), which downloads emojio-samples-all.zip.
#
# Then run this script. It unzips, compresses WAV -> OGG (via tools/compress-voices.js),
# and replaces the bundled voice set in app/assets/voices/.
#
# Usage:
#   tools/bundle-full-voices.sh [zip=~/Downloads/emojio-samples-all.zip] [oggQuality=6]
set -euo pipefail

ZIP="${1:-$HOME/Downloads/emojio-samples-all.zip}"
Q="${2:-6}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/app/assets/voices"

[ -f "$ZIP" ] || { echo "zip not found: $ZIP"; echo "Bake ALL voices in a foreground tab first (tools/bake-voices.html)."; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ Unzipping $ZIP"
unzip -oq "$ZIP" -d "$TMP/wav"
[ -f "$TMP/wav/manifest.json" ] || { echo "manifest.json missing in zip"; exit 1; }

echo "→ Compressing WAV → OGG (q$Q)"
node "$ROOT/tools/compress-voices.js" "$TMP/wav" "$TMP/ogg" "$Q"

echo "→ Replacing bundled voices in app/assets/voices/"
mkdir -p "$DEST"
rm -f "$DEST"/*.wav "$DEST"/*.ogg "$DEST"/manifest.json
cp "$TMP/ogg"/*.ogg "$DEST"/
cp "$TMP/ogg/manifest.json" "$DEST"/

echo "✓ Bundled $(ls "$DEST"/*.ogg | wc -l | tr -d ' ') samples ($(du -sh "$DEST" | cut -f1))."
echo "  Next: cd app && flutter run   (first run confirms OGG decodes in flutter_soloud)"
