#!/bin/sh
# Builds a Developer ID signed, notarized and stapled Entrain.app for
# distribution outside the App Store, and zips it into build/release.
#
# Needs, once per machine:
#   - a "Developer ID Application" certificate in the keychain
#   - notarytool credentials: xcrun notarytool store-credentials entrain
#   - DEVELOPMENT_TEAM in the environment (your Apple team ID)
set -eu

team=${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your Apple team ID}
profile=${NOTARY_PROFILE:-entrain}
out=build/release
archive=$out/Entrain.xcarchive
app=$out/Entrain.app
zip=$out/Entrain.zip

rm -rf "$out"
mkdir -p "$out"
xcodegen generate

xcodebuild -project Entrain.xcodeproj -scheme Entrain -configuration Release \
  -archivePath "$archive" archive \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

cp -R "$archive/Products/Applications/Entrain.app" "$app"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
echo "Ready: $zip"
