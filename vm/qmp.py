#!/usr/bin/env python3
"""Small QMP client for the test VM (host side, standard library only).

  qmp.py SOCK screendump FILE.png     save the guest screen as PNG
  qmp.py SOCK key meta_l-ret          press a key chord (QEMU key names, '-' joins keys)
  qmp.py SOCK type 'text'             type plain text (a-z, 0-9, space, a few signs)
  qmp.py SOCK click X Y               absolute pointer click (needs a tablet device), X Y in screen pixels
  qmp.py SOCK raw '{"execute": ...}'  send one raw command, print the answer
  qmp.py SOCK quit                    stop QEMU
"""
import json
import socket
import sys
import time


class Qmp:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(path)
        self.f = self.s.makefile("rw")
        json.loads(self.f.readline())  # greeting
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        msg = {"execute": name}
        if args:
            msg["arguments"] = args
        self.f.write(json.dumps(msg) + "\n")
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                raise SystemExit("QMP closed")
            ans = json.loads(line)
            if "event" in ans:
                continue
            if "error" in ans:
                raise SystemExit(f"QMP error: {ans['error']}")
            return ans.get("return")


CHARS = {" ": "spc", "-": "minus", ".": "dot", "/": "slash", ",": "comma", "=": "equal", "\n": "ret", ";": "semicolon"}


def keys(q, chord, hold=80):
    q.cmd("send-key", keys=[{"type": "qcode", "data": k} for k in chord.split("-")], **{"hold-time": hold})


def main():
    sock, action, *rest = sys.argv[1:]
    q = Qmp(sock)
    if action == "screendump":
        q.cmd("screendump", filename=rest[0], format="png")
    elif action == "key":
        for chord in rest:
            keys(q, chord)
            time.sleep(0.3)
    elif action == "type":
        for ch in rest[0]:
            if ch.isupper():
                keys(q, "shift-" + ch.lower())
            else:
                keys(q, CHARS.get(ch, ch))
            time.sleep(0.15)
    elif action == "click":
        x, y, w, h = int(rest[0]), int(rest[1]), 1280, 800
        ev = [{"type": "abs", "data": {"axis": "x", "value": x * 32767 // w}},
              {"type": "abs", "data": {"axis": "y", "value": y * 32767 // h}}]
        q.cmd("input-send-event", events=ev)
        time.sleep(0.3)
        for down in (True, False):
            q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
            time.sleep(0.2)
    elif action == "raw":
        print(json.dumps(q.cmd(**{"name": json.loads(rest[0])["execute"], **json.loads(rest[0]).get("arguments", {})})))
    elif action == "quit":
        try:
            q.cmd("quit")
        except SystemExit:
            pass
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
