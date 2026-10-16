# ESR patch verification

Tested with Mozilla Firefox **153.5.0esr**, Linux x86_64, headless.

- Existing `~/.local/opt/firefox-geckium/firefox`: **PASS**, 27 enabled scripts
  running, zero actual loader `injectionFailed` flags, `geckium-one=true` on
  addons/preferences/new-tab and the second `OpenBrowserWindow()` window.
- Clean browser downloaded by `install-linux.sh` into an isolated temporary HOME,
  verified against Mozilla SHA512SUMS: **PASS**, same 27-script result.
- Negative control replacing only Utils with upstream `b0.20.21.2`: **FAIL as
  expected**. Utils/Styles (and dependent scripts in later windows) failed
  injection; second window `geckium-one=false`. This demonstrates that the test
  exercises the reported bug rather than merely checking a styled initial window.
- Geckium-only update in the isolated HOME: **PASS**, preserved sentinel profile
  data and a custom chrTheme, cleared startupCache, created backups.
- Installer against the running real installation: **correctly refused** without
  changing its browser/profile. Bash syntax and git whitespace checks passed
  (upstream CRLF treated as end-of-line, not trailing whitespace).

The release includes the positive JSON reports. This verifies session-wide script
loading, not every Geckium feature or physical virtual-desktop placement. Some
upstream warnings remain: optional missing userChrome.ag.css/bookmarksBar.js,
CustomizableUI localization warnings, the headless graphics diagnostic and a
native Firefox SettingGroupManager `homepage` warning. These are **not** loader
injection failures. The old custom About preferences pane is deliberately skipped
when Firefox does not provide the legacy layout; native preferences remain usable.
