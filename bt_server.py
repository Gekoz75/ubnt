#!/usr/bin/env python3
import bluetooth
import subprocess
import time
import sys
import os
import logging

LOGFILE = "/var/log/btserver.log"
logging.basicConfig(filename=LOGFILE, level=logging.INFO,
                    format="%(asctime)s [%(levelname)s] %(message)s")

print("=== CloudKey Bluetooth Shell (No-PIN) ===")

def run_cmd(cmd):
    """Run a shell command quickly and return (stdout + stderr)."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.stdout + result.stderr
    except Exception as e:
        return f"Error: {e}\n"

def setup_bt():
    cmds = [
        "hciconfig hci0 down",
        "hciconfig hci0 up",
        "hciconfig hci0 name 'CloudKey-NoPIN'",
        "hciconfig hci0 sspmode 1",
        "hciconfig hci0 piscan",
        "btmgmt power off",
        "btmgmt io-capability NoInputNoOutput",
        "btmgmt bondable on",
        "btmgmt ssp on",
        "btmgmt power on",
    ]
    for c in cmds:
        subprocess.run(c, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    logging.info("Bluetooth configured for Just Works pairing")

def register_spp():
    """Register Serial Port Profile so Windows sees COM port."""
    subprocess.run("sdptool add SP", shell=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    logging.info("SPP service registered")

def main():
    setup_bt()
    register_spp()

    server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
    server_sock.bind(("", 1))
    server_sock.listen(1)
    logging.info("Bluetooth RFCOMM server started (channel 1)")

    while True:
        try:
            print("Waiting for Bluetooth connection...")
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

if __name__ == "__main__":
    main()
