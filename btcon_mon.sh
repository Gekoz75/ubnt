# Create a fixed monitor script
cat > btcon_mon_fixed.sh << 'EOF'
#!/bin/bash
# Bluetooth Status Monitor - Fixed Version

while true; do
    clear
    echo "=== Bluetooth Console Status Monitor ==="
    echo "Time: $(date)"
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
        NAME=$(echo "$HCICONFIG" | grep -o "Name: '[^']*'" | head -1 || echo "Name: Not set")
        echo "🏷️  $NAME"
    else
        echo "❌ No Bluetooth interface found!"
    fi
    
    echo ""
    
    # Process Status
    echo "🔄 PROCESS STATUS:"
    echo "─────────────────"
    if pgrep bluetoothd >/dev/null; then
        echo "✅ bluetoothd: RUNNING"
    else
        echo "❌ bluetoothd: NOT RUNNING"
    fi
    
    if pgrep rfcomm >/dev/null; then
        echo "✅ rfcomm: RUNNING"
    else
        echo "❌ rfcomm: NOT RUNNING"
    fi
    
    echo ""
    
    # Service Status
    echo "📡 SERVICE STATUS:"
    echo "─────────────────"
    if sudo sdptool browse local 2>/dev/null | grep -q "Serial Port"; then
        echo "✅ Serial Port: REGISTERED"
    else
        echo "❌ Serial Port: NOT REGISTERED"
    fi
    
    echo ""
    
    # Device Status
    echo "💾 DEVICE STATUS:"
    echo "────────────────"
    if [ -e "/dev/rfcomm0" ]; then
        echo "✅ /dev/rfcomm0: EXISTS"
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
        NAME=$(hciconfig hci0 2>/dev/null | grep -o "Name: '[^']*'" | cut -d"'" -f2)
        echo "👋 Device Name: ${NAME:-Not set}"
    fi
    
    echo ""
    echo "Press Ctrl+C to stop. Refreshing in 5s..."
    sleep 5
done
EOF

chmod +x btcon_mon_fixed.sh
