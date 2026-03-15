#!/bin/bash
# =============================================================================
#  copy_app_deps.sh
#  Part of: mac-transplant
#  Version: 1.0.0
#  Released: 2026-03-15
#  License: MIT
#  Repo: https://github.com/yingtze/mac-transplant
#
#  Copies ALL dependencies of a macOS app to a structured target directory,
#  ready to be restored on another Mac using restore_deps.sh (auto-generated).
#
#  Usage:
#    ./copy_app_deps.sh "AppName" /Volumes/MyDrive
#    ./copy_app_deps.sh "Zoom"    /Volumes/MyDrive
#    ./copy_app_deps.sh "Adobe Photoshop 2024" ~/Desktop/backup
#
#  Changelog: see CHANGELOG.md
#
#  Output structure on target directory:
#    /Volumes/MyDrive/
#    └── AppDeps/
#        └── AppName/
#            ├── app/                    ← the .app bundle itself
#            ├── binaries/               ← CLI tools from /usr/local/bin etc.
#            ├── app_support_system/     ← /Library/Application Support/AppName
#            ├── app_support_user/       ← ~/Library/Application Support/AppName
#            ├── preferences_user/       ← ~/Library/Preferences/bundle.id.plist
#            ├── preferences_system/     ← /Library/Preferences/bundle.id.plist
#            ├── launch_daemons/         ← /Library/LaunchDaemons plists
#            ├── launch_agents_system/   ← /Library/LaunchAgents plists
#            ├── launch_agents_user/     ← ~/Library/LaunchAgents plists
#            ├── privileged_helpers/     ← /Library/PrivilegedHelperTools
#            ├── plugins/                ← all plugin dirs (VST, AU, QuickLook…)
#            ├── login_items/            ← embedded LoginItems helpers
#            └── restore_deps.sh         ← auto-generated restore script
# =============================================================================

# ── Args & validation ─────────────────────────────────────────────────────────
APP_NAME="$1"
TARGET_BASE="$2"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

usage() {
    echo -e "Usage: ${BOLD}./copy_app_deps.sh${RESET} ${CYAN}\"AppName\"${RESET} ${CYAN}/target/path${RESET}"
    echo    "  AppName   — name of the app (without .app)"
    echo    "  /target   — destination drive or folder"
    exit 1
}

[[ -z "$APP_NAME" || -z "$TARGET_BASE" ]] && usage

APP_PATH="/Applications/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    # Try case-insensitive search
    found=$(find /Applications -maxdepth 1 -iname "${APP_NAME}.app" -print -quit 2>/dev/null)
    if [[ -n "$found" ]]; then
        APP_PATH="$found"
        APP_NAME=$(basename "$APP_PATH" .app)
    else
        echo -e "${RED}Error:${RESET} '${APP_NAME}.app' not found in /Applications."
        exit 1
    fi
fi

BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null)
VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
APP_NAME_SAFE="${APP_NAME// /_}"   # spaces → underscores for directory name

DEST="$TARGET_BASE/AppDeps/$APP_NAME"
RESTORE_SCRIPT="$DEST/restore_deps.sh"

declare -a RESTORE_CMDS
copied_any=false

log()       { echo -e "$1"; }
header()    { echo -e "\n${BOLD}${CYAN}$1${RESET}"; echo "$(printf '─%.0s' {1..60})"; }
ok()        { echo -e "  ${GREEN}✓${RESET} $1"; }
skip()      { echo -e "  ${YELLOW}–${RESET} $1 ${YELLOW}(not found, skipping)${RESET}"; }
add_cmd()   { RESTORE_CMDS+=("$1"); }

safe_copy() {
    # safe_copy <source> <dest_dir> [label]
    local src="$1" dst="$2" label="${3:-$(basename "$1")}"
    if [[ -e "$src" ]]; then
        mkdir -p "$dst"
        cp -R "$src" "$dst/" 2>/dev/null && ok "Copied $label" && copied_any=true
    else
        skip "$label"
    fi
}

# =============================================================================
header "📦  Copying dependencies for: ${BOLD}${APP_NAME}${RESET} (${VERSION})"
log "  Bundle ID : $BUNDLE_ID"
log "  Source    : $APP_PATH"
log "  Dest      : $DEST"
# =============================================================================

