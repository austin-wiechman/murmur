#!/bin/zsh
# Builds build/Murmur.app from the Swift package and signs it. Without MURMUR_RELEASE=1 it builds a
# development copy with its own bundle ID and no update feed, so it can't take over the permissions
# or updates of an installed release.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product Murmur
bin=$(swift build -c release --show-bin-path)
app=build/Murmur.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp "$bin/Murmur" "$app/Contents/MacOS/Murmur"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Murmur"
for bundle in "$bin"/*.bundle(N); do cp -R "$bundle" "$app/Contents/Resources/"; done
# actool resolves relative paths against its daemon's directory, not ours.
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$app/Contents/Resources" --platform macosx \
    --minimum-deployment-target 26.0 --app-icon AppIcon --output-partial-info-plist "$PWD/build/icon-partial.plist" >/dev/null
# actool's own .icns stops at 256 px; keep the full-size one.
cp Resources/AppIcon.icns "$app/Contents/Resources/"

# Each commit gets a higher build number, so macOS and updaters can tell builds apart.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$app/Contents/Info.plist"
if [[ "${MURMUR_RELEASE:-}" != 1 ]]; then
    id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $id.dev" -c "Set :CFBundleDisplayName Murmur Dev" \
        -c "Delete :SUFeedURL" "$app/Contents/Info.plist"
fi
if [[ -n "${MURMUR_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MURMUR_VERSION" "$app/Contents/Info.plist"
fi

# Privacy permissions follow the signing identity; ad hoc signatures change every build.
identity=${MURMUR_SIGN_IDENTITY:-Local Code Signing}
if ! security find-identity -p codesigning | grep -qF "\"$identity\""; then
    echo "warning: no \"$identity\" signing identity; signing ad hoc, so permissions reset each build" >&2
    identity=-
fi
# The hardened runtime blocks injected libraries, which would otherwise inherit Murmur's permissions.
codesign --force --deep --options runtime --sign "$identity" "$app/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --entitlements Resources/Murmur.entitlements --sign "$identity" "$app"
echo "$app"
