#!/usr/bin/env python3
import bluetooth
import subprocess
import time
import os
import threading

def pin_handler():
    """Handle PIN requests in background"""
    print("🔄 Starting PIN handler thread...")
    while True:
        try:
            bluetooth.accept_pairing()
            print("✅ PIN pairing accepted")
        except Exception as e:
            if "already exists" not in str(e):
                print(f"PIN handler: {e}")
        time.sleep(1)

print("=== ULTIMATE SERVER WITH PIN ===")

# Start PIN handler in background thread
pin_thread = threading.Thread(target=pin_handler, daemon=True)
pin_thread.start()

# Rest of your server code remains the same...
os.system("sudo hciconfig hci0 down 2>/dev/null")
os.system("sudo hciconfig hci0 up 2>/dev/null")
os.system("sudo hciconfig hci0 sspmode 0 2>/dev/null")
os.system("sudo hciconfig hci0 name 'Win-PIN-0000' 2>/dev/null")
os.system("sudo hciconfig hci0 piscan 2>/dev/null")

time.sleep(2)

server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
server_sock.bind(("", 1))
server_sock.listen(1)

print("✅ Server ready - PIN: 0000")

while True:
    try:
        client_sock, address = server_sock.accept()
        print(f"🎉 CONNECTED: {address}")
        
        client_sock.send(b"Connected! PIN: 0000\n> ")
        
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
