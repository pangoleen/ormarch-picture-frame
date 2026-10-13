#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
"""
Check the PF1007L board DTBs for the project rules. Reads the binary DTB
(own small FDT reader, no dtc necessary). No device access.

  check_dtb.py --variant default  sun8i-a33-pf1007l.dtb
  check_dtb.py --variant uart0-sd sun8i-a33-pf1007l-uart0-sd.dtb

Rules (the script stops with exit code 1 if one fails):
  R1  PL2 (Wi-Fi chip_en) has exactly one GPIO user, a Wi-Fi power node.
      PL3 has no user. No enabled node uses the r_uart pin group (PL2/PL3).
      r_uart is disabled.
  R2  Console: default build has no stdout-path and no serial0 alias.
      uart0-sd build: stdout-path = serial0 = UART0 on PF2/PF4, MMC0 disabled.
  R3  eMMC (mmc2) is disabled (project safety rule 3).
  R4  PB0/PB1 (vendor key pins, possible UART0 pins) have no user.
  R5  CPU: no cpu-supply, DCDC3 fixed at 1.2 V (frequency-only cpufreq).
  R6  The panel node has our compatible first and the driver fallback second.
  R7  Wi-Fi: PL6 is the pwrseq reset GPIO, MMC1 has keep-power-in-suspend,
      the AXP GPIO0 hog is there.
  R8  The DTB has __symbols__ (built with dtc -@, as the stock DTBs are).

This is a check of the FILE. It does not prove that the board works.
"""

import argparse
import struct
import sys

FDT_MAGIC = 0xD00DFEED
BEGIN, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


