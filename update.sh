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

# Logging setup - same directory as script
LOG_DIR="${SCRIPT_DIR}/debian-upgrade-logs"
mkdir -p "$LOG_DIR"
CURRENT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
UPGRADE_LOG="$LOG_DIR/upgrade_${CURRENT_TIMESTAMP}.log"

# Function to log with timestamp
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$UPGRADE_LOG"
}

# Function to capture command output with full logging
run_cmd() {
    local cmd="$1"
    local step="$2"
    local log_file="$LOG_DIR/${step}_${CURRENT_TIMESTAMP}.log"
    
    log "DEBUG" "Starting step: $step"
    log "DEBUG" "Command: $cmd"
    log "DEBUG" "Log file: $log_file"
    
    # Run command and capture all output
    {
        echo "=== COMMAND: $cmd ==="
        echo "=== START TIME: $(date) ==="
        echo "=== STEP: $step ==="
        echo "=== SCRIPT: ${SCRIPT_NAME} ==="
        echo "=== WORKING DIR: $(pwd) ==="
        echo ""
        
        # Execute the command
        eval "$cmd"
        
        local exit_code=$?
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
log "INFO" "Freezing vendor kernel packages..."
run_cmd "apt-mark hold linux-image-3.10.20-ubnt-mtk || true" "hold_kernel_packages"

# Ensure essential tools
log "INFO" "Installing GPG, CA certificates, and archive keyring..."
run_cmd "apt-get update -y" "initial_apt_update"
run_cmd "apt-get install -y wget curl gnupg ca-certificates debian-archive-keyring apt-transport-https" "install_essential_tools"

# Global APT settings
log "INFO" "Applying APT reliability settings..."
run_cmd "cat >/etc/apt/apt.conf.d/99fix-archive <<'EOF'
Acquire::http::Pipeline-Depth \"0\";
Acquire::Retries \"3\";
Acquire::Check-Valid-Until \"false\";
Acquire::AllowInsecureRepositories \"true\";
EOF" "configure_apt_settings"

# Prevent interactive service restarts
log "INFO" "Disabling service restarts during upgrade..."
run_cmd "cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF" "create_policy_rc"
run_cmd "chmod +x /usr/sbin/policy-rc.d" "make_policy_executable"

# Recovery helper with detailed logging
fix_system() {
    local step_name="$1"
    log "INFO" "Starting system repair: $step_name"
    
    run_cmd "dpkg --configure -a" "${step_name}_dpkg_configure"
    run_cmd "apt-get -f install -y" "${step_name}_fix_broken"
    run_cmd "apt-get autoremove -y" "${step_name}_autoremove"
    run_cmd "apt-get clean" "${step_name}_clean"
    
    # Log package state after repair
    log "INFO" "Logging package state after $step_name"
    run_cmd "dpkg -l | grep -E '^[a-z]{2}' | head -20" "${step_name}_broken_packages_check"
    run_cmd "apt-mark showhold" "${step_name}_held_packages"
}

# Import Debian signing keys
import_keys() {
    local step_name="$1"
    log "INFO" "Importing Debian archive signing keys for $step_name..."
    
    for key in 112695A0E562B32A 648ACFD622F3D138 0E98404D386FA1D9 CAA96DFA; do
        run_cmd "gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys $key || true" "${step_name}_import_key_${key}"
    done
}

# Update APT sources for given codename
set_sources() {
    local CODENAME=$1
    local step_name="$2"
    
    log "INFO" "Updating APT sources for Debian ${CODENAME} in step $step_name..."
    
    run_cmd "cp /etc/apt/sources.list /etc/apt/sources.list.bak.${step_name}.$(date +%s)" "${step_name}_backup_sources"
    
    run_cmd "cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${CODENAME} main contrib non-free
deb http://archive.debian.org/debian-security ${CODENAME}/updates main contrib non-free
EOF" "${step_name}_write_sources"
    
    run_cmd "cat /etc/apt/sources.list" "${step_name}_verify_sources"
    run_cmd "apt-get -o Acquire::Check-Valid-Until=false update" "${step_name}_apt_update"
}

# Perform one upgrade step with comprehensive logging
do_upgrade() {
    local FROM=$1
    local TO=$2
    local step_name="${FROM}_to_${TO}"
    
    log "INFO" "==============================================="
    log "INFO" "Starting upgrade: ${FROM} → ${TO}"
    log "INFO" "Step name: $step_name"
    log "INFO" "==============================================="
    
    # Log pre-upgrade state
    log "INFO" "Logging pre-upgrade state for $step_name"
    run_cmd "dpkg -l | wc -l" "${step_name}_pre_package_count"
    run_cmd "df -h" "${step_name}_pre_disk_space"
    run_cmd "cat /etc/debian_version" "${step_name}_pre_debian_version"
    
    set_sources "${TO}" "${step_name}"
    import_keys "${step_name}"
    
    log "INFO" "Starting dist-upgrade for $step_name"
    run_cmd "apt-get -qy -o \"Dpkg::Options::=--force-confdef\" -o \"Dpkg::Options::=--force-confold\" dist-upgrade --allow-unauthenticated" "${step_name}_dist_upgrade"
    
    fix_system "${step_name}_post_upgrade"
    
    # Log post-upgrade state
    log "INFO" "Logging post-upgrade state for $step_name"
    run_cmd "cat /etc/debian_version" "${step_name}_post_debian_version"
    run_cmd "lsb_release -a" "${step_name}_post_lsb_release"
    run_cmd "dpkg -l | wc -l" "${step_name}_post_package_count"
    
    log "INFO" "==============================================="
    log "INFO" "Upgrade step ${FROM} → ${TO} completed"
    log "INFO" "==============================================="
    
    # Log files for analysis
    log "INFO" "Creating analysis logs for $step_name"
    run_cmd "dpkg -l | grep -i unifi" "${step_name}_remaining_unifi_packages"
    run_cmd "systemctl list-units --failed" "${step_name}_failed_services"
    run_cmd "journalctl -u apt -u dpkg --since \"1 hour ago\" | tail -50" "${step_name}_recent_logs"

    # Prompt reboot before next phase
    read -p "Reboot is strongly recommended before continuing to the next upgrade. Reboot now? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        log "INFO" "User requested reboot after $step_name"
        echo "[INFO] Rebooting system now..."
        reboot
        exit 0
    fi
}

# ===== MAIN UPGRADE FLOW =====
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
log "INFO" "Removing temporary service restart blocker..."
run_cmd "rm -f /usr/sbin/policy-rc.d" "cleanup_policy_rc"

fix_system "final_cleanup"

# Final system state log
log "INFO" "Creating final system state report"
run_cmd "lsb_release -a" "final_version_check"
run_cmd "dpkg -l | grep -E '^[a-z]{2}'" "final_broken_packages"
run_cmd "systemctl list-units --failed" "final_failed_services"

log "INFO" "==============================================="
log "INFO" "Upgrade chain complete!"
log "INFO" "Current Debian release: ${CURRENT_VERSION}"
log "INFO" "Main log: $UPGRADE_LOG"
log "INFO" "Detailed logs in: $LOG_DIR"
log "INFO" "Please check logs for any issues before rebooting."
log "INFO" "==============================================="

echo ""
echo "[INFO] Upgrade completed. Check logs in: $LOG_DIR"
echo "[INFO] Main log: $UPGRADE_LOG"
echo "[INFO] All logs are saved in the same directory as this script: ${SCRIPT_DIR}"
