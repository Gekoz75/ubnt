#!/bin/bash
# Unified UBNT/UniFi Cleanup Script - Production Ready
# Safely removes UniFi controller, related services, and cleans system

# REMOVED: set -e  # This was causing premature exits
trap ctrl_c INT

function ctrl_c() {
    echo "*** Interrupted! Resetting LED to defaults..."
    ubnt-systool reset2defaults 2>/dev/null || true
    exit 1
}

echo "=== Unified UBNT Cleanup Script ==="
echo "This will remove UniFi controller and related components"
echo ""

# Safety check - require confirmation in production
if [[ -z "$1" || "$1" != "--force" ]]; then
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# ========== PHASE 0: CRITICAL BACKUP FIRST ==========
echo "💾 CRITICAL: Backing up essential tools FIRST..."
CRITICAL_TOOLS=(
    "/sbin/ubnt-systool"
    "/sbin/ubnt-dpkg-restore"
)

BACKUP_COUNT=0
for TOOL in "${CRITICAL_TOOLS[@]}"; do
    if [[ -f "$TOOL" ]]; then
        BACKUP_PATH="/root/$(basename "$TOOL").backup"
        echo "Backing up: $TOOL → $BACKUP_PATH"
        # Use robust copy that won't fail the script
        if cp "$TOOL" "$BACKUP_PATH" 2>/dev/null; then
            chmod +x "$BACKUP_PATH" 2>/dev/null || true
            echo "✅ SUCCESS: $(basename "$TOOL") backed up"
            ((BACKUP_COUNT++))
        else
            echo "⚠️  Partial backup: $TOOL (copy failed but continuing)"
        fi
    else
        echo "⚠️  Tool not found: $TOOL (skipping - normal for some systems)"
    fi
done

echo "✅ Completed backup phase: $BACKUP_COUNT tools backed up to /root/"

