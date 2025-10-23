#!/usr/bin/env python3
import bluetooth
import subprocess
import time
import logging
import os
import sys

LOGFILE = "/var/log/btserver.log"
logging.basicConfig(filename=LOGFILE, level=logging.INFO,
                    format="%(asctime)s [%(levelname)s] %(message)s")

DEVICE_NAME = "CloudKey-NoPIN"

def sh(cmd):
    """Run shell command quietly."""
    subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)

def setup_bt():
    logging.info("Setting up Bluetooth adapter...")
    cmds = [
        "hciconfig hci0 down",
        f"hciconfig hci0 name '{DEVICE_NAME}'",
        "hciconfig hci0 sspmode 1",
        "hciconfig hci0 up piscan",      # ensure discoverable + page scan
        "btmgmt power off",
        "btmgmt io-capability NoInputNoOutput",
        "btmgmt bondable on",
        "btmgmt ssp on",
        "btmgmt connectable on",
        "btmgmt discoverable on",
        "btmgmt power on"
    ]
    for c in cmds:
        sh(c)
    logging.info("Bluetooth configured for Just Works pairing")

def advertise():
    """Register Serial Port Profile in SDP."""
    try:
        bluetooth.advertise_service(
            server_sock,
            "CloudKeyShell",
            service_id="00001101-0000-1000-8000-00805F9B34FB",
            service_classes=["00001101-0000-1000-8000-00805F9B34FB", bluetooth.SERIAL_PORT_CLASS],
            profiles=[bluetooth.SERIAL_PORT_PROFILE],
        )
        logging.info("SPP advertised via SDP")
    except Exception as e:
        logging.error(f"SDP advertise failed: {e}")

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.stdout + result.stderr
    except Exception as e:
        return f"Error: {e}\n"

if __name__ == "__main__":
    print(f"=== {DEVICE_NAME} Bluetooth Shell (No-PIN) ===")
    setup_bt()

    server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
    server_sock.bind(("", 1))
    server_sock.listen(1)
    advertise()

    print("📡 Waiting for Bluetooth connections...")
    logging.info("Bluetooth RFCOMM server started")

    while True:
        try:
            client_sock, addr = server_sock.accept()
            logging.info(f"Client connected: {addr}")
            print(f"🎉 CONNECTED: {addr}")
            client_sock.send(b"Connected to CloudKey!\n> ")

            while True:
                data = client_sock.recv(1024).decode(errors="ignore").strip()
                if not data:
                    break
                output = run_cmd(data)
                client_sock.send(output.encode() + b"> ")

        except Exception as e:
            logging.error(f"Error: {e}")
            time.sleep(1)
        finally:
            try:
                client_sock.close()
                logging.info("Client disconnected")
            except:
                pass
