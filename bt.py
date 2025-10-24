#!/usr/bin/env python3
import os, sys, subprocess, time, logging
from bluetooth import *

# ---------- Setup verbose logger ----------
logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
log = logging.getLogger("bt_diag")

def run_cmd(cmd):
    log.debug(f"$ {' '.join(cmd)}")
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        log.debug(out.decode().strip())
        return out.decode().strip()
    except subprocess.CalledProcessError as e:
        log.error(e.output.decode().strip())
        return ""

# ---------- Step 1: Reset HCI ----------
log.info("Resetting Bluetooth interface...")
run_cmd(["hciconfig", "hci0", "down"])
time.sleep(1)
run_cmd(["hciconfig", "hci0", "up"])
run_cmd(["hciconfig", "hci0", "name", "UniFi-SPP"])
run_cmd(["hciconfig", "hci0", "class", "0x5A020C"])  # Smart Phone class
run_cmd(["hciconfig", "hci0", "piscan"])
log.info("Interface hci0 reset and discoverable")

# ---------- Step 2: Diagnostic info ----------
log.info("Checking adapter info:")
run_cmd(["hciconfig", "hci0"])
log.info("Browsing existing SDP records:")
run_cmd(["sdptool", "browse", "local"])

# ---------- Step 3: Clean stale SPP entries ----------
log.info("Removing old RFCOMM bindings...")
os.system("rfcomm release all")
run_cmd(["sdptool", "del", "0x10001"])
run_cmd(["sdptool", "del", "0x10002"])
run_cmd(["sdptool", "del", "0x10003"])
run_cmd(["sdptool", "del", "0x10004"])
run_cmd(["sdptool", "del", "0x10005"])

# ---------- Step 4: Create RFCOMM Server ----------
SERVER_ADDR = "74:83:C2:70:F0:1E"  # Your adapter address
SERVER_PORT = 1
SERVER_NAME = "UniFiSPP"

log.info(f"Starting RFCOMM SPP server on {SERVER_ADDR} channel {SERVER_PORT}...")

server_sock = BluetoothSocket(RFCOMM)
server_sock.bind((SERVER_ADDR, SERVER_PORT))
server_sock.listen(1)

# ---------- Step 5: Register SDP ----------
uuid = SERIAL_PORT_CLASS
service_id = SERIAL_PORT_PROFILE
log.info("Registering Serial Port Profile...")
advertise_service(
    server_sock,
    SERVER_NAME,
    service_id=service_id,
    service_classes=[uuid, SERIAL_PORT_CLASS],
    profiles=[SERIAL_PORT_PROFILE],
    provider="UniFi",
    description="UniFi CloudKey Bluetooth SPP Bridge"
)
log.info("Service registered successfully")

# ---------- Step 6: Accept connections ----------
log.info("Waiting for incoming SPP connections... (Ctrl+C to stop)")
try:
    client_sock, client_info = server_sock.accept()
    log.info(f"Connection from {client_info}")
    while True:
        data = client_sock.recv(1024)
        if not data:
            break
        log.info(f"Received: {data.decode(errors='ignore')}")
        client_sock.send(b"ACK\n")
except KeyboardInterrupt:
    log.info("Server stopped by user")
except Exception as e:
    log.error(f"Error: {e}")
finally:
    client_sock.close()
    server_sock.close()
    log.info("Sockets closed")
