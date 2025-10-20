#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

echo ""
echo "[INFO] ==============================================="
echo "[INFO] Debian Jessie → Stretch → Buster → Bullseye"
echo "[INFO] Stepwise Upgrade Script for UniFi CloudKey Gen1"
echo "[INFO] ==============================================="
echo ""

export DEBIAN_FRONTEND=noninteractive

# Logging setup - same directory as script with short names
LOG_DIR="${SCRIPT_DIR}/upgrade-logs"
mkdir -p "$LOG_DIR"
CURRENT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
UPGRADE_LOG="$LOG_DIR/main.log"
STEP_LOG="$LOG_DIR/steps.log"

# Function to log with timestamp
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$UPGRADE_LOG"
}

# Function to capture command output with full logging AND verbose output
run_cmd() {
    local cmd="$1"
    local step="$2"
    local log_file="$LOG_DIR/${step}.log"
    
    log "DEBUG" "Starting step: $step"
    log "DEBUG" "Command: $cmd"
    
    # Run command with verbose output to terminal AND log file
    {
        echo "=== COMMAND: $cmd ==="
        echo "=== START TIME: $(date) ==="
        echo "=== STEP: $step ==="
        echo ""
        
        # Execute the command - output goes to both terminal and log file via tee
        # Use eval to properly handle complex commands with pipes/redirects
        if [[ "$cmd" == *"dist-upgrade"* ]] || [[ "$cmd" == *"apt-get"* ]]; then
            # For apt commands, show verbose progress but capture everything
            eval "$cmd" 2>&1 | tee -a "$STEP_LOG"
        else
            # For other commands, normal execution
            eval "$cmd"
        fi
        
        local exit_code=${PIPESTATUS[0]}
        echo ""
        echo "=== EXIT CODE: $exit_code ==="
        echo "=== END TIME: $(date) ==="
        
        return $exit_code
    } >> "$log_file" 2>&1
    
    local result=$?
    log "DEBUG" "Step $step completed with exit code: $result"
    
    return $result
}

# Detect Debian version
CURRENT_VERSION=$(lsb_release -cs 2>/dev/null || echo "unknown")
log "INFO" "Detected Debian version: ${CURRENT_VERSION}"
log "INFO" "Script directory: ${SCRIPT_DIR}"
log "INFO" "Log directory: ${LOG_DIR}"

# Log system info
log "INFO" "Logging system information..."
{
    echo "=== SYSTEM INFORMATION ==="
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -a)"
    echo "Uptime: $(uptime)"
    echo "Date: $(date)"
    echo "Current Debian: $(lsb_release -ds)"
    echo "Debian Version: $(cat /etc/debian_version 2>/dev/null || echo 'unknown')"
    echo "Architecture: $(dpkg --print-architecture)"
    echo "Memory: $(free -h)"
    echo "Disk: $(df -h /)"
    echo "Script location: ${SCRIPT_DIR}"
    echo "Log location: ${LOG_DIR}"
    echo ""
    echo "=== PACKAGE MANAGER STATE ==="
    echo "Held packages:"
    apt-mark showhold
    echo ""
    echo "Broken packages:"
    dpkg -l | grep -E '^[a-z]{2}' || true
    echo ""
    echo "=== SERVICES STATE ==="
    systemctl list-units --type=service --state=failed
    echo ""
} >> "$UPGRADE_LOG"

# Freeze vendor kernel packages
echo ""
echo "[INFO] Freezing vendor kernel packages..."
log "INFO" "Freezing vendor kernel packages..."
run_cmd "apt-mark hold linux-image-3.10.20-ubnt-mtk || true" "01-hold-kernel"

# Ensure essential tools
echo ""
echo "[INFO] Installing GPG, CA certificates, and archive keyring..."
log "INFO" "Installing GPG, CA certificates, and archive keyring..."
run_cmd "apt-get update -y" "02-apt-update"
run_cmd "apt-get install -y wget curl gnupg ca-certificates debian-archive-keyring apt-transport-https" "03-install-tools"