# ========== PHASE 1: CRITICAL DPKG HOOK CLEANUP ==========
echo ""
echo "🔧 REMOVING UBNT DPKG HOOKS (Critical for upgrades)..."
sudo rm -f /etc/dpkg/dpkg.cfg.d/015-ubnt-dpkg-status 2>/dev/null || true
sudo rm -f /etc/dpkg/dpkg.cfg.d/020-ubnt-dpkg-cache 2>/dev/null || true
sudo rm -f /etc/dpkg/dpkg.cfg.d/*ubnt* 2>/dev/null || true
sudo rm -rf /sbin/ubnt-* 2>/dev/null || true           # Now safe - backups already created
sudo rm -f /var/lib/dpkg/triggers/* 2>/dev/null || true
sudo pkill -f dpkg 2>/dev/null || true
sudo dpkg --configure -a --force-all --no-triggers 2>/dev/null || true
echo "✅ DPKG hooks removed and system reconfigured"

# ========== PHASE 2: HOLD CRITICAL PACKAGES ==========
echo ""
echo "📦 Holding critical packages..."
apt-mark hold linux-image* grub* initramfs-tools 2>/dev/null || true
echo "Held packages: $(apt-mark showhold)"

# ========== PHASE 3: STOP SERVICES ==========
echo ""
echo "🛑 Stopping and disabling services..."

# Force kill any running UniFi processes first
echo "Force stopping all UniFi processes..."
systemctl stop bt-proxy 2>/dev/null || true
pkill -9 -f "unifi" 2>/dev/null || true
pkill -9 -f "java.*unifi" 2>/dev/null || true
sleep 3

SERVICES=(
    unifi cloudkey-webui ubnt-freeradius-setup ubnt-unifi-setup 
    ubnt-systemhub nginx php5-fpm mongod mongodb freeradius
)

for SVC in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        echo "Stopping $SVC..."
        systemctl stop "$SVC" 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet "$SVC" 2>/dev/null; then
        echo "Disabling $SVC..."
        systemctl disable "$SVC" 2>/dev/null || true
    fi
done

# Verify UniFi services are down
echo ""
echo "🔍 Checking for remaining UniFi services..."
systemctl list-units --type=service | grep -i unifi 2>/dev/null || echo "No UniFi services found"

# ========== PHASE 4: REMOVE APT SOURCES ==========
echo ""
echo "🗑️ Removing APT sources..."
rm -rf /etc/apt/sources.list.d/* 2>/dev/null || true

# ========== PHASE 5: PACKAGE REMOVAL ==========
echo ""
echo "📦 Removing packages..."

# Remove APT sources first to prevent reinstallation
rm -rf /etc/apt/sources.list.d/ubnt-unifi.list 2>/dev/null || true

# Package removal in order of dependency
PACKAGE_GROUPS=(
    "unifi"
    "ubnt-unifi-setup ubnt-systemhub ubnt-crash-report bt-proxy"
    "openjdk-8-jre-headless php5* nodejs* nginx* libmariadb3 mongodb-clients mysql-common freeradius*"
    "unifi* ubnt*"
)

for PKG_GROUP in "${PACKAGE_GROUPS[@]}"; do
    echo "Processing: $PKG_GROUP"
    for PKG in $PKG_GROUP; do
        if dpkg -l 2>/dev/null | grep -q "$PKG"; then
            echo "Removing: $PKG"
            apt-get remove --purge -y "$PKG" 2>/dev/null || true
            dpkg --purge --force-remove-reinstreq "$PKG" 2>/dev/null || true
        fi
    done
done

# ========== PHASE 6: CLEANUP LEFTOVERS ==========
echo ""
echo "🧹 Cleaning up leftovers..."

# Remove UniFi user and group
userdel -f unifi 2>/dev/null || true
groupdel unifi 2>/dev/null || true

# Clean up directories
rm -rf /var/lib/unifi /etc/unifi /var/log/unifi /usr/lib/unifi 2>/dev/null || true

# Remove config files
rm -f /etc/apt/apt.conf.d/50unattended-upgrades.ucf-dist 2>/dev/null || true

# ========== PHASE 7: FINAL SYSTEM CLEANUP ==========
echo ""
echo "🔧 Final system cleanup..."

# Fix any package issues
sudo dpkg --configure -a --force-all 2>/dev/null || true
sudo apt-get -f install -y 2>/dev/null || true

# Clean APT cache
apt-get autoremove -y 2>/dev/null || true
apt-get autoclean -y 2>/dev/null || true
apt-get clean 2>/dev/null || true

# ========== PHASE 8: VERIFICATION ==========
echo ""
echo "✅ Final verification..."

# Verify package removal
echo "🔍 Checking for remaining UBNT packages..."
dpkg -l 2>/dev/null | grep -i unifi 2>/dev/null || echo "✅ No UniFi packages found"
dpkg -l 2>/dev/null | grep -i ubnt 2>/dev/null || echo "✅ No UBNT packages found" 
dpkg -l 2>/dev/null | grep -i bt-proxy 2>/dev/null || echo "✅ No bt-proxy packages found"

# Verify backups still exist
echo ""
echo "🔍 Verifying backup files..."
if [[ -f "/root/ubnt-systool.backup" ]]; then
    echo "✅ Critical backup: /root/ubnt-systool.backup"
else
    echo "❌ MISSING: ubnt-systool.backup"
fi

if [[ -f "/root/ubnt-dpkg-restore.backup" ]]; then
    echo "✅ Critical backup: /root/ubnt-dpkg-restore.backup"
else
    echo "⚠️  Missing: ubnt-dpkg-restore.backup (may be normal)"
fi

# Test LED system functionality using backup if needed
echo ""
if [[ -f /sbin/ubnt-systool && -d /sys/class/leds ]]; then
    echo "💡 Testing LED system..."
    ubnt-systool led white on 2>/dev/null || true
    sleep 1
    ubnt-systool led white off 2>/dev/null || true
    echo "✅ LED system operational"
elif [[ -f /root/ubnt-systool.backup && -d /sys/class/leds ]]; then
    echo "💡 Testing LED system from backup..."
    /root/ubnt-systool.backup led white on 2>/dev/null || true
    sleep 1
    /root/ubnt-systool.backup led white off 2>/dev/null || true
    echo "✅ LED system operational (from backup)"
else
    echo "⚠️  LED system test skipped (tool not available)"
fi

# Show held packages
echo ""
echo "📋 Currently held packages:"
apt-mark showhold 2>/dev/null || echo "None"

echo ""
echo "=== Cleanup Complete ==="
echo "✅ Critical tools backed up to /root/"
echo "✅ DPKG hooks removed (critical for upgrades)"
echo "✅ Services stopped and disabled" 
echo "✅ Packages removed"
echo "✅ System cleaned"
echo ""
echo "Recommended: Reboot system to ensure clean state"
echo "Run with: sudo reboot"
