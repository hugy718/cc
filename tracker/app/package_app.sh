#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/ClaudeUsageBar"
swift build -c release
APP="../ClaudeUsageBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/ClaudeUsageBar" "$APP/Contents/MacOS/ClaudeUsageBar"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
echo "Built $APP"
