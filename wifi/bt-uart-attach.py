#!/usr/bin/env python3
"""Supervise H4 UART attachment with the current libc's termios API.

BlueZ 5.87 btattach sets baud bits directly; glibc 2.42+ changed B* values.
This helper uses Python's current termios binding, verified on this frame.
"""
import array
import fcntl
import os
import signal
import termios

port = "/dev/ttyS1"
fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
old = termios.tcgetattr(fd)
ldisc = array.array("i", [0])
fcntl.ioctl(fd, termios.TIOCGETD, ldisc, True)
attached = False
running = True

def stop(signum, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    conf = termios.tcgetattr(fd)
    conf[0] = conf[1] = conf[3] = 0
    conf[2] = termios.CLOCAL | termios.CREAD | termios.CS8 | termios.CRTSCTS
    conf[4] = conf[5] = termios.B1500000
    conf[6][termios.VMIN] = 1
    conf[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, conf)
    termios.tcflush(fd, termios.TCIOFLUSH)
    speed = termios.tcgetattr(fd)
    if speed[4] != termios.B1500000 or speed[5] != termios.B1500000:
        raise RuntimeError("UART did not accept 1,500,000 baud")
    # Linux hci_uart.h ioctl numbers. The driver consumes a scalar argument.
    fcntl.ioctl(fd, termios.TIOCSETD, array.array("i", [15]))  # N_HCI
    attached = True
    fcntl.ioctl(fd, 0x400455cb, 1 << 1)  # HCIUARTSETFLAGS, RESET_ON_INIT
    fcntl.ioctl(fd, 0x400455c8, 0)       # HCIUARTSETPROTO, H4
    index = fcntl.ioctl(fd, 0x800455ca, 0)  # HCIUARTGETDEVICE
    print(f"Attached H4 controller hci{index} on {port} at 1,500,000 baud", flush=True)
    while running:
        signal.pause()
finally:
    if attached:
        fcntl.ioctl(fd, termios.TIOCSETD, ldisc)
    termios.tcsetattr(fd, termios.TCSANOW, old)
    os.close(fd)
