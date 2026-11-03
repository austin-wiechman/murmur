#!/bin/zsh
# Builds Murmur and swaps it into /Applications, keeping the replaced copy as /Applications/.Murmur.app.previous.
# With --dev it installs Murmur Dev beside it instead. Both answer the same shortcut, so each install quits the other.
set -euo pipefail
cd "${0:A:h}/.."

release_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)
if [[ "${1:-}" == --dev ]]; then
    name="Murmur Dev" id=$release_id.dev other=$release_id
    ./scripts/build-app.sh
else
    name=Murmur id=$release_id other=$release_id.dev
    MURMUR_RELEASE=1 ./scripts/build-app.sh
fi
dest=/Applications/$name.app
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ $(osascript -e "application id \"$other\" is running" 2>/dev/null) == true ]]; then
    osascript -e "tell application id \"$other\" to quit"
fi

# Copy next to the destination while the old app still runs, so the swap is one rename and a failed copy
# leaves the installed app untouched.
stage=$(mktemp -d "/Applications/.$name-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto build/Murmur.app "$stage/$name.app"

osascript -e "tell application id \"$id\" to quit" 2>/dev/null || true
for _ in {1..50}; do pgrep -qf "$dest/Contents/MacOS/" || break; sleep 0.2; done
pkill -f "$dest/Contents/MacOS/" || true

# macOS re-registers any *.app in the Trash, where it keeps answering for the bundle ID; a *.app.previous
# name is never registered.
previous=/Applications/.$name.app.previous
if [[ -d "$dest" ]]; then
    if [[ -d "$previous" ]]; then mv "$previous" ~/.Trash/"$name $(date +%Y-%m-%d\ %H.%M.%S).app.previous"; fi
    "$lsregister" -u "$dest"
    mv "$dest" "$previous"
fi
mv "$stage/$name.app" "$dest"
"$lsregister" -f "$dest"

# Every build folder registers its own copy under the same bundle ID, and any of them can answer
# `open -b`, Spotlight, or a document type. Forget all but the installed one.
"$lsregister" -dump | awk -v id="$id" '
    /^-{20,}/ { path = "" }
    /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
    /^identifier:/ && $2 == id && path != "" { print path; path = "" }' |
    sort -u | while IFS= read -r copy; do
        [[ "$copy" == "$dest" ]] && continue
        "$lsregister" -u "$copy" 2>/dev/null || true
        if [[ "$copy" == ~/.Trash/*.app && -d "$copy" ]]; then mv "$copy" "$copy.previous"; fi
    done

open "$dest"
echo "installed $dest ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$dest/Contents/Info.plist"))"
