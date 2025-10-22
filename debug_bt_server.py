#!/usr/bin/env python3
import bluetooth
import subprocess
import time

print("=== DEBUG Bluetooth Server ===")
print("Setting up...")

# Set Bluetooth name via system command
import os
os.system("sudo hciconfig hci0 name 'CloudKey-Debug' 2>/dev/null")

server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
server_sock.bind(("", 1))
server_sock.listen(1)

# Try to advertise service
try:
    bluetooth.advertise_service(server_sock, "SerialConsole",
                               service_classes=[bluetooth.SERIAL_PORT_CLASS],
                               profiles=[bluetooth.SERIAL_PORT_PROFILE])
    print("✅ Service advertised")
except Exception as e:
    print(f"⚠️  Service ad failed: {e}")

print("✅ Listening on RFCOMM channel 1")
print("📍 MAC: 74:83:C2:70:F0:1E")
print("🏷️  Name: CloudKey-Debug")
print("📡 Waiting for connections...")

# Set socket timeout
server_sock.settimeout(5.0)

while True:
    try:
        print("Listening for connections...")
        client_sock, address = server_sock.accept()
        print(f"🎉 CONNECTED: {address}")
        
        client_sock.send(b"=== CloudKey Bluetooth Console ===\\n> ")
        
        while True:
            data = client_sock.recv(1024).decode().strip()
            if not data:
                print("Client disconnected")
                break
                
            print(f"Command from {address}: {data}")
            
            if data.lower() in ['exit', 'quit']:
                client_sock.send(b"Goodbye!\\n")
                break
                
            # Execute command
            try:
                result = subprocess.run(data, shell=True, capture_output=True, text=True, timeout=10)
                output = result.stdout + result.stderr
                if not output:
                    output = "Command executed\\n"
            except Exception as e:
                output = f"Error: {str(e)}\\n"
                
            client_sock.send(output.encode() + b"> ")
            
        client_sock.close()
        print(f"Connection closed: {address}")
        
    except bluetooth.btcommon.BluetoothError as e:
        print(f"Bluetooth error: {e}")
        time.sleep(2)
    except Exception as e:
        print(f"Other error: {e}")
        time.sleep(2)
