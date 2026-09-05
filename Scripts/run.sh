#!/bin/bash
# Builds a Debug copy, re-registers the widget and relaunches the app.
set -uo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Entrain.xcodeproj -scheme Entrain -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/dd build 2>&1 \
  | grep -E "error:|warning: .*/Sources/|BUILD"
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
app=build/dd/Build/Products/Debug/Entrain.app
# The widget host caches the loaded extension; re-register and restart it.
pluginkit -a "$app/Contents/PlugIns/EntrainWidget.appex"
killall chronod 2>/dev/null || true
pkill -x Entrain || true
while pgrep -x Entrain >/dev/null; do sleep 0.2; done
# LaunchServices briefly refuses to relaunch a bundle it just saw exit.
for _ in 1 2 3 4 5; do open "$app" 2>/dev/null && break; sleep 1; done
