# 🍎 mac-transplant

> Scan your `/Applications` folder, detect apps that **can't be safely copied** to another Mac, and auto-generate a full dependency backup + restore script per app.

![macOS](https://img.shields.io/badge/macOS-10.15%2B-blue?logo=apple&logoColor=white)
![Shell](https://img.shields.io/badge/shell-bash-89e051?logo=gnu-bash&logoColor=white)
![analyze version](https://img.shields.io/badge/analyze__apps.sh-v2.0.0-informational)
![copy version](https://img.shields.io/badge/copy__app__deps.sh-v1.0.0-informational)
![License](https://img.shields.io/badge/license-MIT-green)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

---

## 📖 The Problem

Not all macOS apps are safe to drag-and-drop to a new Mac or USB drive. Some install **background daemons**, **kernel extensions**, **privileged helpers**, **plugins**, or store critical data in **Application Support** and **Preferences** — all outside the `.app` bundle. Copying only the `.app` leaves those behind and the app breaks.

This toolset takes the guesswork out of it.

---

## 🗂 Scripts

| Script | Version | Purpose |
|---|---|---|
| `analyze_apps.sh` | v2.0.0 | Scan all apps, detect caveats, generate report & restore guide |
| `copy_app_deps.sh` | v1.0.0 | Copy every dependency of a specific app to a structured folder |

---

## ✨ What It Does

### `analyze_apps.sh`
1. Scans every `.app` in `/Applications`
2. Detects whether each app is self-contained or has caveats
3. Saves two files to `~/Desktop`:

| Output | Purpose |
|---|---|
| `app_report.txt` | Full human-readable report for every app |
| `restore_caveats.sh` | Runnable guide for the target Mac |

### `copy_app_deps.sh`
1. Takes an app name + target path
2. Copies the `.app` bundle **plus** every dependency it finds into a structured folder
3. Auto-generates a `restore_deps.sh` script inside that folder

---

## 🚦 Caveat Types Detected

| Badge | What's Detected | Where It Looks |
|---|---|---|
| `MAS_APP` | Mac App Store receipt | `Contents/_MASReceipt` |
| `LAUNCH_DAEMON` | Background LaunchDaemon/Agent | `/Library/LaunchDaemons`, `/Library/LaunchAgents`, `~/Library/LaunchAgents` |
| `KERNEL_EXTENSION` | Kernel extension (kext) | `/Library/Extensions`, `/System/Library/Extensions` |
| `PRIVILEGED_HELPER` | Privileged helper tool | `/Library/PrivilegedHelperTools` |
| `LICENSE_ACTIVATION` | License / serial / activation file | `Contents/Resources/` |
| `SYSTEM_FRAMEWORK` | Third-party framework dependency | `otool -L` against `/Library/Frameworks` |
| `EXTERNAL_BINARIES` | CLI tools outside the bundle | `/usr/local/bin`, `/opt/homebrew/bin`, `/usr/local/sbin`, `/opt/homebrew/sbin` |
| `APP_SUPPORT_FILES` | Application Support folder | `/Library/Application Support/`, `~/Library/Application Support/` |
| `PREFERENCES` | Preference plists | `~/Library/Preferences/`, `/Library/Preferences/` (by bundle ID) |
| `LOGIN_ITEMS` | Embedded login helper / RunAtLoad plist | `Contents/Library/LoginItems/`, plists with `RunAtLoad` key |
| `PLUGINS` | Plugins in system directories | VST, VST3, AU, HAL, QuickLook, Spotlight, Screen Savers, PreferencePanes, Internet Plug-Ins (17 dirs) |
| `INTEL_ONLY_NEEDS_ROSETTA2` | Intel-only binary on Apple Silicon | `lipo -archs` |

---

## 🚀 Quick Start

### Step 1 — Clone

```bash
git clone https://github.com/yingtze/mac-transplant.git
cd mac-transplant
chmod +x analyze_apps.sh copy_app_deps.sh
```

### Step 2 — Scan your source Mac

```bash
./analyze_apps.sh
```

Outputs `~/Desktop/app_report.txt` and `~/Desktop/restore_caveats.sh`.

### Step 3 — Copy a specific app and all its dependencies

```bash
./copy_app_deps.sh "Zoom" /Volumes/MyDrive
./copy_app_deps.sh "Adobe Photoshop 2024" /Volumes/MyDrive
```

Output structure on your drive:

```
/Volumes/MyDrive/AppDeps/Zoom/
├── app/                    ← .app bundle
├── binaries/               ← CLI tools
├── app_support_system/     ← /Library/Application Support/Zoom
├── app_support_user/       ← ~/Library/Application Support/Zoom
├── preferences_user/       ← com.zoom.us.plist
├── preferences_system/
├── launch_launchdaemons/   ← LaunchDaemon plists
├── launch_agents_user/     ← ~/Library/LaunchAgents plists
├── privileged_helpers/
├── plugins/                ← VST, AU, QuickLook, etc.
├── login_items/
├── kexts/
└── restore_deps.sh         ← ⬅ run this on the target Mac
```

### Step 4 — Restore on the target Mac

```bash
cd /Volumes/MyDrive/AppDeps/Zoom
./restore_deps.sh
```

`restore_deps.sh` knows which files need `sudo`, runs `launchctl load` for daemons, `kextload` for kernel extensions, and prints a post-restore checklist.

---

## 🖥 Example Output

```
🔍  macOS App Analyzer v2.0.0
────────────────────────────────────────────────────────────
VLC  ✅  Self-contained
   Version: 3.0.20  |  Bundle: org.videolan.vlc  |  Arch: arm64 x86_64

Zoom  ⚠️   Has caveats
   Version: 5.17.1  |  Bundle: us.zoom.xos  |  Arch: arm64 x86_64
   Caveats: LAUNCH_DAEMON PRIVILEGED_HELPER PREFERENCES APP_SUPPORT_FILES

Logic Pro  ⚠️   Has caveats
   Version: 11.1  |  Bundle: com.apple.logic10  |  Arch: arm64
   Caveats: MAS_APP PLUGINS APP_SUPPORT_FILES

📊  Summary
────────────────────────────────────────────────────────────
  Total apps scanned : 42
  Self-contained     : 28
  Have caveats       : 14
```

---

## 📋 Requirements

- macOS 10.15 Catalina or later
- Bash 3.2+ (pre-installed on macOS)
- Standard tools: `lipo`, `otool`, `defaults`, `find`, `launchctl` — all pre-installed

No Homebrew, no third-party dependencies.

---

## ⚙️ Configuration

Edit the top of `analyze_apps.sh` to change output paths:

```bash
APPS_DIR="/Applications"
REPORT_FILE="$HOME/Desktop/app_report.txt"
RESTORE_SCRIPT="$HOME/Desktop/restore_caveats.sh"
```

---

## 🔒 Permissions & Safety

- **`analyze_apps.sh`** — read-only. Does not modify, move, or delete anything. Does not require `sudo`. Only writes `app_report.txt` and `restore_caveats.sh` to your Desktop.
- **`copy_app_deps.sh`** — read-only on source. Writes only to your specified target path.
- **`restore_deps.sh`** (auto-generated) — requires `sudo` for system-level files. Review it before running.

---

## 📁 Repo Structure

```
mac-transplant/
├── analyze_apps.sh      # v2.0.0 — scanner & caveat detector
├── copy_app_deps.sh     # v1.0.0 — dependency copier
├── CHANGELOG.md
├── README.md
├── .gitignore
└── LICENSE
```

---

## 🗺 Roadmap

See [Unreleased] section in [CHANGELOG.md](CHANGELOG.md).

---

## 🤝 Contributing

Pull requests are welcome. Please open an issue first to discuss what you'd like to change.

```bash
git checkout -b feature/my-improvement
git commit -m "feat: add --json output flag"
git push origin feature/my-improvement
```

Commit message convention: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.