# Global APT settings
echo ""
echo "[INFO] Applying APT reliability settings..."
log "INFO" "Applying APT reliability settings..."
run_cmd "cat >/etc/apt/apt.conf.d/99fix-archive <<'EOF'
Acquire::http::Pipeline-Depth \"0\";
Acquire::Retries \"3\";
Acquire::Check-Valid-Until \"false\";
Acquire::AllowInsecureRepositories \"true\";
EOF" "04-apt-settings"

# Prevent interactive service restarts
echo ""
echo "[INFO] Disabling service restarts during upgrade..."
log "INFO" "Disabling service restarts during upgrade..."
run_cmd "cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF" "05-policy-create"
run_cmd "chmod +x /usr/sbin/policy-rc.d" "06-policy-executable"

# Recovery helper with detailed logging
fix_system() {
    local step_name="$1"
    echo ""
    echo "[INFO] Starting system repair: $step_name"
    log "INFO" "Starting system repair: $step_name"
    
    run_cmd "dpkg --configure -a" "${step_name}-dpkg-configure"
    run_cmd "apt-get -f install -y" "${step_name}-fix-broken"
    run_cmd "apt-get autoremove -y" "${step_name}-autoremove"
    run_cmd "apt-get clean" "${step_name}-clean"
    
    # Log package state after repair
    echo "[INFO] Logging package state after $step_name"
    log "INFO" "Logging package state after $step_name"
    run_cmd "dpkg -l | grep -E '^[a-z]{2}' | head -20" "${step_name}-broken-check"
    run_cmd "apt-mark showhold" "${step_name}-held-packages"
}

# Import Debian signing keys
import_keys() {
    local step_name="$1"
    echo ""
    echo "[INFO] Importing Debian archive signing keys for $step_name..."
    log "INFO" "Importing Debian archive signing keys for $step_name..."
    
    for key in 112695A0E562B32A 648ACFD622F3D138 0E98404D386FA1D9 CAA96DFA; do
        run_cmd "gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $key || true" "${step_name}-key-${key}"
    done
}

# Update APT sources for given codename
set_sources() {
    local CODENAME=$1
    local step_name="$2"
    
    echo ""
    echo "[INFO] Updating APT sources for Debian ${CODENAME} in step $step_name..."
    log "INFO" "Updating APT sources for Debian ${CODENAME} in step $step_name..."
    
    run_cmd "cp /etc/apt/sources.list /etc/apt/sources.list.bak.${step_name}.$(date +%s)" "${step_name}-backup-sources"
    
    run_cmd "cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${CODENAME} main contrib non-free
deb http://archive.debian.org/debian-security ${CODENAME}/updates main contrib non-free
EOF" "${step_name}-write-sources"
    
    run_cmd "cat /etc/apt/sources.list" "${step_name}-verify-sources"
    run_cmd "apt-get -o Acquire::Check-Valid-Until=false update" "${step_name}-apt-update"
}

