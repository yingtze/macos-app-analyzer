#!/bin/bash
# =============================================================================
#  macOS App Analyzer & Caveat Generator
#  Scans /Applications, detects non-self-contained apps, and generates:
#    1. A human-readable report (app_report.txt)
#    2. A restore script for the target Mac (restore_caveats.sh)
# =============================================================================

APPS_DIR="/Applications"
REPORT_FILE="$HOME/Desktop/app_report.txt"
RESTORE_SCRIPT="$HOME/Desktop/restore_caveats.sh"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Counters
total=0
self_contained=0
caveats_count=0

# Arrays to collect restore commands
declare -a RESTORE_LINES

# ── Helpers ──────────────────────────────────────────────────────────────────

log()    { echo -e "$1"; }
header() { echo -e "\n${BOLD}${CYAN}$1${RESET}"; echo "$(printf '─%.0s' {1..60})"; }

# Write a line to the restore script buffer
add_restore() { RESTORE_LINES+=("$1"); }

# ── Detection functions ───────────────────────────────────────────────────────

is_mas_app() {
    # MAS apps have a _MASReceipt folder inside the bundle
    [[ -d "$1/Contents/_MASReceipt" ]]
}

has_launch_daemons() {
    local app_name
    app_name=$(basename "$1" .app)
    # Check common system locations for launchd plists referencing this app
    for dir in /Library/LaunchDaemons /Library/LaunchAgents \
                "$HOME/Library/LaunchAgents"; do
        if ls "$dir" 2>/dev/null | grep -qi "$app_name"; then
            return 0
        fi
    done
    return 1
}

has_kernel_extensions() {
    local app_name
    app_name=$(basename "$1" .app)
    ls /Library/Extensions /System/Library/Extensions 2>/dev/null \
        | grep -qi "$app_name" && return 0
    return 1
}

has_privileged_helper() {
    # Privileged helpers live in /Library/PrivilegedHelperTools
    local app_name
    app_name=$(basename "$1" .app)
    ls /Library/PrivilegedHelperTools 2>/dev/null \
        | grep -qi "$app_name" && return 0
    return 1
}

has_system_frameworks() {
    # Check if app links against private system frameworks not bundled inside it
    local exec_path
    exec_path=$(defaults read "$1/Contents/Info" CFBundleExecutable 2>/dev/null)
    [[ -z "$exec_path" ]] && return 1
    otool -L "$1/Contents/MacOS/$exec_path" 2>/dev/null \
        | grep -q "/Library/Frameworks" && return 0
    return 1
}

get_arch() {
    local exec_path bundle_exec
    bundle_exec=$(defaults read "$1/Contents/Info" CFBundleExecutable 2>/dev/null)
    [[ -z "$bundle_exec" ]] && echo "unknown" && return
    local bin="$1/Contents/MacOS/$bundle_exec"
    [[ ! -f "$bin" ]] && echo "unknown" && return
    local arches
    arches=$(lipo -archs "$bin" 2>/dev/null || file "$bin" | grep -oE 'arm64|x86_64')
    echo "${arches:-unknown}"
}

get_version() {
    defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null \
        || echo "unknown"
}

get_bundle_id() {
    defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null \
        || echo "unknown"
}

# ── Main analysis loop ────────────────────────────────────────────────────────

header "🔍  macOS App Analyzer"
log "Scanning: ${APPS_DIR}\n"

# Start report file
{
echo "=================================================================="
echo "  macOS App Analysis Report"
echo "  Generated: $(date)"
echo "  Source Mac: $(scutil --get ComputerName 2>/dev/null || hostname)"
echo "=================================================================="
echo ""
} > "$REPORT_FILE"

# Start restore script
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

