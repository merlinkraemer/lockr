#!/bin/bash
# Builds a universal, Developer ID signed and notarized Lockr.app, zips it and
# publishes it as a GitHub release for the version in Resources/Info.plist.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=<notarytool keychain profile> scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_IDENTITY:?set SIGN_IDENTITY to a Developer ID Application identity}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile}"

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
out=build/release
app=$out/Lockr.app
zip=$out/Lockr-$version.zip

[[ -z $(git status --porcelain) ]] || { echo "working tree is dirty" >&2; exit 1; }

rm -rf "$out"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Library"
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" -o "$out/Lockr-$arch" Sources/*.swift
done
lipo -create -output "$app/Contents/MacOS/Lockr" "$out/Lockr-arm64" "$out/Lockr-x86_64"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp -R Resources/LaunchAgents "$app/Contents/Library/LaunchAgents"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"

ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"

git tag -a "v$version" -m "Lockr $version"
git push origin "v$version"
gh release create "v$version" "$zip" --title "Lockr $version" --generate-notes

echo "sha256 $(shasum -a 256 "$zip" | cut -d' ' -f1)"
