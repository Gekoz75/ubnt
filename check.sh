#!/bin/bash
# Ultimate Debian Post-Upgrade Validation Script
# Comprehensive system health check with critical kernel protection

echo "=== DEBIAN POST-UPGRADE ULTIMATE VALIDATION ==="
echo ""

# ========== CRITICAL: VERIFY BACKUP TOOLS EXIST ==========
echo "💾 CRITICAL: Verifying backup tools..."
CRITICAL_BACKUPS=(
    "/root/ubnt-systool.backup"
    "/root/ubnt-dpkg-restore.backup"
)

BACKUP_OK=0
for BACKUP in "${CRITICAL_BACKUPS[@]}"; do
    if [[ -f "$BACKUP" ]]; then
        echo "✅ Backup found: $(basename "$BACKUP")"
        ((BACKUP_OK++))
    else
        echo "❌ MISSING BACKUP: $(basename "$BACKUP")"
        echo "   Run: ./clean.sh to create backups first!"
    fi
done

if [ $BACKUP_OK -eq 2 ]; then
    echo "✅ ALL critical backups verified"
else
    echo "⚠️  WARNING: Only $BACKUP_OK/2 backups found"
    echo "   Some system tools may be missing"
fi

# ========== CRITICAL: PROTECT CUSTOM KERNEL ==========
echo ""
echo "🔒 CRITICAL: Verifying kernel protection..."
sudo apt-mark hold linux-image-3.10.20-ubnt-mtk initramfs-tools >/dev/null 2>&1 || true
HELD_PKGS=$(apt-mark showhold)
if echo "$HELD_PKGS" | grep -q "linux-image-3.10.20-ubnt-mtk"; then
    echo "✅ Custom kernel protected: linux-image-3.10.20-ubnt-mtk"
else
    echo "⚠️  Custom kernel NOT held - protecting now..."
    sudo apt-mark hold linux-image-3.10.20-ubnt-mtk
fi

# ========== PHASE 1: SYSTEM VERSION VERIFICATION ==========
echo ""
echo "🔍 PHASE 1: System Version Verification"
echo "----------------------------------------"
DEBIAN_VERSION=$(cat /etc/debian_version 2>/dev/null || echo "unknown")
KERNEL_VERSION=$(uname -r)
echo "Debian: $DEBIAN_VERSION"
echo "Kernel: $KERNEL_VERSION"

if command -v lsb_release >/dev/null 2>&1; then
    echo "Release: $(lsb_release -sd 2>/dev/null || echo "unknown")"
    echo "Codename: $(lsb_release -sc 2>/dev/null || echo "unknown")"
fi

# Version validation
case "$DEBIAN_VERSION" in
    11*|"bullseye"*) echo "✅ Target version: Debian 11/Bullseye" ;;
    10*|"buster"*) echo "⚠️  Intermediate version: Debian 10/Buster" ;;
    9*|"stretch"*) echo "❌ Stuck version: Debian 9/Stretch" ;;
    8*|"jessie"*) echo "❌ Critical: Still on Debian 8/Jessie" ;;
    *) echo "⚠️  Unknown version: $DEBIAN_VERSION" ;;
esac

# ========== PHASE 2: PACKAGE SYSTEM HEALTH ==========
echo ""
echo "📦 PHASE 2: Package System Health"
echo "----------------------------------"

# Check for broken packages
echo "1. Checking package consistency..."
if sudo dpkg --audit 2>/dev/null | grep -q .; then
    echo "❌ Broken packages found - run: sudo dpkg --configure -a"
    sudo dpkg --audit 2>/dev/null | head -5
else
    echo "✅ No broken packages"
fi

# Check for half-installed packages
if dpkg -l 2>/dev/null | grep -q "^iF"; then
    echo "❌ Half-configured packages found"
    dpkg -l 2>/dev/null | grep "^iF" || true
else
    echo "✅ No half-configured packages"
fi

# Check upgradable packages (excluding held ones)
echo "2. Checking upgradable packages..."
UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
if [ "$UPGRADABLE" -gt 0 ]; then
    echo "⚠️  $UPGRADABLE packages can be upgraded (excluding held packages):"
    apt list --upgradable 2>/dev/null | head -10
    if [ "$UPGRADABLE" -gt 10 ]; then
        echo "... and $((UPGRADABLE - 10)) more"
    fi
