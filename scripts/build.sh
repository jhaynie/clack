#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="$PWD/dist/Clack.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Clack "$app/Contents/MacOS/Clack"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/Sounds "$app/Contents/Resources/"
cp Resources/SoundLicense.txt Resources/SoundCredits.txt "$app/Contents/Resources/"
cp Resources/Clack.icns "$app/Contents/Resources/"
# Prefer an existing development identity for stable permissions across local updates.
sign_identity="${CLACK_SIGN_IDENTITY:-}"
if [ -z "$sign_identity" ]; then
    sign_identity="$(security find-identity -v -p codesigning | awk -F '\"' '/\"Apple Development:/ { print $2; exit }')"
fi
codesign --force --sign "${sign_identity:--}" --identifier com.jhaynie.clack "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
