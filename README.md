# 🔍 macOS App Analyzer & Caveat Generator

> Scan your `/Applications` folder, detect apps that **can't be safely copied** to another Mac, and auto-generate a restore guide for the target machine.

![macOS](https://img.shields.io/badge/macOS-10.15%2B-blue?logo=apple&logoColor=white)
![Shell](https://img.shields.io/badge/shell-bash-89e051?logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📖 The Problem

Not all macOS apps are safe to drag-and-drop to a new Mac or a USB drive. Some install **background daemons**, **kernel extensions**, **privileged helpers**, or are **locked to your Apple ID** via the Mac App Store. Copying only the `.app` bundle leaves those dependencies behind and the app won't work.

This script takes the guesswork out of it.

---

## ✨ What It Does

1. **Scans** every `.app` in `/Applications`
2. **Detects** whether each app is self-contained or has caveats
3. **Generates** two files on your Desktop:

| File | Purpose |
|---|---|
| `app_report.txt` | Full human-readable report for every app |
| `restore_caveats.sh` | Ready-to-run script for the **target** Mac |

---

## 🚦 Caveat Types Detected

| Badge | Caveat | What It Means |
|---|---|---|
| `MAS_APP` | Mac App Store app | Tied to your Apple ID — must re-download on target |
| `LAUNCH_DAEMON` | Background service | LaunchDaemon/Agent installed outside the `.app` |
| `KERNEL_EXTENSION` | Kernel extension (kext) | Needs original installer + System Extension approval |
| `PRIVILEGED_HELPER` | Privileged helper tool | Lives in `/Library/PrivilegedHelperTools` |
| `LICENSE_ACTIVATION` | License/activation file | Will need license key re-entry on target Mac |
| `SYSTEM_FRAMEWORK_DEPENDENCY` | Third-party framework | Links against `/Library/Frameworks` |
| `INTEL_ONLY_NEEDS_ROSETTA2` | Intel-only binary | Needs Rosetta 2 on Apple Silicon target |

---

## 🚀 Quick Start

### 1 — Clone or download

```bash
git clone https://github.com/yingtze/macos-app-analyzer.git
cd macos-app-analyzer
```

### 2 — Make executable

```bash
chmod +x analyze_apps.sh
```

### 3 — Run on your source Mac

```bash
./analyze_apps.sh
```

The script prints a live summary to your terminal and writes two files to `~/Desktop/`.

### 4 — Copy everything to your portable drive

```
/Volumes/MyDrive/
├── Applications/          ← drag your .app bundles here
├── analyze_apps.sh        ← optional, for reference
├── app_report.txt         ← read this to know what needs reinstalling
└── restore_caveats.sh     ← run this on the target Mac
```

### 5 — Run the restore script on the target Mac

```bash
chmod +x restore_caveats.sh
./restore_caveats.sh
```

It will walk through every non-self-contained app and tell you exactly what to do.

---

## 🖥 Example Terminal Output

```
🔍  macOS App Analyzer
────────────────────────────────────────────────────────────
VLC  ✅  Self-contained
   Version: 3.0.20  |  Bundle: org.videolan.vlc  |  Arch: arm64 x86_64

Zoom  ⚠️   Has caveats
   Version: 5.17.1  |  Bundle: us.zoom.xos  |  Arch: arm64 x86_64
   Caveats: LAUNCH_DAEMON PRIVILEGED_HELPER

Xcode  ⚠️   Has caveats
   Version: 15.3  |  Bundle: com.apple.dt.Xcode  |  Arch: arm64
   Caveats: MAS_APP

📊  Summary
────────────────────────────────────────────────────────────
  Total apps scanned : 42
  Self-contained     : 31
  Have caveats       : 11

  📄 Full report  → ~/Desktop/app_report.txt
  🛠  Restore script → ~/Desktop/restore_caveats.sh
```

---

## 📋 Requirements

- macOS 10.15 Catalina or later
- Bash 3.2+ (ships with macOS)
- Standard CLI tools: `lipo`, `otool`, `defaults`, `find` — all pre-installed on macOS

No third-party dependencies. No `brew` required.

---

## ⚙️ Configuration

At the top of `analyze_apps.sh` you can change the default paths:

```bash
APPS_DIR="/Applications"          # Directory to scan
REPORT_FILE="$HOME/Desktop/app_report.txt"     # Where to write the report
RESTORE_SCRIPT="$HOME/Desktop/restore_caveats.sh"  # Where to write the restore script
```

---

## 🔒 Permissions Note

The script reads metadata from your Applications folder. It does **not** modify, move, or delete any apps. It does **not** require `sudo`. The only files it writes are `app_report.txt` and `restore_caveats.sh` on your Desktop.

---

## 🗺 Roadmap

- [ ] `--json` flag to output machine-readable JSON
- [ ] Scan `~/Applications` in addition to `/Applications`
- [ ] HTML report with sortable table
- [ ] Homebrew Cask detection
- [ ] Dry-run mode for restore script

---

## 🤝 Contributing

Pull requests are welcome! Please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-improvement`
3. Commit your changes: `git commit -m "feat: add JSON output flag"`
4. Push and open a PR

---

## 📄 License

MIT — see [LICENSE](LICENSE) for details.
