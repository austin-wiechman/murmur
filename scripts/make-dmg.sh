#!/bin/zsh
# Packs build/Murmur.app into a disk image that opens to the app beside an Applications shortcut.
# Usage: make-dmg.sh <output.dmg>
set -euo pipefail
cd "${0:A:h}/.."

out=${1:?usage: make-dmg.sh <output.dmg>}
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto build/Murmur.app "$stage/Murmur.app"
ln -s /Applications "$stage/Applications"
[[ -e "$out" ]] && rm "$out"
diskutil image create from --format UDZO --volumeName Murmur "$stage" "$out" >/dev/null
echo "wrote $out"