mkdir -p "$DEST"

# ── 1. The .app bundle itself ─────────────────────────────────────────────────
header "1 / 10 — App Bundle"
safe_copy "$APP_PATH" "$DEST/app" ".app bundle"
add_cmd "# ── App bundle"
add_cmd "echo 'Copying .app bundle...'"
add_cmd "sudo cp -R \"\$SRC/app/${APP_NAME}.app\" /Applications/"
add_cmd "sudo chown -R root:wheel \"/Applications/${APP_NAME}.app\" 2>/dev/null || true"

# ── 2. External binaries ──────────────────────────────────────────────────────
header "2 / 10 — External Binaries"
found_bins=false
for bin_dir in /usr/local/bin /usr/local/sbin /opt/homebrew/bin /opt/homebrew/sbin; do
    while IFS= read -r -d '' bin_file; do
        bin_name=$(basename "$bin_file")
        if echo "$bin_name" | grep -qi "$APP_NAME_SAFE\|$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')"; then
            safe_copy "$bin_file" "$DEST/binaries" "$bin_name"
            orig_dir="$bin_dir"
            add_cmd "sudo cp \"\$SRC/binaries/$bin_name\" \"$orig_dir/\""
            add_cmd "sudo chmod +x \"$orig_dir/$bin_name\""
            found_bins=true
        fi
    done < <(find "$bin_dir" -maxdepth 1 -type f -print0 2>/dev/null)
done
$found_bins || skip "No external binaries found"

# ── 3. Application Support — system ──────────────────────────────────────────
header "3 / 10 — Application Support (System)"
src="/Library/Application Support/$APP_NAME"
if [[ -d "$src" ]]; then
    safe_copy "$src" "$DEST/app_support_system" "System Application Support"
    add_cmd "# ── System Application Support"
    add_cmd "sudo cp -R \"\$SRC/app_support_system/$APP_NAME\" \"/Library/Application Support/\""
else
    skip "System Application Support"
fi

# ── 4. Application Support — user ────────────────────────────────────────────
header "4 / 10 — Application Support (User)"
src="$HOME/Library/Application Support/$APP_NAME"
if [[ -d "$src" ]]; then
    safe_copy "$src" "$DEST/app_support_user" "User Application Support"
    add_cmd "# ── User Application Support"
    add_cmd "cp -R \"\$SRC/app_support_user/$APP_NAME\" \"$HOME/Library/Application Support/\""
else
    skip "User Application Support"
fi

# ── 5. Preferences ───────────────────────────────────────────────────────────
header "5 / 10 — Preferences"
prefs_found=false

if [[ -n "$BUNDLE_ID" ]]; then
    user_pref="$HOME/Library/Preferences/${BUNDLE_ID}.plist"
    sys_pref="/Library/Preferences/${BUNDLE_ID}.plist"

    if [[ -f "$user_pref" ]]; then
        safe_copy "$user_pref" "$DEST/preferences_user" "${BUNDLE_ID}.plist (user)"
        add_cmd "cp \"\$SRC/preferences_user/${BUNDLE_ID}.plist\" \"$HOME/Library/Preferences/\""
        prefs_found=true
    fi
    if [[ -f "$sys_pref" ]]; then
        safe_copy "$sys_pref" "$DEST/preferences_system" "${BUNDLE_ID}.plist (system)"
        add_cmd "sudo cp \"\$SRC/preferences_system/${BUNDLE_ID}.plist\" \"/Library/Preferences/\""
        prefs_found=true
    fi

    # Also find any related plists (e.g. com.company.appname.helper.plist)
    while IFS= read -r -d '' pf; do
        pf_name=$(basename "$pf")
        safe_copy "$pf" "$DEST/preferences_user" "$pf_name (related)"
        add_cmd "cp \"\$SRC/preferences_user/$pf_name\" \"$HOME/Library/Preferences/\""
        prefs_found=true
    done < <(find "$HOME/Library/Preferences" -maxdepth 1 \
                -name "${BUNDLE_ID%.*}*.plist" ! -name "${BUNDLE_ID}.plist" \
                -print0 2>/dev/null)
fi
$prefs_found || skip "No preference plists found"

# ── 6. Launch Daemons & Agents ────────────────────────────────────────────────
header "6 / 10 — Launch Daemons & Agents"
daemon_found=false
app_lower=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')

