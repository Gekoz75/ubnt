#!/usr/bin/env python3
import os
import pty
import sys
import socket
import subprocess
import threading
import time
import select

# Config
BT_CHANNEL = 1
BT_NAME = "CloudKey-NoPIN"
SERVICE_NAME = "CloudKeyShell"
UUID = "00001101-0000-1000-8000-00805f9b34fb"

def run_cmd(cmd, check=False):
    print(f"[CMD] {' '.join(cmd)}")
    try:
        subprocess.run(cmd, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        print(f"[ERR] {cmd}: {e.stderr.decode().strip()}")

def bt_init():
    print("[INFO] Initializing Bluetooth adapter...")
    run_cmd(["hciconfig", "hci0", "up"])
    run_cmd(["hciconfig", "hci0", "name", BT_NAME])
    run_cmd(["hciconfig", "hci0", "piscan"])
    time.sleep(0.5)

    print("[INFO] Registering SPP service via sdptool...")
    run_cmd(["sdptool", "add", "--channel", str(BT_CHANNEL), "SP"])

def create_rfcomm_server():
    print("[INFO] Creating RFCOMM socket...")
    sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
    sock.bind(("", BT_CHANNEL))
    sock.listen(1)
    print(f"[INFO] Listening on RFCOMM channel {BT_CHANNEL} ({BT_NAME})")
    return sock

def bridge_data(src_fd, dst_fd, label_src, label_dst):
    """Bidirectional data copy"""
    while True:
        r, _, _ = select.select([src_fd], [], [], 0.1)
        if r:
            try:
                data = os.read(src_fd, 1024)
                if not data:
                    print(f"[INFO] {label_src} disconnected.")
                    break
                os.write(dst_fd, data)
            except OSError as e:
                print(f"[WARN] {label_src}->{label_dst} error: {e}")
                break

def handle_client(client_sock, client_info, pty_master):
    print(f"[INFO] Connection from {client_info}")
    client_fd = client_sock.fileno()
    t1 = threading.Thread(target=bridge_data, args=(client_fd, pty_master, "BT", "PTY"))
    t2 = threading.Thread(target=bridge_data, args=(pty_master, client_fd, "PTY", "BT"))
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    client_sock.close()
    print("[INFO] Connection closed")

def main():
    bt_init()
    sock = create_rfcomm_server()
    master, slave = pty.openpty()
    print(f"[INFO] Virtual TTY created: {os.ttyname(slave)}")
    print("[INFO] Waiting for Bluetooth connection...")

    while True:
        client_sock, client_info = sock.accept()
        handle_client(client_sock, client_info, master)

if __name__ == "__main__":
    if os.geteuid() != 0:
        print("[ERROR] Must run as root (Bluetooth sockets need root).")
        sys.exit(1)
    main()
