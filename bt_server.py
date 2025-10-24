#!/usr/bin/env python3
import os
import sys
import subprocess
import bluetooth
import pty
import time

BT_ADDR = "74:83:C2:70:F0:1E"  # Your CloudKey adapter address
BT_CHANNEL = 1
BT_NAME = "CloudKey-NoPIN"

def run_cmd(cmd):
    """Run shell command with output + status."""
    print(f"[CMD] {cmd}")
    result = subprocess.run(cmd, shell=True, text=True, capture_output=True)
    if result.returncode == 0:
        print(f"[OK] {cmd.split()[0]}: {result.stdout.strip() or 'Done'}")
    else:
        print(f"[ERROR] {cmd.split()[0]} failed:\n{result.stderr}")
    return result.returncode

def init_bluetooth():
    """Initialize adapter, name, discoverability, and SDP service."""
    print("[INFO] === Bluetooth Initialization ===")
    run_cmd("hciconfig hci0 up")
    run_cmd(f"hciconfig hci0 name '{BT_NAME}'")
    run_cmd("hciconfig hci0 piscan")

    # Show current adapter info
    run_cmd("hciconfig -a hci0")

    print("[INFO] Registering Serial Port Profile (SPP)...")
    run_cmd("sdptool add --channel=1 SP")

def create_rfcomm_server():
    """Create and bind RFCOMM socket to fixed adapter address."""
    print(f"[INFO] Creating RFCOMM socket bound to {BT_ADDR}:{BT_CHANNEL}")
    try:
        sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
        sock.bind((BT_ADDR, BT_CHANNEL))
        sock.listen(1)
        print(f"[OK] RFCOMM server listening on channel {BT_CHANNEL}")
        return sock
    except OSError as e:
        print(f"[FATAL] RFCOMM bind failed: {e}")
        sys.exit(1)

def setup_pty():
    """Create pseudo-terminal for bridging."""
    print("[INFO] Creating pseudo-terminal (PTY)...")
    master_fd, slave_fd = pty.openpty()
    slave_name = os.ttyname(slave_fd)
    print(f"[OK] PTY created: {slave_name}")
    return master_fd, slave_name

def main():
    print("[INFO] === Starting Bluetooth SPP Diagnostic Server ===")
    init_bluetooth()

    sock = create_rfcomm_server()
    master_fd, slave_name = setup_pty()

    print("[INFO] Waiting for incoming Bluetooth RFCOMM connection...")
    client_sock, client_info = sock.accept()
    print(f"[OK] Connection established from {client_info}")

    # Simple data bridge demo (echo + PTY)
    try:
        while True:
            data = client_sock.recv(1024)
            if not data:
                print("[WARN] Client disconnected.")
                break
            os.write(master_fd, data)
            echo = os.read(master_fd, 1024)
            if echo:
                client_sock.send(echo)
    except KeyboardInterrupt:
        print("[INFO] Interrupted, closing sockets.")
    finally:
        client_sock.close()
        sock.close()
        print("[OK] Bluetooth server shut down cleanly.")

if __name__ == "__main__":
    main()
