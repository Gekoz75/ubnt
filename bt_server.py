#!/usr/bin/env python3
import bluetooth
import subprocess
import time
import os

print("=== PIN-ENABLED BLUETOOTH SERVER ===")

# Configure for PIN pairing
os.system("sudo hciconfig hci0 sspmode 0 2>/dev/null")  # Use legacy PIN pairing
os.system("sudo hciconfig hci0 down 2>/dev/null")
os.system("sudo hciconfig hci0 up 2>/dev/null")
os.system("sudo hciconfig hci0 name 'PIN-CloudKey' 2>/dev/null")
os.system("sudo hciconfig hci0 piscan 2>/dev/null")

print("✅ Configured for PIN pairing (0000)")

server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
server_sock.bind(("", 1))
server_sock.listen(1)

print("📍 MAC: 74:83:C2:70:F0:1E")
print("🏷️  Name: PIN-CloudKey")
print("🔑 PIN: 0000")
print("🔄 Waiting for connections...")

while True:
    try:
        client_sock, address = server_sock.accept()
        print(f"🎉 CONNECTED: {address}")
        
        client_sock.send(b"Connected to CloudKey! PIN: 0000\\n> ")
        
        while True:
            data = client_sock.recv(1024).decode().strip()
            if not data:
                break
            print(f"Command: {data}")
            
            try:
                result = subprocess.run(data, shell=True, capture_output=True, text=True)
                output = result.stdout + result.stderr or "OK"
            except Exception as e:
                output = f"Error: {e}"
                
            client_sock.send(output.encode() + b"> ")
            
        client_sock.close()
        print("Client disconnected")
        
    except Exception as e:
        print(f"Error: {e}")
        time.sleep(1)
