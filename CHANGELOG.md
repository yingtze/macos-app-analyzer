# Changelog

All notable changes to **mac-transplant** will be documented here.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) conventions
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- `--json` flag for machine-readable output
- Scan `~/Applications` (per-user installs) in addition to `/Applications`
- HTML report with sortable/filterable table
- Homebrew Cask detection (`/opt/homebrew/Caskroom`)
- Dry-run / preview mode for restore scripts
- `--all` flag for `copy_app_deps.sh` to batch-copy every flagged app at once

---

## [2.0.0] — 2026-03-15

### Added — `analyze_apps.sh`
- **5 new caveat detections** (total now: 12):
  - `EXTERNAL_BINARIES` — CLI tools in `/usr/local/bin`, `/usr/local/sbin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`
  - `APP_SUPPORT_FILES` — folders in `/Library/Application Support/` and `~/Library/Application Support/`
  - `PREFERENCES` — `.plist` files in `~/Library/Preferences/` and `/Library/Preferences/` matched by bundle ID
  - `LOGIN_ITEMS` — embedded `Contents/Library/LoginItems/` helpers and plists containing `RunAtLoad`/`LaunchOnlyOnce` keys
  - `PLUGINS` — scans 17 system and user plugin directories: VST, VST3, AU/Components, HAL, Internet Plug-Ins, QuickLook, Spotlight, Screen Savers, PreferencePanes, Address Book Plug-Ins
- Report and restore script now reference `copy_app_deps.sh` for copyable caveats (binaries, support files, prefs, plugins)
- Version bumped to `v2.0.0` in script header

### Added — `copy_app_deps.sh` *(new script, v1.0.0)*
- Usage: `./copy_app_deps.sh "AppName" /Volumes/MyDrive`
- Case-insensitive app name matching
- Copies dependencies in 10 structured steps into `AppDeps/<AppName>/`:
  1. `.app` bundle → `app/`
  2. External binaries → `binaries/`
  3. System Application Support → `app_support_system/`
  4. User Application Support → `app_support_user/`
  5. Preferences (user + system + related bundle ID variants) → `preferences_user/` / `preferences_system/`
  6. LaunchDaemons & LaunchAgents (system + user) → `launch_launchdaemons/`, `launch_launchagents/`, `launch_agents_user/`
  7. Privileged helpers → `privileged_helpers/`
  8. Plugins (all 15 plugin directories) → `plugins/<type>_<scope>/`
  9. Embedded login item helpers → `login_items/`
  10. Kernel extensions → `kexts/`
- Auto-generates `restore_deps.sh` in the output folder with exact per-item restore commands
- `restore_deps.sh` runs: `cp`, `sudo cp`, `launchctl load`, `kextload`, chmod fixes, post-restore checklist
- Skips missing items gracefully with a `–` indicator
- Prints total copied size at completion

---

## [1.0.0] — 2026-03-15

### Added — `analyze_apps.sh` *(initial release)*
- Core scanner for all `.app` bundles in `/Applications` (top-level only)
- 7 caveat detections:
  - `MAS_APP` — Mac App Store receipt (`_MASReceipt` folder)
  - `LAUNCH_DAEMON` — LaunchDaemon/Agent plists referencing the app
  - `KERNEL_EXTENSION` — kext in `/Library/Extensions` or `/System/Library/Extensions`
  - `PRIVILEGED_HELPER` — tool in `/Library/PrivilegedHelperTools`
  - `LICENSE_ACTIVATION` — license/serial/activation files inside bundle Resources
  - `SYSTEM_FRAMEWORK` — links against `/Library/Frameworks` via `otool`
  - `INTEL_ONLY_NEEDS_ROSETTA2` — x86_64-only binary on Apple Silicon host
- Per-app metadata: name, version, bundle ID, architecture (via `lipo`)
- Colored terminal output (green = safe, yellow/red = caveats)
- Generates `~/Desktop/app_report.txt` with per-app caveat descriptions and fix instructions
- Generates `~/Desktop/restore_caveats.sh` — runnable guide for the target Mac
- Auto-opens Mac App Store search and System Preferences for relevant caveats
- `chmod +x` applied automatically to the generated restore script

---

[Unreleased]: https://github.com/yingtze/mac-transplant/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/yingtze/mac-transplant/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/yingtze/mac-transplant/releases/tag/v1.0.0
