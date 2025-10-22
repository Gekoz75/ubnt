#!/bin/bash
# Bluetooth Serial Console Startup Script
# Usage: sudo ./bluetoothConsole_up.sh

echo "=== Starting Bluetooth Serial Console ==="

# Stop any existing Bluetooth processes
echo "🛑 Stopping existing Bluetooth services..."
sudo systemctl stop bluetooth 2>/dev/null
sudo pkill -9 bluetoothd 2>/dev/null
sudo pkill -9 rfcomm 2>/dev/null
sudo pkill -9 agetty 2>/dev/null

# Clean up any stale state
echo "🧹 Cleaning up Bluetooth state..."
sudo rfcomm release all 2>/dev/null
sudo rm -f /dev/rfcomm0 2>/dev/null

# Wait for cleanup
sleep 2

# Reload kernel modules if needed
echo "🔧 Reloading Bluetooth modules..."
sudo modprobe -r rfcomm 2>/dev/null
sudo modprobe -r btusb 2>/dev/null
sudo modprobe -r bluetooth 2>/dev/null
sleep 1
sudo modprobe bluetooth
sudo modprobe btusb
sudo modprobe rfcomm
sleep 2

# Bring up Bluetooth interface
echo "📡 Initializing Bluetooth hardware..."
sudo hciconfig hci0 down 2>/dev/null
sudo hciconfig hci0 up
sudo hciconfig hci0 class 0x3e0100  # Computer class for better compatibility
sudo hciconfig hci0 name "CloudKey-Serial"
sudo hciconfig hci0 piscan
sudo hciconfig hci0 sspmode 0       # Disable secure simple pairing

# Start Bluetooth daemon in compatibility mode
echo "🚀 Starting Bluetooth daemon..."
sudo bluetoothd -C --compat --noplugin=sap,avrcp,a2dp &

# Wait for daemon to start
sleep 3

# Add Serial Port service
echo "🔌 Registering Serial Port service..."
sudo sdptool add --channel=1 SP

# Start RFCOMM listener
echo "📡 Starting RFCOMM serial console..."
sudo rfcomm watch hci0 1 /sbin/agetty rfcomm0 115200 linux &

# Wait and verify
sleep 2

echo ""
echo "✅ Bluetooth Serial Console Started!"
echo "📋 Connection Info:"
echo "   Device Name: CloudKey-Serial"
echo "   MAC Address: $(hciconfig hci0 | grep -o 'BD Address: [0-9A-F:]\+' | cut -d' ' -f3)"
echo "   RFCOMM Channel: 1"
echo "   Baud Rate: 115200"
echo ""
echo "💡 Use './bluetooth_mon.sh' to monitor status"
echo "💡 Use './bluetoothConsole_off.sh' to stop"