for daemon_dir in /Library/LaunchDaemons /Library/LaunchAgents; do
    subkey=$(basename "$daemon_dir" | tr '[:upper:]' '[:lower:]')
    while IFS= read -r -d '' plist; do
        plist_name=$(basename "$plist")
        if echo "$plist_name" | grep -qi "$app_lower"; then
            safe_copy "$plist" "$DEST/launch_${subkey}" "$plist_name"
            add_cmd "sudo cp \"\$SRC/launch_${subkey}/$plist_name\" \"$daemon_dir/\""
            add_cmd "sudo launchctl load \"$daemon_dir/$plist_name\""
            daemon_found=true
        fi
    done < <(find "$daemon_dir" -maxdepth 1 -name "*.plist" -print0 2>/dev/null)
done

# User LaunchAgents
while IFS= read -r -d '' plist; do
    plist_name=$(basename "$plist")
    if echo "$plist_name" | grep -qi "$app_lower"; then
        safe_copy "$plist" "$DEST/launch_agents_user" "$plist_name"
        add_cmd "cp \"\$SRC/launch_agents_user/$plist_name\" \"$HOME/Library/LaunchAgents/\""
        add_cmd "launchctl load \"$HOME/Library/LaunchAgents/$plist_name\""
        daemon_found=true
    fi
done < <(find "$HOME/Library/LaunchAgents" -maxdepth 1 -name "*.plist" -print0 2>/dev/null)

$daemon_found || skip "No LaunchDaemon/Agent plists found"

# ── 7. Privileged Helpers ─────────────────────────────────────────────────────
header "7 / 10 — Privileged Helpers"
helper_found=false
while IFS= read -r -d '' helper; do
    helper_name=$(basename "$helper")
    if echo "$helper_name" | grep -qi "$app_lower"; then
        safe_copy "$helper" "$DEST/privileged_helpers" "$helper_name"
        add_cmd "sudo cp \"\$SRC/privileged_helpers/$helper_name\" \"/Library/PrivilegedHelperTools/\""
        add_cmd "sudo chmod 544 \"/Library/PrivilegedHelperTools/$helper_name\""
        helper_found=true
    fi
done < <(find /Library/PrivilegedHelperTools -maxdepth 1 -print0 2>/dev/null)
$helper_found || skip "No privileged helpers found"

# ── 8. Plugins ────────────────────────────────────────────────────────────────
header "8 / 10 — Plugins"
plugin_found=false
declare -A PLUGIN_DIR_MAP=(
    ["/Library/Audio/Plug-Ins/VST"]="plugins/vst_system"
    ["/Library/Audio/Plug-Ins/VST3"]="plugins/vst3_system"
    ["/Library/Audio/Plug-Ins/Components"]="plugins/au_system"
    ["/Library/Audio/Plug-Ins/HAL"]="plugins/hal_system"
    ["/Library/Internet Plug-Ins"]="plugins/internet_system"
    ["/Library/QuickLook"]="plugins/quicklook_system"
    ["/Library/Spotlight"]="plugins/spotlight_system"
    ["/Library/Screen Savers"]="plugins/screensavers_system"
    ["/Library/PreferencePanes"]="plugins/prefpanes_system"
    ["$HOME/Library/Audio/Plug-Ins/VST"]="plugins/vst_user"
    ["$HOME/Library/Audio/Plug-Ins/VST3"]="plugins/vst3_user"
    ["$HOME/Library/Audio/Plug-Ins/Components"]="plugins/au_user"
    ["$HOME/Library/QuickLook"]="plugins/quicklook_user"
    ["$HOME/Library/Screen Savers"]="plugins/screensavers_user"
    ["$HOME/Library/PreferencePanes"]="plugins/prefpanes_user"
)

