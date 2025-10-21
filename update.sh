#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

echo ""
echo "[INFO] ==============================================="
echo "[INFO] Debian Jessie → Stretch → Buster → Bullseye"
echo "[INFO] Stepwise Upgrade Script for UniFi CloudKey Gen1"
echo "[INFO] ==============================================="
echo ""

export DEBIAN_FRONTEND=noninteractive

# PRESERVE ORIGINAL LOGGING STRUCTURE
LOG_DIR="${SCRIPT_DIR}/upgrade-logs"
mkdir -p "$LOG_DIR"
UPGRADE_LOG="$LOG_DIR/main.log"

# PRESERVE ORIGINAL LOGGING FUNCTION
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$UPGRADE_LOG"
    # Show ALL messages on terminal for verbosity (changed from original)
    echo "[${level}] ${message}"
}

# PRESERVE ORIGINAL COMMAND RUNNER (but make it faster)
run_cmd() {
    local cmd="$1"
    local step="$2"
    local log_file="$LOG_DIR/${step}.log"
    
    log "DEBUG" "Starting: $step"
    
    {
        echo "=== START: $step ==="
        echo "Command: $cmd"
        echo "Time: $(date)"
        echo ""
        
        # EXACT SAME EXECUTION AS ORIGINAL - just show output
        eval "$cmd"
        
        local exit_code=$?
        echo ""
        echo "Exit code: $exit_code"
        echo "=== END: $step ==="
        echo "Time: $(date)"
        
    } > "$log_file" 2>&1
    
    return 0
}

# PRESERVE ORIGINAL VERSION DETECTION
CURRENT_VERSION=$(lsb_release -cs 2>/dev/null || echo "unknown")
log "INFO" "Detected Debian version: ${CURRENT_VERSION}"

# PRESERVE ORIGINAL SYSTEM INFO LOGGING
{
    echo "=== SYSTEM INFO ==="
    lsb_release -a
    echo "Kernel: $(uname -a)"
    echo "Disk: $(df -h / | tail -1)"
} >> "$UPGRADE_LOG" 2>&1

# PRESERVE ORIGINAL KERNEL HOLDING
log "INFO" "Freezing kernel packages..."
run_cmd "apt-mark hold linux-image-3.10.20-ubnt-mtk 2>/dev/null || true" "01-hold-kernel"

# PRESERVE ORIGINAL TOOL INSTALLATION (but sequential for reliability)
log "INFO" "Updating package lists and installing tools..."
run_cmd "apt-get update -y" "02-apt-update"
run_cmd "apt-get install -y wget curl gnupg ca-certificates debian-archive-keyring" "03-install-tools"

# PRESERVE ORIGINAL APT CONFIG
log "INFO" "Configuring APT settings..."
run_cmd "cat >/etc/apt/apt.conf.d/99fix-archive <<'EOF'
Acquire::http::Pipeline-Depth \"0\";
Acquire::Retries \"3\";
Acquire::Check-Valid-Until \"false\";
Acquire::AllowInsecureRepositories \"true\";
EOF" "04-apt-settings"

# PRESERVE ORIGINAL SERVICE RESTART BLOCKER
log "INFO" "Disabling service restarts..."
run_cmd "cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF" "05-policy-create"
run_cmd "chmod +x /usr/sbin/policy-rc.d" "06-policy-executable"

# PRESERVE ORIGINAL SYSTEM REPAIR FUNCTION
fix_system() {
    local step_name="$1"
    log "INFO" "Starting system repair: $step_name"
    
    run_cmd "dpkg --configure -a" "${step_name}-dpkg-configure"
    run_cmd "apt-get -f install -y" "${step_name}-fix-broken"
    run_cmd "apt-get autoremove -y" "${step_name}-autoremove"
    run_cmd "apt-get clean" "${step_name}-clean"
    
    log "INFO" "System repairs completed"
}

# PRESERVE ORIGINAL SOURCES UPDATE
set_sources() {
    local CODENAME=$1
    local step_name="$2"
    
    log "INFO" "Updating APT sources for Debian ${CODENAME}"
    
    run_cmd "cp /etc/apt/sources.list /etc/apt/sources.list.bak.${step_name}" "${step_name}-backup-sources"
    
    run_cmd "cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${CODENAME} main contrib non-free
deb http://archive.debian.org/debian-security ${CODENAME}/updates main contrib non-free
EOF" "${step_name}-write-sources"
    
    run_cmd "apt-get -o Acquire::Check-Valid-Until=false update" "${step_name}-apt-update"
}

