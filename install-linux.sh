#!/usr/bin/env bash
# Install the compiled release, or run scripts/package-linux.sh first in a checkout.
set -euo pipefail
cd "$(dirname "$0")"
BROWSER_DIR=${BROWSER_DIR:-$HOME/.local/opt/firefox-geckium}
PROFILE_DIR=${PROFILE_DIR:-$HOME/.local/share/geckium/profile}
FIREFOX_VERSION=${FIREFOX_VERSION:-153.5.0esr}
LOCALE=${LOCALE:-en-US}
GECKIUM_ONLY=${GECKIUM_ONLY:-0}
for cmd in python3 curl tar cp; do command -v "$cmd" >/dev/null; done
[[ -f 'Profile Folder/chrome/geckiumChrome.css' ]] || {
  echo 'Missing compiled CSS. Extract the release zip, or run npm run package and extract dist/Geckium_Patched_Linux.zip.' >&2; exit 1;
}
[[ "$BROWSER_DIR" = /* && "$PROFILE_DIR" = /* && "$BROWSER_DIR" != / && "$PROFILE_DIR" != / ]] || exit 1
# Do not mutate any installation/profile that a running process may be using.
python3 - "$BROWSER_DIR" "$PROFILE_DIR" <<'PY'
import os, pathlib, sys
browser, profile = map(os.path.realpath, sys.argv[1:])
for proc in pathlib.Path('/proc').glob('[0-9]*'):
    if int(proc.name) == os.getpid():
        continue  # this safety check itself receives the profile path as argv
    try:
        args = (proc/'cmdline').read_bytes().decode().split('\0')
        exe = os.path.realpath(proc/'exe')
        if exe.startswith(browser + '/') or profile in args:
            sys.exit('Close Firefox (Geckium) before installing (PID ' + proc.name + ').')
    except (OSError, UnicodeError):
        pass
for name in ('lock', '.parentlock'):
    p = pathlib.Path(profile)/name
    if p.is_symlink():
        sys.exit('Profile lock exists; close Firefox and resolve stale locks first: ' + str(p))
PY
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
if [[ "$GECKIUM_ONLY" != 1 ]]; then
  [[ "$FIREFOX_VERSION" =~ ^([0-9]+)\.[0-9.]+esr$ && ${BASH_REMATCH[1]} -ge 153 ]] || { echo 'Use an ESR version >=153' >&2; exit 1; }
  [[ "$LOCALE" =~ ^[a-zA-Z-]+$ ]] || exit 1
  case $(uname -m) in x86_64) arch=linux-x86_64;; aarch64) arch=linux-aarch64;; *) echo 'Unsupported Linux architecture' >&2; exit 1;; esac
  base="https://archive.mozilla.org/pub/firefox/releases/$FIREFOX_VERSION"
  archive="$arch/$LOCALE/firefox-$FIREFOX_VERSION.tar.xz"
  curl -fL --retry 3 "$base/$archive" -o "$stage/firefox.tar.xz"
  curl -fL --retry 3 "$base/SHA512SUMS" -o "$stage/SHA512SUMS"
  python3 - "$stage" "$archive" <<'PY'
import hashlib, pathlib, sys
p = pathlib.Path(sys.argv[1])
entries = dict(line.split(maxsplit=1)[::-1] for line in (p/'SHA512SUMS').read_text().splitlines())
expected = entries[sys.argv[2]]
assert hashlib.sha512((p/'firefox.tar.xz').read_bytes()).hexdigest() == expected, 'Mozilla SHA512 mismatch'
PY
  tar -xJf "$stage/firefox.tar.xz" -C "$stage"
else
  [[ -x "$BROWSER_DIR/firefox" ]] || { echo 'GECKIUM_ONLY requires an existing Firefox installation' >&2; exit 1; }
fi
# Full backups keep bookmarks, passwords, themes and any local modifications recoverable.
stamp=$(date +%Y%m%d-%H%M%S)-$$
backup="$HOME/.local/share/geckium/backups/$stamp"
mkdir -p "$backup" "$(dirname "$BROWSER_DIR")" "$(dirname "$PROFILE_DIR")"
[[ ! -d "$PROFILE_DIR" ]] || cp -a "$PROFILE_DIR" "$backup/profile"
if [[ "$GECKIUM_ONLY" != 1 ]]; then
  [[ ! -e "$BROWSER_DIR" ]] || mv "$BROWSER_DIR" "$backup/browser"
  cp -a "$stage/firefox" "$BROWSER_DIR"
else
  cp -a "$BROWSER_DIR" "$backup/browser"
fi
mkdir -p "$PROFILE_DIR"
# Preserve user data and chrThemes; replace chrome to avoid obsolete user scripts.
rm -rf "$PROFILE_DIR/chrome"
cp -a 'Profile Folder/chrome' "$PROFILE_DIR/chrome"
mkdir -p "$PROFILE_DIR/chrThemes"
cp -an 'Profile Folder/chrThemes/.' "$PROFILE_DIR/chrThemes/"
cp -a 'Firefox Folder/.' "$BROWSER_DIR/"
rm -rf "$PROFILE_DIR/startupCache"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
# Quote arbitrary paths safely in the shell launcher.
{ printf '#!/usr/bin/env bash\nexec '; printf '%q ' "$BROWSER_DIR/firefox" --no-remote --class GeckiumFirefox --name firefox-geckium --profile "$PROFILE_DIR"; printf '"$@"\n'; } > "$HOME/.local/bin/firefox-geckium"
chmod +x "$HOME/.local/bin/firefox-geckium"
# Keep an existing customized desktop entry/icon.
if [[ ! -f "$HOME/.local/share/applications/firefox-geckium.desktop" ]]; then
  printf '[Desktop Entry]\nType=Application\nName=Firefox (Geckium)\nExec="%s/.local/bin/firefox-geckium" %%u\nIcon=firefox\nTerminal=false\nCategories=Network;WebBrowser;\n' "$HOME" > "$HOME/.local/share/applications/firefox-geckium.desktop"
fi
printf 'Installed. Backup: %s\nLaunch: %s/.local/bin/firefox-geckium\n' "$backup" "$HOME"
