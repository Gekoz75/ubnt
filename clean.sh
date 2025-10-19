#!/bin/bash
# Clean removal of UniFi controller + web UI, keep ubnt-systool and ubnt-dpkg-restore

trap ctrl_c INT
function ctrl_c() {
  echo "Resetting LED to defaults..."
  ubnt-systool reset2defaults
}

echo "=== UBNT Cleanup Script ==="

# Disable all UniFi/UBNT controller-related services
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
)

for SVC in "${SERVICES[@]}"; do
  if systemctl list-units --full -all | grep -q "$SVC"; then
    echo "Disabling and stopping $SVC ..."
    systemctl stop "$SVC" 2>/dev/null
    systemctl disable "$SVC" 2>/dev/null
  fi
done

# Remove Ubiquiti packages safely
echo "Removing UniFi and related packages..."
apt-get remove --purge -y unifi unifi-core unifi-video ubnt-freeradius nginx php5-fpm mongodb-server mongodb mongodb-org

# Clean APT caches and old configs
apt-get autoremove -y
apt-get autoclean -y

# Preserve ubnt-systool and ubnt-dpkg-restore
echo "Preserving ubnt-systool and ubnt-dpkg-restore..."
if [ -f /sbin/ubnt-systool ]; then
  cp /sbin/ubnt-systool /root/ubnt-systool.backup
fi
if [ -f /sbin/ubnt-dpkg-restore ]; then
  cp /sbin/ubnt-dpkg-restore /root/ubnt-dpkg-restore.backup
fi

# Ensure LED system still operational
if [ -d /sys/class/leds ]; then
  echo "Testing LED system..."
  /sbin/ubnt-systool led white on 2>/dev/null
  sleep 1
  /sbin/ubnt-systool led white off 2>/dev/null
fi

echo "Cleanup complete. You may reboot now if system is stable."
echo "Backups saved in /root/"
