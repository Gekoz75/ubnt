# Create Windows-compatible server
cat > win_bt_server.py << 'EOF'
#!/usr/bin/env python3
import bluetooth
import subprocess
import time
import os

print("=== WINDOWS-COMPATIBLE BLUETOOTH SERVER ===")

# Comprehensive Bluetooth setup for Windows compatibility
print("🔄 Configuring Bluetooth for Windows...")
os.system("sudo hciconfig hci0 down 2>/dev/null")
os.system("sudo hciconfig hci0 up 2>/dev/null")
os.system("sudo hciconfig hci0 class 0x3e0100 2>/dev/null")  # Computer class
os.system("sudo hciconfig hci0 name 'Win-CloudKey' 2>/dev/null")
os.system("sudo hciconfig hci0 piscan 2>/dev/null")

# Wait for Bluetooth to stabilize
time.sleep(2)

print("✅ Bluetooth configured:")
os.system("hciconfig hci0 | grep -E 'BD Address|Name'")

# Create server socket
server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
server_sock.bind(("", 1))
server_sock.listen(1)

# Enhanced service advertisement for Windows
print("🔄 Advertising service for Windows...")
try:
    bluetooth.advertise_service(
        server_sock,
        "Serial Port",
        service_id=bluetooth.SERIAL_PORT_CLASS,
        service_classes=[bluetooth.SERIAL_PORT_CLASS, bluetooth.GENERIC_TELEPHONY_SERVICE_CLASS],
        profiles=[bluetooth.SERIAL_PORT_PROFILE],
        provider="Ubiquiti CloudKey",
        description="Serial Console Port",
        protocols=[bluetooth.RFCOMM_UUID]
    )
    print("✅ Service advertised for Windows compatibility")
except Exception as e:
    print(f"⚠️  Service advertisement: {e}")

print("")
print("🎯 SERVER READY FOR WINDOWS 11")
print("📍 MAC Address: 74:83:C2:70:F0:1E")
print("🏷️  Device Name: Win-CloudKey")
print("🔗 RFCOMM Channel: 1")
print("⏰ Waiting for Windows connection...")
print("")

# Remove timeout to wait indefinitely for Windows
server_sock.settimeout(None)

while True:
    try:
        print("🔍 Actively listening for Windows connections...")
        client_sock, address = server_sock.accept()
        print(f"🎉 WINDOWS CONNECTED: {address}")
        
        welcome_msg = b"\n=== Ubiquiti CloudKey Bluetooth Console ===\n> "
        client_sock.send(welcome_msg)
        
        while True:
            data = client_sock.recv(1024).decode().strip()
            if not data:
                print("Windows client disconnected")
                break
                
            print(f"💬 Command from Windows: {data}")
            
            if data.lower() in ['exit', 'quit']:
                client_sock.send(b"Goodbye from CloudKey!\n")
                break
                
            # Execute command
            try:
                result = subprocess.run(data, shell=True, capture_output=True, text=True, timeout=10)
                output = result.stdout + result.stderr
                if not output:
                    output = "Command executed successfully\n"
            except Exception as e:
                output = f"Error: {str(e)}\n"
                
            client_sock.send(output.encode() + b"\n> ")
            
        client_sock.close()
        print(f"🔌 Windows connection closed: {address}")
        print("🔄 Waiting for new connections...\n")
        
    except Exception as e:
        print(f"❌ Connection error: {e}")
        print("🔄 Restarting listener...")
        time.sleep(2)
EOF

chmod +x win_bt_server.py
