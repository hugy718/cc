#!/bin/bash
# Rasterize Resources/icon.svg and build Resources/AppIcon.icns.
# Uses only macOS built-ins (qlmanage + sips + iconutil); no extra installs.
set -euo pipefail
cd "$(dirname "$0")/ClaudeUsageBar/Resources"
TMP=$(mktemp -d)
qlmanage -t -s 1024 -o "$TMP" icon.svg >/dev/null 2>&1
SRC="$TMP/icon.svg.png"
[ -f "$SRC" ] || { echo "error: SVG rasterization failed (qlmanage produced no PNG)"; exit 1; }
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s"   "$SRC" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  d=$((s * 2)); sips -z "$d" "$d" "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o AppIcon.icns
echo "Built $(pwd)/AppIcon.icns"