# Iterate over all .app bundles (top-level only)
while IFS= read -r -d '' app; do
    [[ ! -d "$app/Contents" ]] && continue
    ((total++))

    app_name=$(basename "$app" .app)
    version=$(get_version "$app")
    bundle_id=$(get_bundle_id "$app")
    arch=$(get_arch "$app")

    # ── Run all checks ──────────────────────────────────────────────────
    is_mas=false;         is_mas_app "$app"           && is_mas=true
    has_daemon=false;     has_launch_daemons "$app"   && has_daemon=true
    has_kext=false;       has_kernel_extensions "$app" && has_kext=true
    has_helper=false;     has_privileged_helper "$app" && has_helper=true
    has_sysfw=false;      has_system_frameworks "$app" && has_sysfw=true

    # Detect license files or activation hints inside the bundle
    has_license_hint=false
    if find "$app/Contents/Resources" -maxdepth 2 -iname "*licens*" \
           -o -iname "*serial*" -o -iname "*activat*" 2>/dev/null \
           | grep -q .; then
        has_license_hint=true
    fi

    # Aggregate caveats
    caveats=()
    $is_mas        && caveats+=("MAS_APP")
    $has_daemon    && caveats+=("LAUNCH_DAEMON")
    $has_kext      && caveats+=("KERNEL_EXTENSION")
    $has_helper    && caveats+=("PRIVILEGED_HELPER")
    $has_license_hint && caveats+=("LICENSE_ACTIVATION")
    $has_sysfw     && caveats+=("SYSTEM_FRAMEWORK_DEPENDENCY")

    # Check architecture portability
    current_arch=$(uname -m)
    if [[ "$arch" == "x86_64" && "$current_arch" == "arm64" ]]; then
        caveats+=("INTEL_ONLY_NEEDS_ROSETTA2")
    fi

    if [[ ${#caveats[@]} -eq 0 ]]; then
        ((self_contained++))
        status="${GREEN}✅  Self-contained${RESET}"
    else
        ((caveats_count++))
        status="${YELLOW}⚠️   Has caveats${RESET}"
    fi

    # ── Print to terminal ───────────────────────────────────────────────
    log "${BOLD}${app_name}${RESET}  ${status}"
    log "   Version: ${version}  |  Bundle: ${bundle_id}  |  Arch: ${arch}"
    if [[ ${#caveats[@]} -gt 0 ]]; then
        log "   ${RED}Caveats: ${caveats[*]}${RESET}"
    fi

    # ── Write to report file ────────────────────────────────────────────
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
                    echo "  • [MAS_APP] Purchased from Mac App Store — tied to your Apple ID."
                    echo "    → On the target Mac, sign in with the same Apple ID and download"
                    echo "      from the App Store, or the app may not launch properly."
                    ;;
                LAUNCH_DAEMON)
                    echo "  • [LAUNCH_DAEMON] Installs background services (LaunchDaemon/Agent)."
                    echo "    → Must run the original installer on the target Mac."
                    echo "    → Copying the .app alone will leave background services missing."
                    ;;
                KERNEL_EXTENSION)
                    echo "  • [KERNEL_EXTENSION] Uses a kernel extension (kext)."
                    echo "    → Requires the original installer + System Extension approval"
                    echo "      in System Preferences > Privacy & Security."
                    ;;
                PRIVILEGED_HELPER)
                    echo "  • [PRIVILEGED_HELPER] Uses a privileged helper tool."
                    echo "    → Helper tool lives in /Library/PrivilegedHelperTools."
                    echo "    → Run the original installer on the target Mac."
                    ;;
                LICENSE_ACTIVATION)
                    echo "  • [LICENSE_ACTIVATION] Has license/activation mechanism."
                    echo "    → You will likely need to re-enter your license key on the target Mac."
                    ;;
                SYSTEM_FRAMEWORK_DEPENDENCY)
                    echo "  • [SYSTEM_FRAMEWORK_DEPENDENCY] Links against /Library/Frameworks."
                    echo "    → A third-party framework may need to be installed separately."
                    ;;
                INTEL_ONLY_NEEDS_ROSETTA2)
                    echo "  • [INTEL_ONLY] This is an Intel (x86_64) only app."
                    echo "    → On Apple Silicon target Mac, ensure Rosetta 2 is installed:"
                    echo "      softwareupdate --install-rosetta --agree-to-license"
                    ;;
            esac
        done
    fi
    echo ""
    } >> "$REPORT_FILE"

    # ── Write restore commands ──────────────────────────────────────────
    if [[ ${#caveats[@]} -gt 0 ]]; then
        add_restore "echo ''"
        add_restore "echo -e \"\${YELLOW}▶ ${app_name} (${version})\${RESET}\""
        for c in "${caveats[@]}"; do
            case $c in
                MAS_APP)
                    add_restore "echo -e \"  \${RED}[MAS]\${RESET} Sign in with your Apple ID and re-download from the App Store.\""
                    add_restore "open 'macappstore://search/${app_name// /%20}'"
                    ;;
                LAUNCH_DAEMON|PRIVILEGED_HELPER)
                    add_restore "echo -e \"  \${RED}[DAEMON/HELPER]\${RESET} Run the original installer for ${app_name}.\""
                    add_restore "echo    '  → Download from the developer website or use your installer copy.'"
                    ;;
                KERNEL_EXTENSION)
                    add_restore "echo -e \"  \${RED}[KEXT]\${RESET} Run the original installer, then approve the System Extension:\""
                    add_restore "echo    '  → System Preferences > Privacy & Security > Allow'"
                    add_restore "open 'x-apple.systempreferences:com.apple.preference.security'"
                    ;;
                LICENSE_ACTIVATION)
                    add_restore "echo -e \"  \${YELLOW}[LICENSE]\${RESET} Re-enter your license key when launching ${app_name}.\""
                    ;;
                SYSTEM_FRAMEWORK_DEPENDENCY)
                    add_restore "echo -e \"  \${YELLOW}[FRAMEWORK]\${RESET} ${app_name} may need a third-party framework. Check developer site.\""
                    ;;
                INTEL_ONLY_NEEDS_ROSETTA2)
                    add_restore "echo -e \"  \${YELLOW}[ROSETTA]\${RESET} Installing Rosetta 2 for ${app_name}...\""
                    add_restore "softwareupdate --install-rosetta --agree-to-license 2>/dev/null || echo '  Rosetta already installed or not needed.'"
                    ;;
            esac
        done
    fi

