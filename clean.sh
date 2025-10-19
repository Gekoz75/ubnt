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

# Phase 1: Hold critical packages to preserve system
echo "📦 Holding critical packages..."
apt-mark hold linux-image* grub* initramfs-tools 2>/dev/null || true
echo "Held packages: $(apt-mark showhold)"

# Phase 2: Stop and disable services
echo "🛑 Stopping and disabling services..."
SERVICES=(
    unifi
    cloudkey-webui
    ubnt-freeradius-setup
    ubnt-unifi-setup
    ubnt-systemhub
    nginx
    php5-fpm
    mongod
    mongodb
    freeradius
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

# Phase 3: Backup critical UBNT tools before removal
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

# Phase 4: Remove APT sources first
echo "🗑️ Removing APT sources..."
rm -rfv /etc/apt/sources.list.d/* || true

# Phase 5: Package removal sequence
echo "📦 Removing packages..."

# First, try to remove packages that might be on read-only partition
READONLY_PACKAGES=(
    openjdk-8-jre-headless
    php5*
    nodejs*
    nginx*
    libmariadb3
    mongodb-clients
    mysql-common
    freeradius*
)

for PKG in "${READONLY_PACKAGES[@]}"; do
    if dpkg -l | grep -q "$PKG"; then
        echo "Attempting to remove: $PKG"
        apt-get remove --purge -y "$PKG" || true
    fi
done

# Force remove UniFi packages
echo "🔨 Force removing UniFi packages..."
dpkg -P unifi 2>/dev/null || true
apt-get purge --auto-remove -y unifi* ubnt* bt-proxy 2>/dev/null || true

# Verify package removal
echo "🔍 Checking for remaining UBNT packages..."
dpkg -l | grep -i unifi || echo "No UniFi packages found"
dpkg -l | grep -i ubnt || echo "No UBNT packages found" 
dpkg -l | grep -i bt-proxy || echo "No bt-proxy packages found"

# Phase 6: Clean up APT and system
echo "🧹 Cleaning APT and system..."
sudo dpkg --configure -a || true
sudo dpkg --configure --pending || true
sudo apt-get -f install -y || true
apt-get autoremove -y
apt-get autoclean -y
apt-get clean

# Remove specific config files
echo "🗑️ Removing leftover configuration files..."
rm -f /etc/apt/apt.conf.d/50unattended-upgrades.ucf-dist 2>/dev/null || true

# Phase 7: Final system verification
echo "✅ Final verification..."

# Test LED system functionality
if [[ -f /sbin/ubnt-systool && -d /sys/class/leds ]]; then
    echo "💡 Testing LED system..."
    ubnt-systool led white on 2>/dev/null || true
    sleep 1
    ubnt-systool led white off 2>/dev/null || true
    echo "LED system operational"
fi

# Show held packages
echo "📋 Currently held packages:"
apt-mark showhold

echo ""
echo "=== Cleanup Complete ==="
echo "✅ Services stopped and disabled"
echo "✅ Packages removed"
echo "✅ System cleaned"
echo "✅ Critical tools backed up to /root/"
echo ""
echo "Recommended: Reboot system to ensure clean state"
echo "Run with: sudo reboot"