else
    echo "✅ All packages up to date"
fi

# Verify held packages
HELD_COUNT=$(apt-mark showhold 2>/dev/null | wc -l)
echo "3. Held packages: $HELD_COUNT"
if [ "$HELD_COUNT" -gt 0 ]; then
    echo "📋 Held packages:"
    apt-mark showhold 2>/dev/null
fi

# ========== NEW: BLOATWARE DETECTION ==========
echo ""
echo "🔍 BLOATWARE DETECTION"
echo "----------------------"

# Check largest packages
echo "4. Largest packages (top 10):"
dpkg-query -W --showformat='${Installed-Size}\t${Package}\n' 2>/dev/null | sort -nr | head -10

# Check total package count
TOTAL_PACKAGES=$(dpkg -l 2>/dev/null | grep -c '^ii' || echo "0")
echo "5. Total installed packages: $TOTAL_PACKAGES"
if [ "$TOTAL_PACKAGES" -gt 500 ]; then
    echo "   ⚠️  High package count - consider cleanup"
else
    echo "   ✅ Reasonable package count for embedded system"
fi

# Check for common bloatware
echo "6. Checking for common bloatware:"
BLOAT_FOUND=$(apt list --installed 2>/dev/null | grep -c -E "(avahi|cups|exim4)" || echo "0")
if [ "$BLOAT_FOUND" -gt 0 ]; then
    echo "   ❌ BLOATWARE FOUND:"
    apt list --installed 2>/dev/null | grep -E "(avahi|cups|exim4)" | while read pkg; do
        echo "      - $pkg"
    done
else
    echo "   ✅ No common bloatware detected"
fi

# Check Debian-exim statoverride issue
echo "7. Checking Debian-exim statoverride:"
if grep -q "Debian-exim" /var/lib/dpkg/statoverride 2>/dev/null; then
    echo "   ❌ Debian-exim in statoverride - WILL CAUSE UPGRADE FAILURES!"
else
    echo "   ✅ No Debian-exim statoverride issues"
fi

# ========== PHASE 3: SERVICE HEALTH CHECK ==========
echo ""
echo "🛠️ PHASE 3: Service Health Check"
echo "---------------------------------"

# Check failed services
FAILED_SVCS=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
if [ "$FAILED_SVCS" -gt 0 ]; then
    echo "❌ Failed services: $FAILED_SVCS"
    systemctl --failed --no-legend 2>/dev/null || true
else
    echo "✅ No failed services"
fi

# Check critical services
echo "8. Critical services status:"
CRITICAL_SERVICES=("ssh" "systemd-journald" "dbus" "systemd-logind")
for SERVICE in "${CRITICAL_SERVICES[@]}"; do
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
        echo "  ✅ $SERVICE: ACTIVE"
    else
        echo "  ❌ $SERVICE: INACTIVE"
    fi
done

# Check networking (may show inactive but work)
if ip route show default 2>/dev/null | grep -q default; then
    echo "  ✅ Network routing: CONFIGURED"
else
    echo "  ⚠️  Network routing: NO DEFAULT ROUTE"
fi

# Check for UBNT service leftovers
UBNT_SERVICES=$(systemctl list-units --all --no-legend 2>/dev/null | grep -i "ubnt\|unifi" | wc -l || echo "0")
if [ "$UBNT_SERVICES" -gt 0 ]; then
    echo "⚠️  UBNT service leftovers: $UBNT_SERVICES"
    systemctl list-units --all --no-legend 2>/dev/null | grep -i "ubnt\|unifi" | head -5
else
    echo "✅ No UBNT services found"
fi

# ========== PHASE 4: NETWORK VALIDATION ==========
echo ""
echo "🌐 PHASE 4: Network Validation"
echo "------------------------------"

# Interface status
echo "9. Network interfaces:"
ip -o addr show scope global 2>/dev/null | awk '{print "  " $2 ": " $4}' | head -5

# Connectivity tests
echo "10. Connectivity tests:"
if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
    echo "  ✅ Internet connectivity: OK"
else
    echo "  ❌ Internet connectivity: FAILED"
fi

if ping -c 2 -W 3 google.com >/dev/null 2>&1; then
    echo "  ✅ DNS resolution: OK"
else
    echo "  ❌ DNS resolution: FAILED"