for plugin_src_dir in "${!PLUGIN_DIR_MAP[@]}"; do
    dest_sub="${PLUGIN_DIR_MAP[$plugin_src_dir]}"
    [[ ! -d "$plugin_src_dir" ]] && continue
    while IFS= read -r -d '' item; do
        item_name=$(basename "$item")
        if echo "$item_name" | grep -qi "$app_lower"; then
            safe_copy "$item" "$DEST/$dest_sub" "$item_name ($dest_sub)"
            add_cmd "# Plugin: $item_name → $plugin_src_dir"
            if [[ "$plugin_src_dir" == /Library/* ]]; then
                add_cmd "sudo cp -R \"\$SRC/$dest_sub/$item_name\" \"$plugin_src_dir/\""
            else
                add_cmd "cp -R \"\$SRC/$dest_sub/$item_name\" \"$plugin_src_dir/\""
            fi
            plugin_found=true
        fi
    done < <(find "$plugin_src_dir" -maxdepth 1 -print0 2>/dev/null)
done
$plugin_found || skip "No plugins found"

# ── 9. Login Items (embedded inside bundle) ───────────────────────────────────
header "9 / 10 — Embedded Login Items"
login_src="$APP_PATH/Contents/Library/LoginItems"
if [[ -d "$login_src" ]]; then
    safe_copy "$login_src" "$DEST/login_items" "Embedded LoginItems"
    add_cmd "# Login items are inside the .app — they auto-register on first launch."
    ok "Note: login items inside the .app bundle are already copied with the app."
else
    skip "No embedded login items found"
fi

# ── 10. Kernel Extensions ─────────────────────────────────────────────────────
header "10 / 10 — Kernel Extensions"
kext_found=false
for kext_dir in /Library/Extensions /System/Library/Extensions; do
    while IFS= read -r -d '' kext; do
        kext_name=$(basename "$kext")
        if echo "$kext_name" | grep -qi "$app_lower"; then
            safe_copy "$kext" "$DEST/kexts" "$kext_name"
            add_cmd "sudo cp -R \"\$SRC/kexts/$kext_name\" \"$kext_dir/\""
            add_cmd "sudo kextload \"$kext_dir/$kext_name\" 2>/dev/null || true"
            kext_found=true
        fi
    done < <(find "$kext_dir" -maxdepth 1 -name "*.kext" -print0 2>/dev/null)
done
$kext_found || skip "No kernel extensions found"

# =============================================================================
#  Generate restore_deps.sh
# =============================================================================

header "📝  Generating restore_deps.sh"

{
cat <<'HEADER'
#!/bin/bash
# =============================================================================
#  restore_deps.sh — Restore all dependencies on the TARGET Mac
#  Run this script from the same directory it lives in (inside AppDeps/AppName/)
#  Requires: sudo for system-level files
# =============================================================================

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()    { echo -e "$1"; }
ok()     { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()   { echo -e "  ${YELLOW}!${RESET} $1"; }

HEADER

echo "echo ''"
echo "echo -e \"\${BOLD}Restoring: ${APP_NAME} (${VERSION})\${RESET}\""
echo "echo ''"

for cmd in "${RESTORE_CMDS[@]}"; do
    if [[ "$cmd" == \#* ]]; then
        echo ""
        echo "echo -e \"\${CYAN}${cmd#\# }\${RESET}\""
    else
        echo "$cmd && ok \"Done\" || warn \"Failed — may need manual install\""
    fi
done

cat <<'FOOTER'

echo ""
echo -e "${GREEN}${BOLD}✅  Restore complete!${RESET}"
echo ""
echo "Post-restore checklist:"
echo "  1. Open the app once to trigger any first-launch setup"
echo "  2. Re-enter license keys if prompted"
echo "  3. If a System Extension dialog appears → approve in Privacy & Security"
echo "  4. Reboot if any kernel extensions were installed"
echo ""
FOOTER
} > "$RESTORE_SCRIPT"

chmod +x "$RESTORE_SCRIPT"
ok "restore_deps.sh written"

# =============================================================================
#  Final summary
# =============================================================================

header "✅  Done"
log "  App    : ${BOLD}${APP_NAME}${RESET} ${version}"
log "  Saved  : ${CYAN}${DEST}${RESET}"
log ""
log "  On the target Mac:"
log "  ${CYAN}1.${RESET} Copy the entire ${BOLD}AppDeps/${APP_NAME}/${RESET} folder"
log "  ${CYAN}2.${RESET} Open Terminal inside that folder"
log "  ${CYAN}3.${RESET} Run: ${BOLD}${CYAN}./restore_deps.sh${RESET}"
log ""

du -sh "$DEST" 2>/dev/null | awk '{print "  Total size: " $1}'
echo ""
