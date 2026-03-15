#!/bin/bash
# =============================================================================
#  analyze_apps.sh
#  Part of: mac-transplant
#  Version: 2.0.0
#  Released: 2026-03-15
#  License: MIT
#  Repo: https://github.com/yingtze/mac-transplant
#
#  Scans /Applications, detects non-self-contained apps, and generates:
#    1. A human-readable report   → ~/Desktop/app_report.txt
#    2. A restore guide script    → ~/Desktop/restore_caveats.sh
#
#  Detects (12 caveat types):
#    MAS_APP, LAUNCH_DAEMON, KERNEL_EXTENSION, PRIVILEGED_HELPER,
#    LICENSE_ACTIVATION, SYSTEM_FRAMEWORK, EXTERNAL_BINARIES,
#    APP_SUPPORT_FILES, PREFERENCES, LOGIN_ITEMS, PLUGINS,
#    INTEL_ONLY_NEEDS_ROSETTA2
#
#  Changelog: see CHANGELOG.md
# =============================================================================

APPS_DIR="/Applications"
REPORT_FILE="$HOME/Desktop/app_report.txt"
RESTORE_SCRIPT="$HOME/Desktop/restore_caveats.sh"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

total=0; self_contained=0; caveats_count=0
declare -a RESTORE_LINES

log()    { echo -e "$1"; }
header() { echo -e "\n${BOLD}${CYAN}$1${RESET}"; echo "$(printf '─%.0s' {1..60})"; }
add_restore() { RESTORE_LINES+=("$1"); }

# =============================================================================
#  DETECTION FUNCTIONS
# =============================================================================

is_mas_app() {
    [[ -d "$1/Contents/_MASReceipt" ]]
}

has_launch_daemons() {
    local name; name=$(basename "$1" .app)
    for dir in /Library/LaunchDaemons /Library/LaunchAgents "$HOME/Library/LaunchAgents"; do
        ls "$dir" 2>/dev/null | grep -qi "$name" && return 0
    done
    return 1
}

has_kernel_extensions() {
    local name; name=$(basename "$1" .app)
    ls /Library/Extensions /System/Library/Extensions 2>/dev/null \
        | grep -qi "$name" && return 0
    return 1
}

has_privileged_helper() {
    local name; name=$(basename "$1" .app)
    ls /Library/PrivilegedHelperTools 2>/dev/null | grep -qi "$name" && return 0
    return 1
}

has_system_frameworks() {
    local exec_path
    exec_path=$(defaults read "$1/Contents/Info" CFBundleExecutable 2>/dev/null)
    [[ -z "$exec_path" ]] && return 1
    otool -L "$1/Contents/MacOS/$exec_path" 2>/dev/null \
        | grep -q "/Library/Frameworks" && return 0
    return 1
}

has_license_hint() {
    find "$1/Contents/Resources" -maxdepth 2 \
        \( -iname "*licens*" -o -iname "*serial*" -o -iname "*activat*" \) \
        2>/dev/null | grep -q .
}

# External CLI binaries in system bin paths
has_external_binaries() {
    local name; name=$(basename "$1" .app | tr '[:upper:]' '[:lower:]')
    for dir in /usr/local/bin /usr/local/sbin /opt/homebrew/bin /opt/homebrew/sbin; do
        ls "$dir" 2>/dev/null | grep -qi "$name" && return 0
    done
    return 1
}

# Application Support folders outside the bundle
has_app_support() {
    local name; name=$(basename "$1" .app)
    [[ -d "/Library/Application Support/$name" ]] && return 0
    [[ -d "$HOME/Library/Application Support/$name" ]] && return 0
    return 1
}

# Preference plists registered under the bundle ID
has_preferences() {
    local bundle_id
    bundle_id=$(defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null)
    [[ -z "$bundle_id" ]] && return 1
    [[ -f "$HOME/Library/Preferences/${bundle_id}.plist" ]] && return 0
    [[ -f "/Library/Preferences/${bundle_id}.plist" ]] && return 0
    return 1
}

