#!/bin/bash
# Rasterize Resources/icon.svg and build Resources/AppIcon.icns.
# Uses only macOS built-ins (qlmanage + sips + iconutil); no extra installs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/ClaudeUsageBar/Resources"
TMP=$(mktemp -d)
# qlmanage flattens onto opaque white, so render at 2x then re-clip to a
# rounded rect with real transparency (matching icon.svg's rx=27 => 0.27).
qlmanage -t -s 2048 -o "$TMP" icon.svg >/dev/null 2>&1
RAW="$TMP/icon.svg.png"
[ -f "$RAW" ] || { echo "error: SVG rasterization failed (qlmanage produced no PNG)"; exit 1; }
SRC="$TMP/icon-rounded.png"
swift "$HERE/round_corners.swift" "$RAW" "$SRC" 2048 0.27
[ -f "$SRC" ] || { echo "error: corner masking failed"; exit 1; }
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s"   "$SRC" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  d=$((s * 2)); sips -z "$d" "$d" "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "Built $(pwd)/AppIcon.icns"
