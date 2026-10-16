#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v zip >/dev/null
npm ci --ignore-scripts
mkdir -p dist
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cp -a 'Firefox Folder' 'Profile Folder' LICENSE.md README.md PATCHED-LINUX.md VERIFICATION.md install-linux.sh "$stage/"
mkdir "$stage/scripts"
cp scripts/verify-headless.py "$stage/scripts/"
./node_modules/.bin/sass --no-source-map 'Profile Folder/chrome':"$stage/Profile Folder/chrome"
# Source maps and SCSS are unnecessary for installation; source remains in git.
find "$stage" -name '*.scss' -delete
rm -f dist/Geckium_Patched_Linux.zip
(cd "$stage" && zip -qr "$OLDPWD/dist/Geckium_Patched_Linux.zip" .)
(cd dist && sha256sum Geckium_Patched_Linux.zip > SHA256SUMS)