# Embedded LoginItem helpers or RunAtLoad plists inside the bundle
has_login_items() {
    # Embedded login helper app (e.g. Contents/Library/LoginItems/*.app)
    find "$1/Contents/Library/LoginItems" -name "*.app" 2>/dev/null | grep -q . && return 0
    # Plist inside bundle that contains RunAtLoad key
    find "$1/Contents" -name "*.plist" 2>/dev/null \
        | xargs grep -ql "RunAtLoad\|LaunchOnlyOnce" 2>/dev/null | grep -q . && return 0
    return 1
}

# Plugins installed into system/user plugin directories
has_plugins() {
    local name; name=$(basename "$1" .app)
    local plugin_dirs=(
        "/Library/Audio/Plug-Ins/VST"        "/Library/Audio/Plug-Ins/VST3"
        "/Library/Audio/Plug-Ins/AU"         "/Library/Audio/Plug-Ins/Components"
        "/Library/Audio/Plug-Ins/HAL"        "/Library/Internet Plug-Ins"
        "/Library/QuickLook"                 "/Library/Spotlight"
        "/Library/Screen Savers"             "/Library/PreferencePanes"
        "/Library/Address Book Plug-Ins"
        "$HOME/Library/Audio/Plug-Ins/VST"   "$HOME/Library/Audio/Plug-Ins/VST3"
        "$HOME/Library/Audio/Plug-Ins/Components"
        "$HOME/Library/QuickLook"            "$HOME/Library/Screen Savers"
        "$HOME/Library/PreferencePanes"
    )
    for dir in "${plugin_dirs[@]}"; do
        ls "$dir" 2>/dev/null | grep -qi "$name" && return 0
    done
    return 1
}

get_arch() {
    local bundle_exec bin arches
    bundle_exec=$(defaults read "$1/Contents/Info" CFBundleExecutable 2>/dev/null)
    [[ -z "$bundle_exec" ]] && echo "unknown" && return
    bin="$1/Contents/MacOS/$bundle_exec"
    [[ ! -f "$bin" ]] && echo "unknown" && return
    arches=$(lipo -archs "$bin" 2>/dev/null || file "$bin" | grep -oE 'arm64|x86_64')
    echo "${arches:-unknown}"
}

