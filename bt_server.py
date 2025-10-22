#!/usr/bin/env python3
import bluetooth
import subprocess
import time
import os

print("=== NO-PIN BLUETOOTH SERVER ===")

# Force "Just Works" pairing (no PIN)
os.system("sudo hciconfig hci0 down 2>/dev/null")
os.system("sudo hciconfig hci0 up 2>/dev/null")
os.system("sudo hciconfig hci0 sspmode 1 2>/dev/null")  # ENABLE SSP for "Just Works"
os.system("sudo hciconfig hci0 name 'CloudKey-NoPIN' 2>/dev/null")
os.system("sudo hciconfig hci0 piscan 2>/dev/null")

# Configure for "Just Works" pairing
os.system("sudo btmgmt power off 2>/dev/null")
os.system("sudo btmgmt io-capability NoInputNoOutput 2>/dev/null")
os.system("sudo btmgmt bondable on 2>/dev/null")
os.system("sudo btmgmt ssp on 2>/dev/null")
os.system("sudo btmgmt power on 2>/dev/null")

time.sleep(2)

print("✅ Configured for 'Just Works' pairing (no PIN required)")

server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
server_sock.bind(("", 1))
server_sock.listen(1)

print("📍 MAC: 74:83:C2:70:F0:1E")
print("🏷️  Name: CloudKey-NoPIN")
print("🔓 No PIN required - 'Just Works' pairing")
print("")

while True:
    try:
        client_sock, address = server_sock.accept()
        print(f"🎉 CONNECTED: {address}")
        
        client_sock.send(b"Connected - No PIN required!\n> ")
        
        while True:
            data = client_sock.recv(1024).decode().strip()
            if not data: break
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
        time.sleep(2)
