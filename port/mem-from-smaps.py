#!/usr/bin/env python3
"""Split the memory of a process into "guest" and "QEMU" parts from a /proc/<pid>/smaps dump.

Under QEMU user emulation, /proc/<pid> shows the qemu-arm host process. On this setup the 32-bit
guest address space is mapped 1:1 below 4 GiB (guest_base = 0). QEMU's own memory (the 128 MiB
translated-code buffer, the qemu-arm binary, its heap) is above 4 GiB. So:

    guest part = mappings that start below 2^32   (what the armv7 program itself uses)
    QEMU part  = mappings that start at or above 2^32   (emulator overhead, not on real hardware)

For a native process (no qemu-arm mapping), all of the memory is the program's own memory.

Usage: mem-from-smaps.py <file.smaps> [...]
"""
import re
import sys

HDR = re.compile(r"^([0-9a-f]+)-([0-9a-f]+) (\S+) \S+ \S+ \S+\s*(.*)$")


def analyse(path):
    maps = []
    cur = None
    for line in open(path, errors="replace"):
        m = HDR.match(line)
        if m:
            cur = {"s": int(m[1], 16), "perm": m[3], "name": m[4].strip(), "Rss": 0, "Pss": 0,
                   "Anonymous": 0, "Private_Dirty": 0}
            maps.append(cur)
        elif cur is not None and ":" in line:
            k, v = line.split(":", 1)
            if k in cur:
                cur[k] = int(v.split()[0])
    emulated = any("qemu" in m["name"] for m in maps)

    def is_guest(m):
        return (not emulated) or m["s"] < 2 ** 32

    def tot(sel, key):
        return sum(m[key] for m in maps if sel(m)) / 1024.0

    g = is_guest
    llvm = lambda m: g(m) and ("libLLVM" in m["name"] or "libgallium" in m["name"])
    print(f"{path}")
    print(f"  emulated by QEMU: {'yes' if emulated else 'no (native)'}; mappings: {len(maps)}")
    print(f"  whole process      Rss {tot(lambda m: True, 'Rss'):7.1f} MiB   Pss {tot(lambda m: True, 'Pss'):7.1f} MiB")
    if emulated:
        print(f"  QEMU part (>=4GiB) Rss {tot(lambda m: not g(m), 'Rss'):7.1f} MiB   Pss {tot(lambda m: not g(m), 'Pss'):7.1f} MiB")
    print(f"  program part       Rss {tot(g, 'Rss'):7.1f} MiB   Pss {tot(g, 'Pss'):7.1f} MiB")
    print(f"    anonymous (heap, stacks, JIT)     {tot(g, 'Anonymous'):7.1f} MiB")
    print(f"    file-backed (code, fonts, caches) {tot(g, 'Rss') - tot(g, 'Anonymous'):7.1f} MiB (Rss)")
    print(f"    of which libLLVM + libgallium     {tot(llvm, 'Rss'):7.1f} MiB (Rss)  <- llvmpipe; a real GPU driver does not touch most of it")
    print(f"    private dirty (cannot be dropped) {tot(g, 'Private_Dirty'):7.1f} MiB")


for p in sys.argv[1:]:
    analyse(p)
