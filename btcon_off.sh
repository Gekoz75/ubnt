#!/bin/bash
# Bluetooth Serial Console Shutdown Script
# Usage: sudo ./bluetoothConsole_off.sh

echo "=== Stopping Bluetooth Serial Console ==="

# Stop all Bluetooth-related processes
echo "🛑 Stopping Bluetooth services..."
sudo systemctl stop bluetooth 2>/dev/null
sudo pkill -9 bluetoothd 2>/dev/null
sudo pkill -9 rfcomm 2>/dev/null
sudo pkill -9 agetty 2>/dev/null

# Release RFCOMM devices
echo "🔓 Releasing RFCOMM devices..."
sudo rfcomm release all 2>/dev/null

# Remove RFCOMM device file
echo "🧹 Cleaning up device files..."
sudo rm -f /dev/rfcomm0 2>/dev/null

# Reset Bluetooth interface
echo "🔄 Resetting Bluetooth interface..."
sudo hciconfig hci0 down 2>/dev/null

# Optional: Unload kernel modules
# echo "📦 Unloading kernel modules..."
# sudo modprobe -r rfcomm 2>/dev/null
# sudo modprobe -r bnep 2>/dev/null
# sudo modprobe -r btusb 2>/dev/null
# sudo modprobe -r bluetooth 2>/dev/null

echo ""
echo "✅ Bluetooth Serial Console Stopped!"
echo "💡 Use './bluetoothConsole_up.sh' to start again"
echo "💡 Use './bluetooth_mon.sh' to verify shutdown"