fi

# ========== PHASE 5: DISK & FILESYSTEM HEALTH ==========
echo ""
echo "💾 PHASE 5: Disk & Filesystem Health"
echo "------------------------------------"

# Disk space
ROOT_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {print $5 " used (" $4 " free)"}' || echo "unknown")
echo "11. Root filesystem: $ROOT_USAGE"

ROOT_USAGE_PCT=$(df / 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}' | head -1 || echo "0")
if [ "$ROOT_USAGE_PCT" -gt 90 ] 2>/dev/null; then
    echo "  ❌ Disk space: CRITICAL (>90% used)"
else
    echo "  ✅ Disk space: SUFFICIENT"
fi

# Memory
MEM_USAGE=$(free -h 2>/dev/null | awk 'NR==2 {print "Total: " $2 " | Used: " $3 " | Free: " $4}' || echo "unknown")
echo "12. Memory: $MEM_USAGE"

# Filesystem health
if touch /fs-test && rm /fs-test 2>/dev/null; then
    echo "  ✅ Root filesystem: WRITABLE"
else
    echo "  ❌ Root filesystem: READ-ONLY ISSUES"
fi

# ========== PHASE 6: UBNT LEFTOVER CLEANUP CHECK ==========
echo ""
echo "🧹 PHASE 6: UBNT Leftover Check"
echo "--------------------------------"

# Check for UBNT files
UBNT_FILES=$(find /etc /usr /sbin -name "*ubnt*" -o -name "*unifi*" 2>/dev/null | grep -v "/root/\|/proc/" | wc -l)
if [ "$UBNT_FILES" -gt 0 ]; then
    echo "⚠️  UBNT files found: $UBNT_FILES"
    echo "   Run cleanup with: ./clean.sh --post-upgrade"
    find /etc /usr /sbin -name "*ubnt*" -o -name "*unifi*" 2>/dev/null | grep -v "/root/\|/proc/" | head -5
    if [ "$UBNT_FILES" -gt 5 ]; then
        echo "   ... and $((UBNT_FILES - 5)) more"
    fi
else
    echo "✅ No UBNT leftover files"
fi