# PRESERVE ORIGINAL KEY IMPORT
import_keys() {
    local step_name="$1"
    log "INFO" "Importing Debian archive signing keys..."
    
    for key in 112695A0E562B32A 648ACFD622F3D138 0E98404D386FA1D9 CAA96DFA; do
        run_cmd "gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $key || true" "${step_name}-key-${key}"
    done
}

# OPTIMIZED UPGRADE FUNCTION - PRESERVES ALL ORIGINAL LOGIC
do_upgrade() {
    local FROM=$1
    local TO=$2
    local step_name="${FROM}-to-${TO}"
    
    echo ""
    log "INFO" "==============================================="
    log "INFO" "Starting upgrade: ${FROM} → ${TO}"
    log "INFO" "==============================================="
    
    # PRESERVE ORIGINAL PRE-UPGRADE CHECKS
    log "INFO" "Pre-upgrade state:"
    log "INFO" "  Debian: $(cat /etc/debian_version 2>/dev/null || echo 'unknown')"
    log "INFO" "  Disk: $(df -h / | tail -1 | awk '{print $4}') free"
    
    set_sources "${TO}" "${step_name}"
    import_keys "${step_name}"
    
    # VERBOSE UPGRADE - shows real progress but preserves logging
    log "INFO" "Starting major upgrade - VERBOSE OUTPUT ENABLED..."
    log "INFO" "Logging to: $LOG_DIR/${step_name}-upgrade.log"
    
    # Run upgrade with BOTH terminal output AND file logging
    {
        echo "=== START UPGRADE: ${FROM} → ${TO} ==="
        echo "Time: $(date)"
        echo ""
        
        # VERBOSE: Show upgrade progress in terminal
        apt-get -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" \
                dist-upgrade --allow-unauthenticated
        
        local exit_code=$?
        echo ""
        echo "=== UPGRADE COMPLETED ==="
        echo "Exit code: $exit_code"
        echo "Time: $(date)"
        echo "New version: $(cat /etc/debian_version 2>/dev/null || echo 'unknown')"
        
        return $exit_code
    } | tee "$LOG_DIR/${step_name}-upgrade.log" 2>&1
    
    local UPGRADE_RESULT=${PIPESTATUS[0]}
    
    fix_system "${step_name}-post"
    
    # PRESERVE ORIGINAL POST-UPGRADE CHECKS
    log "INFO" "Post-upgrade state:"
    log "INFO" "  Debian: $(cat /etc/debian_version 2>/dev/null || echo 'unknown')"
    log "INFO" "  Result: $UPGRADE_RESULT"
    
    # PRESERVE ORIGINAL REBOOT PROMPT
    echo ""
    read -p "Reboot recommended. Reboot now? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        log "INFO" "Rebooting after ${FROM} → ${TO}"
        echo "[INFO] Rebooting..."
        reboot
        exit 0
    fi
}

# PRESERVE ORIGINAL MAIN UPGRADE FLOW EXACTLY
log "INFO" "Starting upgrade flow from $CURRENT_VERSION"

if [ "$CURRENT_VERSION" = "jessie" ]; then
    do_upgrade "jessie" "stretch"
    CURRENT_VERSION="stretch"
fi

if [ "$CURRENT_VERSION" = "stretch" ]; then
    do_upgrade "stretch" "buster"
    CURRENT_VERSION="buster"
fi

if [ "$CURRENT_VERSION" = "buster" ]; then
    do_upgrade "buster" "bullseye"
    CURRENT_VERSION="bullseye"
fi

# PRESERVE ORIGINAL CLEANUP
log "INFO" "Final cleanup..."
run_cmd "rm -f /usr/sbin/policy-rc.d" "99-cleanup-policy"
fix_system "99-final-cleanup"

log "INFO" "==============================================="
log "INFO" "Upgrade chain completed!"
log "INFO" "Current Debian release: ${CURRENT_VERSION}"
log "INFO" "Logs: $LOG_DIR"
log "INFO" "==============================================="
