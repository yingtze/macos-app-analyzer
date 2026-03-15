# Changelog

All notable changes to **macOS App Analyzer & Caveat Generator** will be documented here.

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) conventions
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

> Changes staged for the next release.

### Planned
- `--json` flag to emit machine-readable JSON output
- Scan `~/Applications` (per-user installs) in addition to `/Applications`
- HTML report with a sortable, filterable table
- Homebrew Cask detection (`/opt/homebrew/Caskroom`)
- Dry-run / preview mode for `restore_caveats.sh`

---

## [1.0.0] — 2025-03-15

### 🎉 Initial Release

#### Added
- **Core scanner** — iterates every `.app` bundle in `/Applications` (top-level)
- **Self-contained detection** — marks apps with zero caveats as ✅ safe to copy
- **Caveat detection engine** with 7 checks:
  - `MAS_APP` — detects Mac App Store receipts (`_MASReceipt` folder)
  - `LAUNCH_DAEMON` — checks `/Library/LaunchDaemons`, `/Library/LaunchAgents`, `~/Library/LaunchAgents`
  - `KERNEL_EXTENSION` — checks `/Library/Extensions` and `/System/Library/Extensions`
  - `PRIVILEGED_HELPER` — checks `/Library/PrivilegedHelperTools`
  - `LICENSE_ACTIVATION` — scans bundle Resources for license/serial/activation hints
  - `SYSTEM_FRAMEWORK_DEPENDENCY` — uses `otool` to detect links against `/Library/Frameworks`
  - `INTEL_ONLY_NEEDS_ROSETTA2` — flags x86_64-only apps when running on Apple Silicon
- **Metadata extraction** per app: name, version, bundle ID, architecture (via `lipo`)
- **Colored terminal output** — green for safe, yellow/red for caveats
- **`app_report.txt`** — full human-readable report saved to `~/Desktop`
  - Per-app block with all caveat descriptions and fix instructions
  - Summary section with total / safe / caveats counts
- **`restore_caveats.sh`** — auto-generated script for the target Mac
  - Opens Mac App Store search for MAS apps
  - Installs Rosetta 2 automatically for Intel-only apps
  - Opens System Preferences > Privacy & Security for kext approval
  - Prints actionable steps for daemon/helper/license/framework caveats
- **`header()` / `log()` helpers** for consistent terminal formatting
- Bash `declare -a RESTORE_LINES` buffer to build the restore script line-by-line
- `chmod +x` applied automatically to the generated restore script

---

<!-- Link references for diff URLs — update when you have a real repo -->
[Unreleased]: https://github.com/your-username/macos-app-analyzer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/your-username/macos-app-analyzer/releases/tag/v1.0.0
