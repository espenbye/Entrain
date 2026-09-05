#!/bin/bash
# Builds a Debug copy and relaunches it. Xcode refuses to sign the App Group
# entitlement without a development certificate, so the build runs unsigned
# like CI and the bundles are ad-hoc signed here with their entitlements:
# the system only loads sandboxed widget extensions.
set -uo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Entrain.xcodeproj -scheme Entrain -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|warning: .*/Sources/|BUILD"
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
app=build/dd/Build/Products/Debug/Entrain.app
codesign --force --sign - --entitlements Widget/EntrainWidget.entitlements "$app/Contents/PlugIns/EntrainWidget.appex"
codesign --force --sign - --entitlements Entrain.entitlements "$app"
pkill -x Entrain || true
while pgrep -x Entrain >/dev/null; do sleep 0.2; done
open "$app"
