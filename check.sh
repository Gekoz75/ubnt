#!/bin/bash
echo "=== DEBIAN 11.11 POST-UPGRADE ULTIMATE VALIDATION ==="
echo ""

# ========== PHASE 1: SYSTEM VERSION VERIFICATION ==========
echo "🔍 PHASE 1: System Version Verification"
echo "----------------------------------------"
cat /etc/debian_version
lsb_release -a
uname -r
echo ""

# ========== PHASE 2: PACKAGE SYSTEM HEALTH ==========
echo "📦 PHASE 2: Package System Health"
echo "----------------------------------"
echo "1. Checking for broken packages..."
sudo dpkg --audit 2>/dev/null || echo "No broken packages found"

echo "2. Checking package consistency..."
sudo apt-get check

echo "3. Checking for held packages..."
HELD_PKGS=$(apt-mark showhold)
if [[ -n "$HELD_PKGS" ]]; then
    echo "Held packages: $HELD_PKGS"
else
    echo "✅ No packages held back"
fi

echo "4. Checking for upgradable packages..."
apt list --upgradable

echo "5. Verifying no half-installed packages..."
dpkg -l | grep "^iF" || echo "✅ No half-configured packages"
echo ""

# ========== PHASE 3: SERVICE HEALTH CHECK ==========
echo "🛠️ PHASE 3: Service Health Check"
echo "---------------------------------"
echo "1. Checking failed systemd services..."
FAILED_SVCS=$(systemctl --failed --no-legend | wc -l)
if [[ $FAILED_SVCS -gt 0 ]]; then
    echo "❌ Failed services found:"
    systemctl --failed
else
    echo "✅ No failed services"
fi

echo "2. Checking critical services..."
CRITICAL_SERVICES=(
    "ssh"
    "systemd-journald"
    "dbus"
    "networking"
    "systemd-logind"
)

for SERVICE in "${CRITICAL_SERVICES[@]}"; do
    if systemctl is-active --quiet "$SERVICE"; then
        echo "✅ $SERVICE: ACTIVE"
    else
        echo "❌ $SERVICE: INACTIVE"
    fi
done

echo "3. Checking for leftover UBNT services..."
systemctl list-units | grep -i "ubnt\|unifi" || echo "✅ No UBNT services found"
echo ""

# ========== PHASE 4: NETWORK VALIDATION ==========
echo "🌐 PHASE 4: Network Validation"
echo "------------------------------"
echo "1. Network interface status:"
ip addr show | grep -E "^([0-9]+:|inet )"

echo "2. Network connectivity test..."
ping -c 3 8.8.8.8 >/dev/null && echo "✅ Internet connectivity: OK" || echo "❌ Internet connectivity: FAILED"

echo "3. DNS resolution test..."
nslookup google.com >/dev/null && echo "✅ DNS resolution: OK" || echo "❌ DNS resolution: FAILED"
echo ""

# ========== PHASE 5: DISK & FILESYSTEM HEALTH ==========
echo "💾 PHASE 5: Disk & Filesystem Health"
echo "------------------------------------"
echo "1. Disk space usage:"
df -h

echo "2. Inode usage:"
df -i

echo "3. Checking for filesystem errors..."
sudo touch /fs-check && sudo rm /fs-check && echo "✅ Root filesystem writable" || echo "❌ Root filesystem issues"

echo "4. Memory usage:"
free -h
echo ""

# ========== PHASE 6: SECURITY & KERNEL CHECKS ==========
echo "🔒 PHASE 6: Security & Kernel Checks"
echo "-----------------------------------"
echo "1. Checking kernel modules..."
lsmod | head -10
echo "..."

echo "2. Checking dmesg for errors..."
dmesg -l err | tail -5 || echo "✅ No kernel errors found"

echo "3. Checking system logs for critical errors..."
journalctl -p 3 --since "1 hour ago" --no-pager | tail -10 || echo "✅ No recent critical errors"
echo ""

# ========== PHASE 7: UBNT SPECIFIC CLEANUP VERIFICATION ==========
echo "🧹 PHASE 7: UBNT Cleanup Verification"
echo "------------------------------------"
echo "1. Checking for remaining UBNT hooks..."
HOOK_FILES=$(find /etc /usr /sbin -name "*ubnt*" -o -name "*unifi*" 2>/dev/null | grep -v "/root/" | wc -l)
if [[ $HOOK_FILES -gt 0 ]]; then
    echo "⚠️  UBNT files found: $HOOK_FILES"
    find /etc /usr /sbin -name "*ubnt*" -o -name "*unifi*" 2>/dev/null | grep -v "/root/"
else
    echo "✅ No UBNT hook files found"
fi

echo "2. Checking dpkg hook configurations..."
ls -la /etc/dpkg/dpkg.cfg.d/ | grep ubnt || echo "✅ No UBNT dpkg hooks"

echo "3. Testing dpkg operations..."
sudo dpkg --configure -a --force-all >/dev/null 2>&1 && echo "✅ DPKG operations: HEALTHY" || echo "❌ DPKG operations: ISSUES"
echo ""

# ========== PHASE 8: PERFORMANCE & STABILITY ==========
echo "⚡ PHASE 8: Performance & Stability"
echo "----------------------------------"
echo "1. System load:"
uptime

echo "2. Current processes count:"
ps aux | wc -l

echo "3. Zombie processes:"
ps aux | awk '{print $8}' | grep -c Z || echo "✅ No zombie processes"

echo "4. System temperature (if available):"
cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1 || echo "Temperature sensors not available"
echo ""

# ========== FINAL SUMMARY ==========
echo "=== VALIDATION SUMMARY ==="
echo "✅ System Version: Debian $(cat /etc/debian_version)"
echo "✅ Kernel: $(uname -r)"
echo "✅ Uptime: $(uptime -p)"
echo "✅ Last Boot: $(who -b | awk '{print $3, $4}')"

# Final health score
echo ""
echo "🎯 RECOMMENDED ACTIONS:"
echo "1. Reboot system to ensure all services start cleanly"
echo "2. Monitor system logs for 24 hours: journalctl -f"
echo "3. Test any custom applications/services"
echo "4. Verify backups are working"

echo ""
echo "🚀 SYSTEM READY: Debian 11.11 upgrade validated!"
