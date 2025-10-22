#!/usr/bin/env python3
import bluetooth
import subprocess
import time
import os

print("=== ULTIMATE BLUETOOTH SERVER ===")
print("🖥️  Windows Visible + 🔑 PIN 0000 Support")

# STOP any existing Bluetooth configuration first
os.system("sudo pkill bluetoothd 2>/dev/null")
os.system("sudo hciconfig hci0 down 2>/dev/null")

# Windows-optimized Bluetooth setup for MAXIMUM visibility
print("🔄 Configuring Bluetooth for Windows discovery...")
os.system("sudo hciconfig hci0 up 2>/dev/null")
os.system("sudo hciconfig hci0 sspmode 0 2>/dev/null")  # CRITICAL: Enable legacy PIN pairing
os.system("sudo hciconfig hci0 class 0x3e0100 2>/dev/null")  # Computer class
os.system("sudo hciconfig hci0 name 'Win-CloudKey-PIN0000' 2>/dev/null")
os.system("sudo hciconfig hci0 piscan 2>/dev/null")
os.system("sudo hciconfig hci0 inqmode 1 2>/dev/null")  # Extended inquiry
os.system("sudo hciconfig hci0 inqtpl 2 2>/dev/null")   # Higher power

# Start Bluetooth daemon for service advertising
os.system("sudo bluetoothd -C --compat & 2>/dev/null")

# Wait for Bluetooth to stabilize
time.sleep(3)

print("")
print("✅ BLUETOOTH CONFIGURED:")
os.system("hciconfig hci0 | grep -E 'BD Address|Name|UP|PSCAN'")

# Create server socket
server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
server_sock.bind(("", 1))  # Channel 1
server_sock.listen(1)

# Enhanced service advertisement for Windows
print("🔄 Advertising service for Windows...")
try:
    bluetooth.advertise_service(
        server_sock,
        "Serial Port",
        service_id=bluetooth.SERIAL_PORT_CLASS,
        service_classes=[bluetooth.SERIAL_PORT_CLASS],
        profiles=[bluetooth.SERIAL_PORT_PROFILE],
        provider="Ubiquiti CloudKey",
        description="Serial Console"
    )
    print("✅ Service advertised successfully")
except Exception as e:
    print(f"⚠️  Service advertisement: {e}")

print("")
print("🎯 ULTIMATE SERVER READY!")
print("📍 MAC Address: 74:83:C2:70:F0:1E")
print("🏷️  Device Name: Win-CloudKey-PIN0000")
print("🔑 Pairing PIN: 0000")
print("🔗 RFCOMM Channel: 1")
print("🖥️  Optimized for Windows 11")
print("")

# Remove timeout to wait indefinitely
server_sock.settimeout(None)

# Main connection loop
connection_count = 0
while True:
    try:
        connection_count += 1
        print(f"🔍 [{connection_count}] Waiting for Windows connection...")
        
        client_sock, address = server_sock.accept()
        print(f"🎉 CONNECTED: {address}")
        
        # Welcome message
        welcome_msg = b"\n" + b"="*50 + b"\n"
        welcome_msg += b"Ubiquiti CloudKey Bluetooth Console\n"
        welcome_msg += b"Device: Win-CloudKey-PIN0000\n"
        welcome_msg += b"PIN: 0000 | Connection Successful!\n"
        welcome_msg += b"="*50 + b"\n"
        welcome_msg += b"> "
        
        client_sock.send(welcome_msg)
        
        # Command processing loop
        while True:
            data = client_sock.recv(1024).decode().strip()
            if not data:
                print(f"🔌 Client {address} disconnected")
                break
                
            print(f"💬 Command from {address}: {data}")
            
            # Handle exit commands
            if data.lower() in ['exit', 'quit', 'bye']:
                client_sock.send(b"Goodbye from CloudKey!\n")
                break
                
            # Execute command
            try:
                result = subprocess.run(
                    data, 
                    shell=True, 
                    capture_output=True, 
                    text=True, 
                    timeout=10
                )
                output = result.stdout + result.stderr
                if not output:
                    output = "Command executed (no output)\n"
            except subprocess.TimeoutExpired:
                output = "Error: Command timed out (10s limit)\n"
            except Exception as e:
                output = f"Error: {str(e)}\n"
                
            # Send response
            client_sock.send(output.encode() + b"\n> ")
            
        # Cleanup connection
        client_sock.close()
        print(f"🔄 Ready for new connection...\n")
        
    except bluetooth.btcommon.BluetoothError as e:
        print(f"❌ Bluetooth error: {e}")
        time.sleep(2)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        time.sleep(2)