get_version()   { defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown"; }
get_bundle_id() { defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "unknown"; }

# =============================================================================
#  INIT OUTPUT FILES
# =============================================================================

header "🔍  macOS App Analyzer v2.0.0"
log "Scanning: ${APPS_DIR}\n"

{
echo "=================================================================="
echo "  macOS App Analysis Report  v2.0.0"
echo "  Generated : $(date)"
echo "  Source Mac: $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "=================================================================="
echo ""
} > "$REPORT_FILE"

{
echo "#!/bin/bash"
echo "# =================================================================="
echo "# Restore Caveats Script — run this on the TARGET Mac"
echo "# Generated: $(date) on $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "# =================================================================="
echo ""
echo "RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; RESET='\033[0m'"
echo "echo ''"
echo "echo '=== macOS App Restore Caveats ==='"
echo "echo ''"
} > "$RESTORE_SCRIPT"

# =============================================================================
#  MAIN SCAN LOOP
# =============================================================================

while IFS= read -r -d '' app; do
    [[ ! -d "$app/Contents" ]] && continue
    ((total++))

    app_name=$(basename "$app" .app)
    version=$(get_version "$app")
    bundle_id=$(get_bundle_id "$app")
    arch=$(get_arch "$app")

    caveats=()
    is_mas_app            "$app" && caveats+=("MAS_APP")
    has_launch_daemons    "$app" && caveats+=("LAUNCH_DAEMON")
    has_kernel_extensions "$app" && caveats+=("KERNEL_EXTENSION")
    has_privileged_helper "$app" && caveats+=("PRIVILEGED_HELPER")
    has_license_hint      "$app" && caveats+=("LICENSE_ACTIVATION")
    has_system_frameworks "$app" && caveats+=("SYSTEM_FRAMEWORK")
    has_external_binaries "$app" && caveats+=("EXTERNAL_BINARIES")
    has_app_support       "$app" && caveats+=("APP_SUPPORT_FILES")
    has_preferences       "$app" && caveats+=("PREFERENCES")
    has_login_items       "$app" && caveats+=("LOGIN_ITEMS")
    has_plugins           "$app" && caveats+=("PLUGINS")

    current_arch=$(uname -m)
    [[ "$arch" == "x86_64" && "$current_arch" == "arm64" ]] \
        && caveats+=("INTEL_ONLY_NEEDS_ROSETTA2")

    if [[ ${#caveats[@]} -eq 0 ]]; then
        ((self_contained++))
        status="${GREEN}✅  Self-contained${RESET}"
    else
        ((caveats_count++))
        status="${YELLOW}⚠️   Has caveats${RESET}"
    fi

    log "${BOLD}${app_name}${RESET}  ${status}"
    log "   Version: ${version}  |  Bundle: ${bundle_id}  |  Arch: ${arch}"
    [[ ${#caveats[@]} -gt 0 ]] && log "   ${RED}Caveats: ${caveats[*]}${RESET}"

    # ── Report ──────────────────────────────────────────────────────────
    {
    echo "------------------------------------------------------------------"
    echo "App:       $app_name"
    echo "Version:   $version"
    echo "Bundle ID: $bundle_id"
    echo "Arch:      $arch"
    if [[ ${#caveats[@]} -eq 0 ]]; then
        echo "Status:    ✅ Self-contained (safe to copy)"
    else
        echo "Status:    ⚠️  Has caveats"
        echo "Caveats:"
        for c in "${caveats[@]}"; do
            case $c in
                MAS_APP)
                    echo "  • [MAS_APP] Mac App Store app — tied to Apple ID."
                    echo "    → Re-download from App Store on the target Mac." ;;
                LAUNCH_DAEMON)
                    echo "  • [LAUNCH_DAEMON] Background service in LaunchDaemons/Agents."
                    echo "    → Run the original installer on the target Mac." ;;
                KERNEL_EXTENSION)
                    echo "  • [KERNEL_EXTENSION] Installs a kernel extension."
                    echo "    → Run original installer + approve in Privacy & Security." ;;
                PRIVILEGED_HELPER)
                    echo "  • [PRIVILEGED_HELPER] Helper in /Library/PrivilegedHelperTools."
                    echo "    → Run the original installer on the target Mac." ;;
                LICENSE_ACTIVATION)
                    echo "  • [LICENSE_ACTIVATION] Has license/activation mechanism."
                    echo "    → Re-enter your license key on the target Mac." ;;
                SYSTEM_FRAMEWORK)
                    echo "  • [SYSTEM_FRAMEWORK] Links against /Library/Frameworks."
                    echo "    → Third-party framework may need separate install." ;;
                EXTERNAL_BINARIES)
                    echo "  • [EXTERNAL_BINARIES] Has CLI tools in /usr/local/bin or /opt/homebrew/bin."
                    echo "    → Run: ./copy_app_deps.sh '$app_name' /target/path" ;;
                APP_SUPPORT_FILES)
                    echo "  • [APP_SUPPORT_FILES] Has files in Application Support."
                    echo "    → Run: ./copy_app_deps.sh '$app_name' /target/path" ;;
                PREFERENCES)
                    echo "  • [PREFERENCES] Has preference plist in ~/Library/Preferences."
                    echo "    → Run: ./copy_app_deps.sh '$app_name' /target/path" ;;
                LOGIN_ITEMS)
                    echo "  • [LOGIN_ITEMS] Registers a login item or embedded launch helper."
                    echo "    → Launch the app once on the target Mac to re-register." ;;
                PLUGINS)
                    echo "  • [PLUGINS] Has plugins in system plugin directories."
                    echo "    → Run: ./copy_app_deps.sh '$app_name' /target/path" ;;
                INTEL_ONLY_NEEDS_ROSETTA2)
                    echo "  • [INTEL_ONLY] Intel (x86_64) only binary."
                    echo "    → On Apple Silicon: softwareupdate --install-rosetta --agree-to-license" ;;
            esac
        done
    fi
    echo ""
    } >> "$REPORT_FILE"

    # ── Restore script ──────────────────────────────────────────────────
    if [[ ${#caveats[@]} -gt 0 ]]; then
        add_restore "echo ''"
        add_restore "echo -e \"\${YELLOW}▶ ${app_name} (${version})\${RESET}\""
        for c in "${caveats[@]}"; do
            case $c in
                MAS_APP)
                    add_restore "echo -e \"  \${RED}[MAS]\${RESET} Re-download from App Store.\""
                    add_restore "open 'macappstore://search/${app_name// /%20}'" ;;
                LAUNCH_DAEMON|PRIVILEGED_HELPER|KERNEL_EXTENSION)
                    add_restore "echo -e \"  \${RED}[${c}]\${RESET} Run the original installer for ${app_name}.\"";;
                LICENSE_ACTIVATION)
                    add_restore "echo -e \"  \${YELLOW}[LICENSE]\${RESET} Re-enter license key when launching ${app_name}.\"";;
                EXTERNAL_BINARIES|APP_SUPPORT_FILES|PREFERENCES|PLUGINS)
                    add_restore "echo -e \"  \${YELLOW}[${c}]\${RESET} Restore with: ./copy_app_deps.sh '${app_name}' /target/path\"";;
                LOGIN_ITEMS)
                    add_restore "echo -e \"  \${YELLOW}[LOGIN_ITEMS]\${RESET} Launch ${app_name} once to re-register login item.\"";;
                INTEL_ONLY_NEEDS_ROSETTA2)
                    add_restore "echo -e \"  \${YELLOW}[ROSETTA]\${RESET} Installing Rosetta 2...\""
                    add_restore "softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true";;
                SYSTEM_FRAMEWORK)
                    add_restore "echo -e \"  \${YELLOW}[FRAMEWORK]\${RESET} Check developer site for framework installer.\"";;
            esac
        done
    fi

