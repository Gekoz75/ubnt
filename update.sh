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

# Minimal logging setup
LOG_DIR="${SCRIPT_DIR}/upgrade-logs"
mkdir -p "$LOG_DIR"
UPGRADE_LOG="$LOG_DIR/main.log"

# Fast logging function - minimal overhead
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$UPGRADE_LOG"
    # Only show important messages on terminal
    if [[ "$level" == "INFO" ]] || [[ "$level" == "ERROR" ]]; then
        echo "[${level}] ${message}"
    fi
}

# Fast command runner - minimal logging overhead
run_cmd() {
    local cmd="$1"
    local step="$2"
    local log_file="$LOG_DIR/${step}.log"
    
    log "DEBUG" "Starting: $step"
    
    # Fast execution - only log start/end, not every byte
    {
        echo "=== START: $step ==="
        echo "Command: $cmd"
        echo "Time: $(date)"
        echo ""
        
        # Execute directly without tee overhead
        eval "$cmd"
        
        local exit_code=$?
        echo ""
        echo "Exit code: $exit_code"
        echo "=== END: $step ==="
        echo "Time: $(date)"
        
    } > "$log_file" 2>&1
    
    return 0
}

# Detect Debian version
CURRENT_VERSION=$(lsb_release -cs 2>/dev/null || echo "unknown")
echo "[INFO] Detected Debian version: ${CURRENT_VERSION}"
log "INFO" "Detected Debian version: ${CURRENT_VERSION}"

# Fast system info - run once and be done
{
    echo "=== SYSTEM INFO ==="
    lsb_release -a
    echo "Kernel: $(uname -a)"
    echo "Disk: $(df -h / | tail -1)"
} >> "$UPGRADE_LOG" 2>&1

# Freeze vendor kernel packages - FAST
echo "[INFO] Freezing kernel packages..."
apt-mark hold linux-image-3.10.20-ubnt-mtk 2>/dev/null || true
log "INFO" "Kernel packages held"

# Ensure essential tools - FAST parallel approach
echo "[INFO] Updating package lists..."
apt-get update -y > "$LOG_DIR/02-apt-update.log" 2>&1 &
UPDATE_PID=$!

echo "[INFO] Installing essential tools..."
apt-get install -y wget curl gnupg ca-certificates debian-archive-keyring > "$LOG_DIR/03-install-tools.log" 2>&1 &
INSTALL_PID=$!

# Wait for background jobs
wait $UPDATE_PID
wait $INSTALL_PID
log "INFO" "Basic tools installed"

# Fast APT settings
echo "[INFO] Configuring APT settings..."
cat >/etc/apt/apt.conf.d/99fix-archive <<'EOF'
Acquire::http::Pipeline-Depth "0";
Acquire::Retries "3";
Acquire::Check-Valid-Until "false";
Acquire::AllowInsecureRepositories "true";
EOF

# Fast service restart blocker
echo "[INFO] Disabling service restarts..."
cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod +x /usr/sbin/policy-rc.d
log "INFO" "Service restarts disabled"

# Fast system repair
fix_system() {
    echo "[INFO] Running system repairs..."
    dpkg --configure -a >/dev/null 2>&1 &
    apt-get -f install -y >/dev/null 2>&1 &
    wait
    log "INFO" "System repairs completed"
}

# Fast sources update
set_sources() {
    local CODENAME=$1
    echo "[INFO] Switching to Debian ${CODENAME}..."
    
    cp /etc/apt/sources.list /etc/apt/sources.list.bak
    cat >/etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${CODENAME} main contrib non-free
deb http://archive.debian.org/debian-security ${CODENAME}/updates main contrib non-free
EOF
    
    apt-get -o Acquire::Check-Valid-Until=false update > "$LOG_DIR/sources-${CODENAME}.log" 2>&1
    log "INFO" "Sources updated to ${CODENAME}"
}

# Fast key import (non-blocking)
import_keys() {
    echo "[INFO] Importing signing keys..."
    for key in 112695A0E562B32A 648ACFD622F3D138 0E98404D386FA1D9 CAA96DFA; do
        gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$key" >/dev/null 2>&1 &
    done
    wait
    log "INFO" "Signing keys imported"
}

# Fast upgrade step
do_upgrade() {
    local FROM=$1
    local TO=$2
    local step_name="${FROM}-to-${TO}"
    
    echo ""
    echo "[INFO] ==============================================="
    echo "[INFO] Starting upgrade: ${FROM} → ${TO}"
    echo "[INFO] ==============================================="
    log "INFO" "Starting upgrade: ${FROM} → ${TO}"
    
    # Pre-upgrade check
    echo "[INFO] Pre-upgrade state:"
    echo "  Debian: $(cat /etc/debian_version 2>/dev/null || echo 'unknown')"
    echo "  Disk: $(df -h / | tail -1 | awk '{print $4}') free"
    
    set_sources "${TO}"
    import_keys
    
    # MAJOR UPGRADE - show progress but log to file
    echo "[INFO] Starting major upgrade - this will take a while..."
    echo "[INFO] Follow progress in: $LOG_DIR/${step_name}-upgrade.log"
    
    # Run upgrade with visible progress but background logging
    apt-get -qy \
      -o "Dpkg::Options::=--force-confdef" \
      -o "Dpkg::Options::=--force-confold" \
      dist-upgrade --allow-unauthenticated > "$LOG_DIR/${step_name}-upgrade.log" 2>&1 &
    
    UPGRADE_PID=$!
    
    # Show progress while upgrade runs
    while kill -0 $UPGRADE_PID 2>/dev/null; do
        echo -n "."
        sleep 10
    done
    echo ""
    
    wait $UPGRADE_PID
    UPGRADE_RESULT=$?
    
    fix_system
    
    # Post-upgrade check
    echo "[INFO] Post-upgrade state:"
    echo "  Debian: $(cat /etc/debian_version 2>/dev/null || echo 'unknown')"
    echo "  Result: $UPGRADE_RESULT"
    
    log "INFO" "Upgrade ${FROM} → ${TO} completed with exit code: $UPGRADE_RESULT"
    
    # Quick reboot prompt
    echo ""
    read -t 30 -p "Reboot recommended. Reboot now? (continuing in 30s) [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        echo "[INFO] Rebooting..."
        log "INFO" "Rebooting after ${FROM} → ${TO}"
        reboot
        exit 0
    fi
}

# ===== MAIN UPGRADE FLOW =====
echo ""
echo "[INFO] Starting upgrade flow from $CURRENT_VERSION"

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

# Final cleanup
echo "[INFO] Final cleanup..."
rm -f /usr/sbin/policy-rc.d
fix_system

echo ""
echo "[INFO] ==============================================="
echo "[INFO] Upgrade complete! Current: ${CURRENT_VERSION}"
echo "[INFO] Logs: $LOG_DIR"
echo "[INFO] ==============================================="
log "INFO" "Upgrade chain completed. Final version: ${CURRENT_VERSION}"
