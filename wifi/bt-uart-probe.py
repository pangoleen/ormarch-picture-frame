#!/usr/bin/env python3
"""Probe H4 Read Local Version on the known BT UART. No address query.

Run as root only after booting the UART1 test DTB and loading Wi-Fi firmware.
Does not control GPIOs. Do not run while btattach owns the port.
"""
import argparse
import os
import select
import termios
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--port", default="/dev/ttyS1")
parser.add_argument("--baud", type=int, choices=(115200, 1500000), default=1500000)
parser.add_argument("--flow", action="store_true", help="use hardware RTS/CTS")
args = parser.parse_args()

def local_version_reply(data):
    # Num_HCI_Command_Packets is a variable credit count, not a fixed 1.
    for pos in range(max(0, len(data) - 14)):
        if (data[pos:pos + 3] == bytes.fromhex("04 0e 0c")
                and data[pos + 4:pos + 7] == bytes.fromhex("01 10 00")):
            return True
    return False

fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
old = termios.tcgetattr(fd)
try:
    conf = termios.tcgetattr(fd)
    conf[0] = conf[1] = conf[3] = 0
    conf[2] = termios.CLOCAL | termios.CREAD | termios.CS8
    if args.flow:
        conf[2] |= termios.CRTSCTS
    conf[4] = conf[5] = getattr(termios, "B" + str(args.baud))
    conf[6][termios.VMIN] = 0
    conf[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, conf)
    termios.tcflush(fd, termios.TCIOFLUSH)
    os.write(fd, bytes.fromhex("01 01 10 00"))
    data = bytearray()
    end = time.monotonic() + 3
    while time.monotonic() < end:
        if select.select([fd], [], [], max(0, min(0.2, end - time.monotonic())))[0]:
            data.extend(os.read(fd, 256))
        if local_version_reply(data):
            break
    print(f"H4 local-version probe: {args.port}, {args.baud}, RTS/CTS={args.flow}")
    print("RX:", data.hex(" ") if data else "no bytes within 3 seconds")
    ok = local_version_reply(data)
    print("PASS: controller replied" if ok else "No verified controller response")
finally:
    termios.tcsetattr(fd, termios.TCSANOW, old)
    os.close(fd)
raise SystemExit(0 if ok else 1)
