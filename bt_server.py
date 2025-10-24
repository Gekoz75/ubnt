#!/usr/bin/env python3
import os
import pty
import select
import socket
import subprocess
import sys
import time
import logging
from bluetooth import *

# -----------------------------------------------
# Configuration
# -----------------------------------------------
SERVER_NAME = "UniFi-SPP"
BT_ADDR = "74:83:C2:70:F0:1E"  # Your adapter's BD_ADDR
BT_CHANNEL = 1
SERVICE_UUID = "00001101-0000-1000-8000-00805F9B34FB"  # Serial Port UUID

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger("BT-SPP")

# -----------------------------------------------
# Helper to run shell commands
# -----------------------------------------------
def run_cmd(cmd):
    log.debug(f"$ {cmd}")
    proc = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out, _ = proc.communicate()
    out = out.decode(errors="ignore").strip()
    if out:
        log.debug(out)
    return out, proc.returncode

# -----------------------------------------------
# Step 1: Initialize Bluetooth interface
# -----------------------------------------------
def init_bluetooth():
    log.info("=== Bluetooth Initialization ===")
    run_cmd("hciconfig hci0 down")
    time.sleep(1)
    run_cmd("hciconfig hci0 up")
    run_cmd(f"hciconfig hci0 name {SERVER_NAME}")
    run_cmd("hciconfig hci0 class 0x5A020C")  # Smartphone-like, to make visible to Windows
    run_cmd("hciconfig hci0 piscan")  # Discoverable + connectable
    log.info("Adapter is UP and Discoverable")

    out, _ = run_cmd("hciconfig hci0")
    log.debug(out)

# -----------------------------------------------
# Step 2: Remove old SDP records
# -----------------------------------------------
def clean_sdp():
    log.info("Cleaning old SDP records...")
    for handle in range(0x10001, 0x10010):
        out, rc = run_cmd(f"sdptool del 0x{handle:05X}")
        if "not found" not in out:
            log.debug(f"Deleted handle 0x{handle:05X}")

# -----------------------------------------------
# Step 3: Create RFCOMM server
# -----------------------------------------------
def create_rfcomm_server():
    log.info(f"Creating RFCOMM server on {BT_ADDR}, channel {BT_CHANNEL}")
    sock = BluetoothSocket(RFCOMM)
    sock.bind((BT_ADDR, BT_CHANNEL))
    sock.listen(1)
    log.info("RFCOMM socket ready and listening.")
    return sock

# -----------------------------------------------
# Step 4: Register SPP Service
# -----------------------------------------------
def register_spp_service(sock):
    log.info("Registering Serial Port Profile (UUID 1101)...")
    advertise_service(
        sock,
        SERVER_NAME,
        service_id=SERVICE_UUID,
        service_classes=[SERVICE_UUID],
        profiles=[(SERVICE_UUID, 0x0100)],
        provider="UniFi",
        description="UniFi CloudKey Bluetooth SPP Bridge"
    )
    log.info("Service registered successfully.")

# -----------------------------------------------
# Step 5: Create PTY bridge
# -----------------------------------------------
def create_pty():
    master_fd, slave_fd = pty.openpty()
    slave_name = os.ttyname(slave_fd)
    log.info(f"PTY created: {slave_name}")
    return master_fd, slave_name

# -----------------------------------------------
# Step 6: Bridge RFCOMM <-> PTY
# -----------------------------------------------
def bridge_loop(client_sock, master_fd):
    log.info("Starting bidirectional data bridge (RFCOMM <-> PTY)")
    client_sock.setblocking(False)
    try:
        while True:
            rlist, _, _ = select.select([client_sock, master_fd], [], [])
            for src in rlist:
                if src == client_sock:
                    data = client_sock.recv(1024)
                    if not data:
                        log.info("Bluetooth client disconnected.")
                        return
                    os.write(master_fd, data)
                    log.debug(f"[BT→PTY] {data!r}")
                else:
                    data = os.read(master_fd, 1024)
                    if not data:
                        continue
                    client_sock.send(data)
                    log.debug(f"[PTY→BT] {data!r}")
    except KeyboardInterrupt:
        log.info("Interrupted by user.")
    finally:
        client_sock.close()

# -----------------------------------------------
# Main entry point
# -----------------------------------------------
def main():
    log.info("=== Starting Bluetooth SPP Diagnostic Server ===")
    init_bluetooth()
    clean_sdp()

    server_sock = create_rfcomm_server()
    register_spp_service(server_sock)

    master_fd, slave_name = create_pty()
    log.info(f"Waiting for incoming RFCOMM connections... (PTY: {slave_name})")

    try:
        client_sock, client_info = server_sock.accept()
        log.info(f"Accepted Bluetooth connection from {client_info}")
        bridge_loop(client_sock, master_fd)
    except Exception as e:
        log.error(f"Error in main loop: {e}")
    finally:
        server_sock.close()
        log.info("Server stopped.")

if __name__ == "__main__":
    main()