done < <(find "$APPS_DIR" -maxdepth 1 -name "*.app" -print0 | sort -z)

# =============================================================================
#  SUMMARY
# =============================================================================

header "📊  Summary"
log "  Total apps scanned : ${BOLD}${total}${RESET}"
log "  Self-contained     : ${GREEN}${BOLD}${self_contained}${RESET}"
log "  Have caveats       : ${YELLOW}${BOLD}${caveats_count}${RESET}"
log ""
log "  📄 Report         → ${CYAN}${REPORT_FILE}${RESET}"
log "  🛠  Restore script → ${CYAN}${RESTORE_SCRIPT}${RESET}"
log ""
log "  💡 Copy all deps for a specific app:"
log "     ${CYAN}./copy_app_deps.sh 'AppName' /Volumes/YourDrive${RESET}\n"

{
echo "=================================================================="
echo "SUMMARY"
echo "  Total apps scanned : $total"
echo "  Self-contained     : $self_contained"
echo "  Have caveats       : $caveats_count"
echo ""
echo "Copy all deps for a specific app:"
echo "  ./copy_app_deps.sh 'AppName' /Volumes/YourDrive"
echo "=================================================================="
} >> "$REPORT_FILE"

{
for line in "${RESTORE_LINES[@]}"; do echo "$line"; done
echo ""
echo "echo ''"
echo "echo -e \"\${GREEN}✅ Done. Self-contained apps can be copied directly.\${RESET}\""
echo "echo ''"
} >> "$RESTORE_SCRIPT"

chmod +x "$RESTORE_SCRIPT"
log "${GREEN}${BOLD}Done!${RESET}\n"
