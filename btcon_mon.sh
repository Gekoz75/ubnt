#!/bin/bash
# Bluetooth Status Monitor and Troubleshooting Script
# Usage: ./bluetooth_mon.sh

echo "=== Bluetooth Console Status Monitor ==="
echo "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    clear
    echo "┌─────────────────────────────────────────────────────┐"
    echo "│            BLUETOOTH CONSOLE MONITOR                │"
    echo "│ $(date) │"
    echo "└─────────────────────────────────────────────────────┘"
    echo ""
    
    # Hardware Status
    echo "🔧 HARDWARE STATUS:"
    echo "──────────────────"
    if hciconfig hci0 >/dev/null 2>&1; then
        HCICONFIG=$(hciconfig hci0)
        echo "✅ Interface: hci0"
        echo "📟 $(echo "$HCICONFIG" | grep "BD Address" | head -1)"
        echo "📊 $(echo "$HCICONFIG" | grep "UP\|DOWN" | head -1)"
        echo "👀 $(echo "$HCICONFIG" | grep "PSCAN\|ISCAN" | head -1)"
        echo "🏷️  Name: $(echo "$HCICONFIG" | grep "Name" | cut -d: -f2 | sed 's/^ *//' || echo "Not set")"
    else
        echo "❌ No Bluetooth interface found!"
    fi
    
    echo ""
    
    # Process Status
    echo "🔄 PROCESS STATUS:"
    echo "─────────────────"
    BLUETOOTHD_PID=$(pgrep bluetoothd)
    if [ -n "$BLUETOOTHD_PID" ]; then
        echo "✅ bluetoothd: RUNNING (PID: $BLUETOOTHD_PID)"
        echo "   Command: $(ps -p $BLUETOOTHD_PID -o cmd=)"
    else
        echo "❌ bluetoothd: NOT RUNNING"
    fi
    
    RFCOMM_PID=$(pgrep rfcomm)
    if [ -n "$RFCOMM_PID" ]; then
        echo "✅ rfcomm: RUNNING (PID: $RFCOMM_PID)"
        echo "   Command: $(ps -p $RFCOMM_PID -o cmd=)"
    else
        echo "❌ rfcomm: NOT RUNNING"
    fi
    
    echo ""
    
    # Service Status
    echo "📡 SERVICE STATUS:"
    echo "─────────────────"
    if sudo sdptool browse local >/dev/null 2>&1; then
        SERIAL_SERVICE=$(sudo sdptool browse local 2>/dev/null | grep -A10 "Serial Port" | head -5)
        if [ -n "$SERIAL_SERVICE" ]; then
            echo "✅ Serial Port: REGISTERED"
            echo "   Channel: $(echo "$SERIAL_SERVICE" | grep "Channel" | cut -d: -f2 | tr -d ' ')"
        else
            echo "⚠️  Serial Port: NOT FOUND in SDP"
        fi
    else
        echo "❌ SDP Server: NOT AVAILABLE"
    fi
    
    echo ""
    
    # Device Status
    echo "💾 DEVICE STATUS:"
    echo "────────────────"
    if [ -e "/dev/rfcomm0" ]; then
        echo "✅ /dev/rfcomm0: EXISTS"
        echo "   Permissions: $(ls -la /dev/rfcomm0 | cut -d' ' -f1)"
    else
        echo "❌ /dev/rfcomm0: NOT FOUND"
    fi
    
    echo ""
    
    # Connection Info
    echo "📱 CONNECTION INFO:"
    echo "──────────────────"
    MAC=$(hciconfig hci0 2>/dev/null | grep -o 'BD Address: [0-9A-F:]\+' | cut -d' ' -f3)
    if [ -n "$MAC" ]; then
        echo "📍 MAC Address: $MAC"
        echo "🔗 RFCOMM Channel: 1"
        echo "⚡ Baud Rate: 115200"
        echo "👋 Device Name: $(hciconfig hci0 2>/dev/null | grep "Name" | cut -d: -f2 | sed 's/^ *//' || echo "Unknown")"
    else
        echo "❌ Cannot read Bluetooth info"
    fi
    
    echo ""
    echo "┌─────────────────────────────────────────────────────┐"
    echo "│          Monitoring... (Refresh every 5s)           │"
    echo "│        Press Ctrl+C to stop monitoring              │"
    echo "└─────────────────────────────────────────────────────┘"
    
    sleep 5
done