# Check dpkg hooks
if ls /etc/dpkg/dpkg.cfg.d/*ubnt* 2>/dev/null; then
    echo "❌ UBNT dpkg hooks still present"
else
    echo "✅ No UBNT dpkg hooks"
fi

# ========== PHASE 7: SYSTEM STABILITY CHECKS ==========
echo ""
echo "⚡ PHASE 7: System Stability"
echo "---------------------------"

# System load
echo "13. System load: $(uptime | awk -F'load average:' '{print $2}')"

# Zombie processes
ZOMBIES=$(ps aux 2>/dev/null | awk '{print $8}' | grep -c Z || echo "0")
if [ "$ZOMBIES" -gt 0 ]; then
    echo "❌ Zombie processes: $ZOMBIES"
else
    echo "✅ No zombie processes"
fi

# Kernel errors
KERNEL_ERRORS=$(dmesg -l err 2>/dev/null | tail -5 | wc -l)
if [ "$KERNEL_ERRORS" -gt 0 ]; then
    echo "⚠️  Recent kernel errors: $KERNEL_ERRORS"
    dmesg -l err 2>/dev/null | tail -3
else
    echo "✅ No recent kernel errors"
fi

# Temperature (if available)
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | head -1)
    if [ -n "$TEMP" ]; then
        TEMP_C=$((TEMP/1000))
        echo "🌡️  CPU temperature: ${TEMP_C}°C"
    fi
fi

# ========== PHASE 8: AUTOMATIC FIXES ==========
echo ""
echo "🔧 PHASE 8: Automatic Fixes"
echo "---------------------------"

FIXES_APPLIED=0

# Fix failed services
if systemctl is-failed infctld.service 2>/dev/null; then
    echo "🛠️  Fixing failed infctld.service..."
    sudo systemctl disable infctld.service 2>/dev/null || true
    sudo systemctl mask infctld.service 2>/dev/null || true
    ((FIXES_APPLIED++))
fi

if systemctl is-failed e2scrub_reap.service 2>/dev/null; then
    echo "🛠️  Fixing failed e2scrub_reap.service..."
    sudo systemctl disable e2scrub_reap.service 2>/dev/null || true
    sudo systemctl reset-failed e2scrub_reap.service 2>/dev/null || true
    ((FIXES_APPLIED++))
fi

# Fix networking service
if ! systemctl is-active networking >/dev/null 2>&1; then
    echo "🛠️  Enabling networking service..."
    sudo systemctl enable networking 2>/dev/null || true
    ((FIXES_APPLIED++))
fi

# Remove critical UBNT leftovers
if [ -f "/etc/default/ubnt-dpkg-cache" ]; then
    echo "🛠️  Removing UBNT dpkg cache..."
    sudo rm -f /etc/default/ubnt-dpkg-cache 2>/dev/null || true
    ((FIXES_APPLIED++))
fi

if [ -f "/etc/fwupdate/post.d/020-ubnt-dpkg-restore" ]; then
    echo "🛠️  Removing UBNT fwupdate hook..."
    sudo rm -f /etc/fwupdate/post.d/020-ubnt-dpkg-restore 2>/dev/null || true
    ((FIXES_APPLIED++))
fi

# Fix Debian-exim statoverride if needed
if grep -q "Debian-exim" /var/lib/dpkg/statoverride 2>/dev/null; then
    echo "🛠️  Fixing Debian-exim statoverride..."
    sudo sed -i '/Debian-exim/d' /var/lib/dpkg/statoverride
    ((FIXES_APPLIED++))
fi

if [ $FIXES_APPLIED -eq 0 ]; then
    echo "✅ No automatic fixes needed"
else
    echo "🛠️  Applied $FIXES_APPLIED automatic fixes"
fi

# ========== FINAL SUMMARY & RECOMMENDATIONS ==========
echo ""
echo "=== VALIDATION SUMMARY ==="
echo "✅ Debian Version: $DEBIAN_VERSION"
echo "✅ Kernel: $KERNEL_VERSION"
echo "✅ Uptime: $(uptime -p 2>/dev/null | sed 's/up //' || echo 'unknown')"
echo "✅ Held Packages: $HELD_COUNT (kernel protected)"
echo "✅ Critical Backups: $BACKUP_OK/2 verified"
echo "📦 Total Packages: $TOTAL_PACKAGES"
if [ $BLOAT_FOUND -gt 0 ]; then
    echo "⚠️  Bloatware Packages: $BLOAT_FOUND"
fi

# Overall health score
ISSUES=0
[ "$FAILED_SVCS" -gt 0 ] && ((ISSUES++))
[ "$UBNT_FILES" -gt 10 ] && ((ISSUES++))
[ "$ROOT_USAGE_PCT" -gt 90 ] 2>/dev/null && ((ISSUES++))
ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ((ISSUES++))
[ $BACKUP_OK -lt 2 ] && ((ISSUES++))
[ $BLOAT_FOUND -gt 0 ] && ((ISSUES++))

echo ""
echo "🎯 RECOMMENDATIONS:"
if [ "$ISSUES" -eq 0 ]; then
    echo "🚀 SYSTEM EXCELLENT - Upgrade successful!"
    echo "   No critical issues found"
elif [ "$ISSUES" -le 2 ]; then
    echo "✅ SYSTEM GOOD - Minor issues"
    echo "   Review warnings above"
else
    echo "⚠️  SYSTEM NEEDS ATTENTION - $ISSUES issues"
    echo "   Address critical items above"
fi

echo ""
echo "📋 Next steps:"
if [ $BACKUP_OK -lt 2 ]; then
    echo "   1. RUN: ./clean.sh (to create missing backups)"
fi
if [ $BLOAT_FOUND -gt 0 ]; then
    echo "   2. RUN BLOATWARE CLEANUP:"
    echo "      sudo apt-get remove --purge -y avahi-daemon libavahi-* libcups2 exim4* && sudo sed -i '/Debian-exim/d' /var/lib/dpkg/statoverride && sudo apt-get autoremove --purge -y"
fi
echo "   3. Review any warnings above"
echo "   4. Run: ./clean.sh --post-upgrade (if UBNT leftovers)"
echo "   5. Reboot: sudo reboot"
echo "   6. Run this check again after reboot"

echo ""
echo "💡 Remember: linux-image-3.10.20-ubnt-mtk is PROTECTED"
echo "   This custom kernel is required for hardware compatibility"
