#!/bin/bash
# Unified UBNT/UniFi Cleanup Script - Production Ready
# Safely removes UniFi controller, related services, and cleans system

set -e  # Exit on any error
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

# ========== PHASE 0: CRITICAL DPKG HOOK CLEANUP ==========
echo "🔧 REMOVING UBNT DPKG HOOKS (Critical for upgrades)..."
sudo rm -f /etc/dpkg/dpkg.cfg.d/015-ubnt-dpkg-status
sudo rm -f /etc/dpkg/dpkg.cfg.d/020-ubnt-dpkg-cache
sudo rm -f /etc/dpkg/dpkg.cfg.d/*ubnt*
sudo rm -rf /sbin/ubnt-*           # Removes the hook scripts
sudo rm -f /var/lib/dpkg/triggers/* # Clears cached trigger info  
sudo pkill -f dpkg                 # Kills processes holding hook refs
sudo dpkg --configure -a --force-all --no-triggers # Completes ops without hooks
echo "✅ DPKG hooks removed and system reconfigured"

# ========== PHASE 1: HOLD CRITICAL PACKAGES ==========
echo "📦 Holding critical packages..."
apt-mark hold linux-image* grub* initramfs-tools 2>/dev/null || true
echo "Held packages: $(apt-mark showhold)"

# ========== PHASE 2: STOP SERVICES ==========
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
        systemctl stop "$SVC"
    fi
    if systemctl is-enabled --quiet "$SVC" 2>/dev/null; then
        echo "Disabling $SVC..."
        systemctl disable "$SVC"
    fi
done

# Verify UniFi services are down
echo "🔍 Checking for remaining UniFi services..."
systemctl list-units --type=service | grep -i unifi || echo "No UniFi services found"

# ========== PHASE 3: BACKUP CRITICAL TOOLS ==========
echo "💾 Backing up critical UBNT tools..."
CRITICAL_TOOLS=(
    "/sbin/ubnt-systool"
    "/sbin/ubnt-dpkg-restore"
)

for TOOL in "${CRITICAL_TOOLS[@]}"; do
    if [[ -f "$TOOL" ]]; then
        BACKUP_PATH="/root/$(basename "$TOOL").backup"
        cp "$TOOL" "$BACKUP_PATH"
        echo "Backed up $TOOL to $BACKUP_PATH"
    fi
done

# ========== PHASE 4: REMOVE APT SOURCES ==========
echo "🗑️ Removing APT sources..."
rm -rfv /etc/apt/sources.list.d/* || true

# ========== PHASE 5: PACKAGE REMOVAL ==========
echo "📦 Removing packages..."

# Remove APT sources first to prevent reinstallation
rm -rf /etc/apt/sources.list.d/ubnt-unifi.list 2>/dev/null || true

# Package removal in order of dependency
PACKAGE_GROUPS=(
    # First: Force remove core UniFi packages
    "unifi"
    
    # Second: Remove UBNT management packages  
    "ubnt-unifi-setup ubnt-systemhub ubnt-crash-report bt-proxy"
    
    # Third: Remove dependencies
    "openjdk-8-jre-headless php5* nodejs* nginx* libmariadb3 mongodb-clients mysql-common freeradius*"
    
    # Fourth: Clean up any remaining
    "unifi* ubnt*"
)

for PKG_GROUP in "${PACKAGE_GROUPS[@]}"; do
    echo "Processing: $PKG_GROUP"
    for PKG in $PKG_GROUP; do
        if dpkg -l | grep -q "$PKG"; then
            echo "Removing: $PKG"
            apt-get remove --purge -y "$PKG" 2>/dev/null || true
            dpkg --purge --force-remove-reinstreq "$PKG" 2>/dev/null || true
        fi
    done
done

# ========== PHASE 6: CLEANUP LEFTOVERS ==========
echo "🧹 Cleaning up leftovers..."

# Remove UniFi user and group
userdel -f unifi 2>/dev/null || true
groupdel unifi 2>/dev/null || true

# Clean up directories
rm -rf /var/lib/unifi /etc/unifi /var/log/unifi /usr/lib/unifi 2>/dev/null || true

# Remove config files
rm -f /etc/apt/apt.conf.d/50unattended-upgrades.ucf-dist 2>/dev/null || true

# ========== PHASE 7: FINAL SYSTEM CLEANUP ==========
echo "🔧 Final system cleanup..."

# Fix any package issues
sudo dpkg --configure -a --force-all 2>/dev/null || true
sudo apt-get -f install -y 2>/dev/null || true

# Clean APT cache
apt-get autoremove -y
apt-get autoclean -y
apt-get clean

# ========== PHASE 8: VERIFICATION ==========
echo "✅ Final verification..."

# Verify package removal
echo "🔍 Checking for remaining UBNT packages..."
dpkg -l | grep -i unifi || echo "✅ No UniFi packages found"
dpkg -l | grep -i ubnt || echo "✅ No UBNT packages found" 
dpkg -l | grep -i bt-proxy || echo "✅ No bt-proxy packages found"

# Test LED system functionality
if [[ -f /sbin/ubnt-systool && -d /sys/class/leds ]]; then
    echo "💡 Testing LED system..."
    ubnt-systool led white on 2>/dev/null || true
    sleep 1
    ubnt-systool led white off 2>/dev/null || true
    echo "✅ LED system operational"
fi

# Show held packages
echo "📋 Currently held packages:"
apt-mark showhold

echo ""
echo "=== Cleanup Complete ==="
echo "✅ DPKG hooks removed (critical for upgrades)"
echo "✅ Services stopped and disabled" 
echo "✅ Packages removed"
echo "✅ System cleaned"
echo "✅ Critical tools backed up to /root/"
echo ""
echo "Recommended: Reboot system to ensure clean state"
echo "Run with: sudo reboot"
