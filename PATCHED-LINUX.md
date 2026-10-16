# Geckium Public Beta 1 — Linux ESR patch

Based on upstream `b0.20.21.2` (MPL-2.0; see LICENSE.md). This is an
independent patched distribution, not an official upstream release.

## Install / update

Extract `Geckium_Patched_Linux.zip`, close **all** Firefox (Geckium) processes,
then run `bash install-linux.sh`. Requires Linux, Python 3, curl, tar/xz and
Mozilla's runtime dependencies (GTK, etc.). No root is needed.

Defaults match the existing standalone installation:

- Browser: `~/.local/opt/firefox-geckium`
- Profile: `~/.local/share/geckium/profile`
- Launcher: `~/.local/bin/firefox-geckium`

Firefox ESR defaults to the tested `153.5.0esr`; choose a newer ESR explicitly:
`FIREFOX_VERSION=153.6.0esr bash install-linux.sh` (example; must exist at Mozilla).
Mozilla archives are downloaded over HTTPS and checked against Mozilla's
SHA512SUMS. This is checksum validation, not independent signature validation.
The zip contains Geckium, not a bundled Firefox binary. Installation needs internet
unless using `GECKIUM_ONLY=1 bash install-linux.sh` with an existing ESR browser.
`BROWSER_DIR`, `PROFILE_DIR`, and `LOCALE` may also be overridden.

Updates back up the entire existing profile/browser under
`~/.local/share/geckium/backups/<timestamp>/`, preserve the profile's bookmarks,
logins, preferences and `chrThemes`, replace chrome files, merge autoconfig files,
and clear `startupCache`. Backups may be large. Restore them with Firefox closed
if an installation fails. No changes are made to Snap Firefox, other profiles,
or default-browser settings. Existing desktop entry/icon customizations are kept;
a Firefox binary update can restore Firefox's native window icons.
First installs still show Geckium's setup wizard. Privileged user scripts have
file access: only install distributions you trust.

## Rebuild

Requires Node.js >=18, npm and zip:

```sh
npm ci --ignore-scripts
npm run package
unzip dist/Geckium_Patched_Linux.zip -d /tmp/geckium-patched
```

Sass is locked in package-lock.json. Packaging compiles all SCSS using the same
source-tree mapping as upstream CI. The compiled CSS is included in the zip;
there is no dependence on a local release cache. `dist/SHA256SUMS` checks the zip.

## Regression verification

```sh
python3 scripts/verify-headless.py --payload /tmp/geckium-patched \
  --firefox "$HOME/.local/opt/firefox-geckium/firefox"
```

Uses a fresh disposable profile and the browser's real fx-autoconfig files.
Marionette is enabled **only** for this test profile, on loopback, with privileged
context access. Do not enable that access in a normal browsing profile.
The test opens addons, preferences and Geckium's new tab, then calls
`window.OpenBrowserWindow()`. It reads actual `injectionFailed` state via the
loader's public API (no production boot modifications), requires every enabled
script to run and checks `geckium-one` on the internal pages and second window.
JSON and browser logs are retained in the working directory. Setup completion
and migration version, stylesheet support, persistent internal-page injection,
and an empty new-tab apps list are seeded only in the disposable test profile.
These emulate a completed setup without disabling any Geckium scripts.

Headless testing covers window creation and session-wide script poisoning;
it cannot verify actual compositor/virtual-desktop placement or future Firefox
releases. ESR 153.5.0esr is the tested baseline, not a blanket compatibility
guarantee for every later Firefox release.

## Cross-page script audit

The about:addons/preferences includes are Utils (loadorder 1), Styles (2),
Branding, Titlebar, AboutAddons and AboutPreferences. Their shared Geckium
bindings originate in Utils; platform checks in Titlebar and Styles therefore
also receive the explicitly imported AppConstants. Services/ChromeUtils and DOM
APIs are available in these privileged page globals on the tested ESR.
GeckiumMaterial (`@include *`, loadorder 2) only defines functions at injection
time; its browser-only UI helpers are not executed during internal-page loading.
No additional missing injection-time globals were found in that include set.
Runtime testing also found removed legacy sidebar/preferences DOM nodes. The
optional Geckium About pane/sidebar branding now no-op when the required native
layout/API is absent, rather than throwing from DOMContentLoaded or preference
observers. Native Firefox preferences remain available; the custom About pane
is not implemented for Firefox's redesigned preferences UI.

Utils now imports AppConstants before platform/version checks without replacing
an existing browser binding, and uses `window.gBrowser?.` in its zoom callback
(optional chaining on an undeclared bare identifier still throws). NewTabHome
loads Geckium_themes exactly once, after Styles as in other Geckium pages, avoiding
lexical redeclaration of `gkSysTheme`. The loader's session-wide failure policy
is intentionally unchanged: real injection errors must remain detectable.