class Node:
    def __init__(self, name, parent):
        self.name, self.parent, self.props, self.children = name, parent, {}, []

    @property
    def path(self):
        if self.parent is None:
            return "/"
        p = self.parent.path
        return (p if p.endswith("/") else p + "/") + self.name

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()

    def cells(self, prop):
        b = self.props.get(prop, b"")
        return list(struct.unpack(">%dI" % (len(b) // 4), b[:len(b) // 4 * 4]))

    def string(self, prop):
        b = self.props.get(prop)
        return None if b is None else b.split(b"\0")[0].decode()

    def strings(self, prop):
        b = self.props.get(prop, b"")
        return [x.decode() for x in b.split(b"\0") if x]

    def enabled(self):
        n = self
        while n is not None:
            if n.string("status") not in (None, "okay", "ok"):
                return False
            n = n.parent
        return True


def parse(blob):
    magic, total, off_struct, off_strings = struct.unpack(">4I", blob[:16])
    if magic != FDT_MAGIC:
        sys.exit("not a DTB (bad magic)")
    pos, root, cur = off_struct, None, None
    while True:
        (tok,) = struct.unpack(">I", blob[pos:pos + 4])
        pos += 4
        if tok == BEGIN:
            end = blob.index(b"\0", pos)
            node = Node(blob[pos:end].decode(), cur)
            if cur is None:
                root = node
            else:
                cur.children.append(node)
            cur = node
            pos = (end + 4) & ~3
        elif tok == END_NODE:
            cur = cur.parent
        elif tok == PROP:
            ln, nameoff = struct.unpack(">2I", blob[pos:pos + 8])
            pos += 8
            s = off_strings + nameoff
            name = blob[s:blob.index(b"\0", s)].decode()
            cur.props[name] = blob[pos:pos + ln]
            pos = (pos + ln + 3) & ~3
        elif tok == NOP:
            continue
        elif tok == END:
            return root
        else:
            sys.exit(f"bad FDT token {tok} at {pos - 4}")


FAILS = []


def rule(ok, text):
    print(("  PASS  " if ok else "  FAIL  ") + text)
    if not ok:
        FAILS.append(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=["default", "uart0-sd"], required=True)
    ap.add_argument("dtb")
    a = ap.parse_args()
    root = parse(open(a.dtb, "rb").read())
    nodes = list(root.walk())
    by_path = {n.path: n for n in nodes}
    by_phandle = {n.cells("phandle")[0]: n for n in nodes if "phandle" in n.props}

    def find(pred, what):
        hit = [n for n in nodes if pred(n)]
        if len(hit) != 1:
            sys.exit(f"{what}: expected one node, found {[n.path for n in hit]}")
        return hit[0]

    def unit(name):
        return lambda n: n.name == name

    r_pio = find(unit("pinctrl@1f02c00"), "r_pio")
    pio = find(unit("pinctrl@1c20800"), "pio")
    r_uart = find(unit("serial@1f02800"), "r_uart")
    uart0 = find(unit("serial@1c28000"), "uart0")
    mmc0 = find(unit("mmc@1c0f000"), "mmc0")
    mmc1 = find(unit("mmc@1c10000"), "mmc1")
    mmc2 = find(unit("mmc@1c11000"), "mmc2")
    ph = lambda n: n.cells("phandle")[0]

    # GPIO users: every property that holds <&ctrl bank pin flags> for sunxi
    # pin controllers (#gpio-cells = 3). Scan all properties for the pattern.
    def gpio_users(ctrl):
        users = []
        for n in nodes:
            for prop, raw in n.props.items():
                if not (prop.endswith("-gpios") or prop.endswith("-gpio") or prop in ("gpios", "gpio")):
                    continue
                c = n.cells(prop)
                i = 0
                while i < len(c):
                    target = by_phandle.get(c[i])
                    ncell = target.cells("#gpio-cells")[0] if target and "#gpio-cells" in target.props else 0
                    if target is ctrl:
                        users.append((n, prop, c[i + 1], c[i + 2], c[i + 3]))
                    i += 1 + ncell
        return users

    def pin_groups(ctrl, pins):
        return [n for n in ctrl.children if set(n.strings("pins")) & set(pins)]

    def group_users(group):
        g = ph(group) if "phandle" in group.props else None
        out = []
        for n in nodes:
            for prop in n.props:
                if prop.startswith("pinctrl-") and prop != "pinctrl-names" and g in n.cells(prop):
                    out.append(n)
        return out

    print(f"{a.dtb} (variant {a.variant})")

    # ---- R1 ------------------------------------------------------------------
    rpio_users = gpio_users(r_pio)
    for n, prop, bank, pin, flags in rpio_users:
        print(f"        r_pio user: PL{pin} flags={flags} <- {n.path} : {prop} (enabled={n.enabled()})")
    pl2 = [u for u in rpio_users if u[3] == 2]
    pl3 = [u for u in rpio_users if u[3] == 3]
    rule(len(pl2) == 1 and pl2[0][0].name in ("regulator-wifi-chip-en", "pwrseq"),
         f"R1 PL2 has one GPIO user, a Wi-Fi power node: {[u[0].path for u in pl2]}")
    rule(not pl3, f"R1 PL3 has no GPIO user: {[u[0].path for u in pl3]}")
    bad = []
    for g in pin_groups(r_pio, ["PL2", "PL3"]):
        bad += [(g.name, n.path) for n in group_users(g) if n.enabled()]
    rule(not bad, f"R1 no enabled node uses a pin group with PL2/PL3: {bad}")
    rule(r_uart.string("status") == "disabled" and "pinctrl-0" not in r_uart.props,
         f"R1 r_uart is disabled and has no pinctrl-0 (status={r_uart.string('status')})")

    # ---- R2 ------------------------------------------------------------------
    chosen, aliases = by_path.get("/chosen"), by_path.get("/aliases")
    stdout = chosen.string("stdout-path") if chosen else None
    serial0 = aliases.string("serial0") if aliases else None
    pf_group = [g for g in pin_groups(pio, ["PF2", "PF4"]) if g.string("function") == "uart0"]
    if a.variant == "default":
        rule(stdout is None, f"R2 no stdout-path (found: {stdout})")
        rule(serial0 is None, f"R2 no serial0 alias (found: {serial0})")
        rule(not uart0.enabled(), "R2 uart0 is disabled")
        rule(mmc0.enabled(), "R2 mmc0 (MicroSD) is enabled")
        en = [n.path for n in nodes if n.name.startswith("serial@") and n.enabled()]
        rule(not en, f"R2 no UART is enabled: {en}")
    else:
        rule(stdout == "serial0:115200n8", f"R2 stdout-path = serial0:115200n8 (found: {stdout})")
        rule(serial0 == uart0.path, f"R2 serial0 = {uart0.path} (found: {serial0})")
        rule(uart0.enabled() and pf_group and ph(pf_group[0]) in uart0.cells("pinctrl-0"),
             "R2 uart0 is enabled on the PF2/PF4 pin group")
        rule(not mmc0.enabled(), "R2 mmc0 (MicroSD, same pins) is disabled")

    # ---- R3 ------------------------------------------------------------------
    rule(mmc2.string("status") == "disabled", f"R3 mmc2 (eMMC) status = {mmc2.string('status')}")

    # ---- R4 ------------------------------------------------------------------
    pb = [u for u in gpio_users(pio) if u[2] == 1 and u[3] in (0, 1)]
    pbg = []
    for g in pin_groups(pio, ["PB0", "PB1"]):
        pbg += [(g.name, n.path) for n in group_users(g) if n.enabled()]
    rule(not pb and not pbg, f"R4 PB0/PB1 have no user: gpio={[u[0].path for u in pb]} pinctrl={pbg}")

    # ---- R5 ------------------------------------------------------------------
    cpu0 = by_path["/cpus/cpu@0"]
    dcdc3 = find(lambda n: n.name == "dcdc3", "dcdc3")
    dcdc2 = find(lambda n: n.name == "dcdc2", "dcdc2")
    supplies = [p for n in nodes if n.name.startswith("cpu@") for p in n.props if p.endswith("-supply")]
    rule(not supplies, f"R5 no cpu-supply on a CPU node: {supplies}")
    for r in (dcdc2, dcdc3):
        lo, hi = r.cells("regulator-min-microvolt")[0], r.cells("regulator-max-microvolt")[0]
        rule(lo == hi == 1200000 and "regulator-always-on" in r.props,
             f"R5 {r.name} fixed at 1.2 V, always-on (min {lo}, max {hi})")
    rule("operating-points-v2" in cpu0.props, "R5 cpu0 has an OPP table (frequency scaling)")

    # ---- R6 ------------------------------------------------------------------
    panel = find(lambda n: n.name == "panel@0", "panel")
    rule(panel.strings("compatible") == ["yhk,zr789-sq9365-101", "jadard,jd9365da-h3"],
         f"R6 panel compatible = {panel.strings('compatible')}")
    rule(panel.enabled() and panel.parent.name == "dsi@1ca0000", "R6 panel is an enabled child of dsi@1ca0000")

    # ---- R7 ------------------------------------------------------------------
    pwrseq = by_path.get("/pwrseq")
    pl6 = [u for u in rpio_users if u[3] == 6]
    rule(len(pl6) == 1 and pl6[0][0] is pwrseq and pl6[0][4] & 1 == 1,
         "R7 PL6 is the pwrseq reset GPIO, active low (= enable, active high)")
    rule("keep-power-in-suspend" in mmc1.props and "non-removable" in mmc1.props and mmc1.enabled(),
         "R7 mmc1 is enabled, non-removable, keep-power-in-suspend")
    hog = [n for n in nodes if "gpio-hog" in n.props]
    axp_hog = [h for h in hog if h.parent.string("compatible") == "x-powers,axp221-gpio"]
    rule(len(axp_hog) == 1 and axp_hog[0].cells("gpios")[0] == 0
         and "output-high" in axp_hog[0].props,
         f"R7 AXP GPIO0 hog, output high: {[h.path for h in hog]}")
    amp_hog = [h for h in hog if h.name == "speaker-amp-hog"]
    rule(all(h.cells("gpios")[:2] == [7, 9] and "output-high" in h.props for h in amp_hog),
         f"R7 speaker-amp hog is PH09 output-high only: {[h.path for h in amp_hog]}")
    chip_en = by_path.get("/regulator-wifi-chip-en")
    if chip_en is not None:
        d = chip_en.cells("startup-delay-us")[0]
        rule(d >= 125000 and ph(chip_en) in mmc1.cells("vmmc-supply"),
             f"R7 PL2 regulator is the mmc1 vmmc supply, start-up delay {d} us (>= 125 ms and >= 5 ms)")

    # ---- R8 ------------------------------------------------------------------
    rule("/__symbols__" in by_path, "R8 __symbols__ is present (dtc -@)")

    if FAILS:
        print(f"RESULT: {len(FAILS)} rule(s) FAILED")
        sys.exit(1)
    print("RESULT: all rules pass")


if __name__ == "__main__":
    main()