# Perform one upgrade step with comprehensive logging AND verbose output
do_upgrade() {
    local FROM=$1
    local TO=$2
    local step_name="${FROM}-to-${TO}"
    
    echo ""
    echo "[INFO] ==============================================="
    echo "[INFO] Starting upgrade: ${FROM} → ${TO}"
    echo "[INFO] ==============================================="
    log "INFO" "==============================================="
    log "INFO" "Starting upgrade: ${FROM} → ${TO}"
    log "INFO" "Step name: $step_name"
    log "INFO" "==============================================="
    
    # Log pre-upgrade state
    echo "[INFO] Logging pre-upgrade state for $step_name"
    log "INFO" "Logging pre-upgrade state for $step_name"
    run_cmd "dpkg -l | wc -l" "${step_name}-pre-pkg-count"
    run_cmd "df -h" "${step_name}-pre-disk"
    run_cmd "cat /etc/debian_version" "${step_name}-pre-version"
    
    set_sources "${TO}" "${step_name}"
    import_keys "${step_name}"
    
    echo ""
    echo "[INFO] Starting dist-upgrade for $step_name"
    echo "[INFO] This may take a while - verbose output enabled..."
    log "INFO" "Starting dist-upgrade for $step_name"
    
    # Major upgrade with verbose output
    run_cmd "apt-get -qy -o \"Dpkg::Options::=--force-confdef\" -o \"Dpkg::Options::=--force-confold\" dist-upgrade --allow-unauthenticated" "${step_name}-dist-upgrade"
    
    fix_system "${step_name}-post"
    
    # Log post-upgrade state
    echo ""
    echo "[INFO] Logging post-upgrade state for $step_name"
    log "INFO" "Logging post-upgrade state for $step_name"
    run_cmd "cat /etc/debian_version" "${step_name}-post-version"
    run_cmd "lsb_release -a" "${step_name}-post-lsb"
    run_cmd "dpkg -l | wc -l" "${step_name}-post-pkg-count"
    
    echo ""
    echo "[INFO] ==============================================="
    echo "[INFO] Upgrade step ${FROM} → ${TO} completed"
    echo "[INFO] ==============================================="
    log "INFO" "==============================================="
    log "INFO" "Upgrade step ${FROM} → ${TO} completed"
    log "INFO" "==============================================="
    
    # Log files for analysis
    echo "[INFO] Creating analysis logs for $step_name"
    log "INFO" "Creating analysis logs for $step_name"
    run_cmd "dpkg -l | grep -i unifi" "${step_name}-unifi-check"
    run_cmd "systemctl list-units --failed" "${step_name}-failed-services"
    run_cmd "journalctl -u apt -u dpkg --since \"1 hour ago\" | tail -50" "${step_name}-recent-logs"

    # Prompt reboot before next phase
    echo ""
    read -p "Reboot is strongly recommended before continuing to the next upgrade. Reboot now? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo "[INFO] Rebooting system now..."
        log "INFO" "User requested reboot after $step_name"
        reboot
        exit 0
    fi
}

# ===== MAIN UPGRADE FLOW =====
echo ""
echo "[INFO] Starting main upgrade flow from $CURRENT_VERSION"
log "INFO" "Starting main upgrade flow from $CURRENT_VERSION"

# ===== STEP 1: JESSIE → STRETCH =====
if [ "$CURRENT_VERSION" = "jessie" ]; then
    do_upgrade "jessie" "stretch"
    CURRENT_VERSION="stretch"
fi

# ===== STEP 2: STRETCH → BUSTER =====
if [ "$CURRENT_VERSION" = "stretch" ]; then
    do_upgrade "stretch" "buster"
    CURRENT_VERSION="buster"
fi

# ===== STEP 3: BUSTER → BULLSEYE =====
if [ "$CURRENT_VERSION" = "buster" ]; then
    do_upgrade "buster" "bullseye"
    CURRENT_VERSION="bullseye"
fi

# Final cleanup and logging
echo ""
echo "[INFO] Removing temporary service restart blocker..."
log "INFO" "Removing temporary service restart blocker..."
run_cmd "rm -f /usr/sbin/policy-rc.d" "99-cleanup-policy"

fix_system "99-final-cleanup"

# Final system state log
echo ""
echo "[INFO] Creating final system state report"
log "INFO" "Creating final system state report"
run_cmd "lsb_release -a" "99-final-version"
run_cmd "dpkg -l | grep -E '^[a-z]{2}'" "99-final-broken"
run_cmd "systemctl list-units --failed" "99-final-failed"

echo ""
echo "[INFO] ==============================================="
echo "[INFO] Upgrade chain complete!"
echo "[INFO] Current Debian release: ${CURRENT_VERSION}"
echo "[INFO] Main log: $UPGRADE_LOG"
echo "[INFO] Step logs: $LOG_DIR/*.log"
echo "[INFO] ==============================================="
log "INFO" "==============================================="
log "INFO" "Upgrade chain complete!"
log "INFO" "Current Debian release: ${CURRENT_VERSION}"
log "INFO" "Main log: $UPGRADE_LOG"
log "INFO" "Detailed logs in: $LOG_DIR"
log "INFO" "==============================================="

echo ""
echo "[INFO] All logs saved in: $LOG_DIR"
