#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_bundle="$PWD/build/MultiscreenSaver.saver"
target_bundle="$HOME/Library/Screen Savers/MultiscreenSaver.saver"
[[ -d "$source_bundle" ]] || { echo 'Build first.'; exit 1; }
codesign --verify --strict "$source_bundle"
mkdir -p Private "$HOME/Library/Screen Savers"
chmod 700 Private
if [[ -e "$target_bundle" || -L "$target_bundle" ]]; then
    [[ ! -L "$target_bundle" ]] || { echo 'Refusing to replace a symlink.'; exit 1; }
    backup="$PWD/Private/MultiscreenSaver-$(date +%Y%m%d-%H%M%S).saver"
    mv "$target_bundle" "$backup"
    echo 'Previous bundle backed up in Private.'
fi
/usr/bin/ditto "$source_bundle" "$target_bundle"
codesign --verify --strict "$target_bundle"
shasum -a 256 "$source_bundle/Contents/MacOS/MultiscreenSaver" "$target_bundle/Contents/MacOS/MultiscreenSaver"
echo 'Installed this project only. Screen saver selection is unchanged.'
