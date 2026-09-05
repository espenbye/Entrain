#!/bin/bash
# Builds a Debug copy, re-registers the widget and relaunches the app.
set -uo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
# Widget buttons perform inside the app over linkd, which only talks to
# bundles signed with a team identity. Ad-hoc builds render the widget but
# every button falls back to opening the app; add a Local.xcconfig (see
# Signing.xcconfig) or set DEVELOPMENT_TEAM to sign with your Apple
# Development certificate instead.
signing=()
[ -n "${DEVELOPMENT_TEAM:-}" ] && signing=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY="Apple Development")
# chronod caches the widget and control descriptors per bundle version and
# never re-asks an "unchanged" extension, so a new control would stay
# invisible; stamp every build with a fresh version.
xcodebuild -project Entrain.xcodeproj -scheme Entrain -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/dd ${signing[@]+"${signing[@]}"} \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M%S)" build 2>&1 \
  | grep -E "error:|warning: .*/Sources/|BUILD"
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
app=build/dd/Build/Products/Debug/Entrain.app
# Widget buttons with parameters resolve their intent metadata through linkd,
# which looks the bundle id up in LaunchServices. Make this copy the one it
# finds: a stale build without Metadata.appintents breaks every mode button.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f "$app"
# The widget host caches the loaded extension; re-register and restart it.
pluginkit -a "$app/Contents/PlugIns/EntrainWidget.appex"
killall chronod linkd 2>/dev/null || true
pkill -x Entrain || true
while pgrep -x Entrain >/dev/null; do sleep 0.2; done
# LaunchServices briefly refuses to relaunch a bundle it just saw exit.
for _ in 1 2 3 4 5; do open "$app" 2>/dev/null && break; sleep 1; done