done < <(find "$APPS_DIR" -maxdepth 1 -name "*.app" -print0 | sort -z)

# ── Summary ───────────────────────────────────────────────────────────────────

header "📊  Summary"
log "  Total apps scanned : ${BOLD}${total}${RESET}"
log "  Self-contained     : ${GREEN}${BOLD}${self_contained}${RESET}"
log "  Have caveats       : ${YELLOW}${BOLD}${caveats_count}${RESET}"
log ""
log "  📄 Full report  → ${CYAN}${REPORT_FILE}${RESET}"
log "  🛠  Restore script → ${CYAN}${RESTORE_SCRIPT}${RESET}"

# Append summary to report
{
echo "=================================================================="
echo "SUMMARY"
echo "  Total apps scanned : $total"
echo "  Self-contained     : $self_contained"
echo "  Have caveats       : $caveats_count"
echo "=================================================================="
} >> "$REPORT_FILE"

# Finalize restore script
{
for line in "${RESTORE_LINES[@]}"; do
    echo "$line"
done
echo ""
echo "echo ''"
echo "echo -e \"\${GREEN}✅  All caveats listed above. Copy self-contained apps normally.\${RESET}\""
echo "echo ''"
} >> "$RESTORE_SCRIPT"

chmod +x "$RESTORE_SCRIPT"

log "\n${GREEN}${BOLD}Done!${RESET} Copy both files to your portable drive alongside your apps.\n"
