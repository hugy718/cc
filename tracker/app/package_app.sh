#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/ClaudeUsageBar"
swift build -c release
APP="../ClaudeUsageBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/ClaudeUsageBar" "$APP/Contents/MacOS/ClaudeUsageBar"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
echo "Built $APP"
