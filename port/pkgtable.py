#!/usr/bin/env python3
"""Join the Omarchy v4.0.4 package lists against pacman sync databases. Reads only; writes one TSV.

Usage:
  pkgtable.py <omarchy_repo> <omarchy_pkgs_repo> <dbs_armv7h_dir> <dbs_other_dir> <resolve_file> <out_tsv>

Input files (the names are fixed):
  <dbs_armv7h_dir>/alarm-armv7h-{core,extra,alarm,aur}.db
      copies of /var/lib/pacman/sync/*.db from the armv7h container (after `pacman -Sy`)
  <dbs_other_dir>/arch-{core,extra}.db
      https://geo.mirror.pkgbuild.com/<repo>/os/x86_64/<repo>.db
  <dbs_other_dir>/alarm-aarch64-{core,extra,alarm,aur}.db
      http://mirror.archlinuxarm.org/aarch64/<repo>/<repo>.db   (use curl -L)
  <dbs_other_dir>/omarchy-stable-x86_64.tar, omarchy-edge-aarch64.tar
      https://pkgs.omarchy.org/stable/x86_64/omarchy.db and .../edge/aarch64/omarchy.db,
      which are zstd files: unpack with `zstd -d omarchy.db -o <name>.tar`
  <resolve_file>
      one line per package, "<name> OK|FAIL ...", from `pacman -S --print <name>` in the armv7h
      container (see port/logs/resolve-armv7h.txt)

"vercmp" is not needed. The "older" status compares only major.minor of the upstream version.
"""
import datetime
import io
import os
import re
import sys
import tarfile

omarchy, omapkgs, d7, dother, resolvefile, out = sys.argv[1:7]
resolved = {}
for line in open(resolvefile):
    parts = line.split()
    if len(parts) >= 2:
        resolved[parts[0]] = parts[1]


def load(path):
    """Return {name: {version, builddate, provides:[...], arch, isize}} for one sync db."""
    res = {}
    if path.endswith(".tar"):
        tf = tarfile.open(path, "r:")
    else:
        tf = tarfile.open(path, "r:*")
    for m in tf:
        if not m.isfile() or not m.name.endswith("/desc"):
            continue
        txt = tf.extractfile(m).read().decode("utf-8", "replace")
        f = {}
        key = None
        for line in txt.splitlines():
            if line.startswith("%") and line.endswith("%"):
                key = line.strip("%")
                f[key] = []
            elif line and key:
                f[key].append(line)
        if "NAME" not in f:
            print("WARN: desc without NAME:", path, m.name, len(txt), file=sys.stderr)
            continue
        name = f["NAME"][0]
        res[name] = {
            "version": f["VERSION"][0],
            "builddate": int(f.get("BUILDDATE", ["0"])[0]),
            "provides": [re.split(r"[<>=]", p)[0] for p in f.get("PROVIDES", [])],
            "arch": f.get("ARCH", ["?"])[0],
            "isize": int(f.get("ISIZE", ["0"])[0]),
            "depends": f.get("DEPENDS", []),
        }
    return res


def loadset(d, prefix, repos):
    s = {}
    for r in repos:
        for ext in (".db", ".tar"):
            p = os.path.join(d, f"{prefix}{r}{ext}")
            if os.path.exists(p) and (ext == ".tar" or not os.path.exists(p[:-3] + ".tar")):
                try:
                    s[r] = load(p)
                except tarfile.ReadError:
                    pass
    return s


armv7 = loadset(d7, "alarm-armv7h-", ["core", "extra", "alarm", "aur"])
aarch = loadset(dother, "alarm-aarch64-", ["core", "extra", "alarm", "aur"])
arch = loadset(dother, "arch-", ["core", "extra"])
oma_x86 = load(os.path.join(dother, "omarchy-stable-x86_64.tar"))
oma_a64 = load(os.path.join(dother, "omarchy-edge-aarch64.tar"))


def find(dbs, name):
    for repo, db in dbs.items():
        if name in db:
            return repo, db[name], ""
    for repo, db in dbs.items():
        for n, p in db.items():
            if name in p["provides"]:
                return repo, p, n
    return None, None, ""


def readlist(path):
    names = []
    for line in open(path):
        line = line.split("#")[0].strip()
        if line:
            names.append(line)
    return names


base = readlist(os.path.join(omarchy, "install/omarchy-base.packages"))
other = readlist(os.path.join(omarchy, "install/omarchy-other.packages"))

hard = ("omarchy-keyring omarchy-settings hyprland quickshell uwsm sddm xdg-desktop-portal-hyprland "
        "wireplumber pipewire gnome-keyring gum jq git perl fakeroot pacman-contrib "
        "ttf-jetbrains-mono-nerd-basic networkmanager omarchy").split()
settings = "bash curl gum hicolor-icon-theme plymouth".split()
qs_deps = ("cpptrace glibc hicolor-icon-theme jemalloc libdrm libglvnd libpipewire libxcb mesa pam polkit "
           "qt6-base qt6-declarative qt6-svg qt6-wayland wayland").split()
extra_frame = ("firefox neovim wvkbd hyprgrass squeekboard kmscube aquamarine hyprlock hypridle "
               "qt6-5compat qt6-multimedia cage weston wayvnc").split()

# Minimum versions that Omarchy states. Source in the note column.
minver = {
    "omarchy-settings": ("=4.0.4", "omarchy PKGBUILD depends"),
    "neovim": (">=0.9.0", "omarchy-nvim PKGBUILD depends (LazyVim itself needs more, see smoke-test.md)"),
    "nvim": (">=0.9.0", "omarchy-nvim PKGBUILD depends on neovim>=0.9.0"),
    "hyprland": (">=0.55 (Lua config); Omarchy ships 0.56.2", "config/hypr/hyprland.lua; omarchy-hyprland-titlebars pins =0.56.2"),
    "quickshell": ("0.3.2 + Omarchy patch (pkgrel 4)", "omarchy-pkgs pkgbuilds/quickshell"),
}


X86_HW = set("""asusctl broadcom-wl-dkms intel-ipu7-camera intel-lpmd intel-media-driver libva-intel-driver
libva-nvidia-driver limine limine-mkinitcpio-hook limine-snapper-sync linux-omarchy linux-omarchy-headers
macbook12-spi-driver-dkms nvidia-580xx-dkms nvidia-dkms nvidia-open-dkms nvidia-580xx-utils nvidia-utils
lib32-nvidia-580xx-utils lib32-nvidia-utils thermald yay-debug tuxedo-drivers-nocompatcheck-dkms yt6801-dkms
vpl-gpu-rt libvpl dell-xps-touchpad-haptics apple-bcm-firmware apple-t2-audio-config linux-t2 linux-t2-headers
t2fanrd qmk-hid vulkan-intel vulkan-radeon vulkan-asahi linux-firmware-marvell sof-firmware snapper btrfs-progs
egl-wayland dkms asdcontrol""".split())

TOO_OLD = {"neovim"}

ACTION = {
    "omarchy": "build ourselves (Omarchy PKGBUILD, add armv7h)",
    "omarchy-settings": "build ourselves (Omarchy PKGBUILD, add armv7h)",
    "omarchy-keyring": "build ourselves (arch=any)",
    "ttf-jetbrains-mono-nerd-basic": "replace with ttf-jetbrains-mono-nerd (in extra), or build (arch=any)",
    "yaru-icon-theme": "build ourselves (arch=any)",
    "ttf-ia-writer": "build ourselves (arch=any) or drop",
    "chromium": "replace with firefox (extra 157.0-1, installable)",
    "nvim": "use the name neovim; see neovim",
    "neovim": "build neovim >= 0.11.2 ourselves, or drop omarchy-nvim and use helix/vim/micro",
    "omarchy-nvim": "drop until neovim >= 0.11.2 exists on armv7h",
    "mise-bin": "build ourselves (wrap the upstream linux-armv7 binary) or drop",
    "yay": "build ourselves (Go; the AUR PKGBUILD lists armv7h) or drop",
    "ufw-docker": "drop with docker",
    "hyprland-preview-share-picker": "drop (and remove its line in config/hypr/xdph.conf)",
    "aether": "drop", "cliamp": "drop", "herdr": "drop", "localsend": "drop", "obsidian": "drop",
    "obs-studio": "drop", "pinta": "drop", "dotnet-runtime": "drop (only pinta needs it)",
    "qemu-user-static-binfmt": "drop", "tobi-try": "drop", "tensaku": "drop or build later (Rust)",
    "omacalc": "optional: build ourselves (Qt6 C++)", "omawrite": "optional: build ourselves (Qt6 C++)",
    "omacut": "drop", "ttfx": "optional: build ourselves (Rust); screensaver only",
    "tzupdate": "optional: build ourselves (Rust)",
    "kdenlive": "drop (also not installable)",
    "wvkbd": "build ourselves (C, AUR lists armv7h); or use squeekboard from extra",
    "hyprgrass": "build ourselves against the exact hyprland package",
    "kmscube": "build ourselves (GPU test tool), or use mesa-utils/glmark2 from extra",
    "squeekboard": "candidate on-screen keyboard (in extra)",
    "docker": "drop on the frame", "docker-buildx": "drop on the frame", "docker-compose": "drop on the frame",
    "libreoffice-fresh": "drop on the frame", "sddm": "keep, or replace with getty autologin + uwsm",
    "quickshell": "keep the ALARM package; with Omarchy > v4.0.4 it works without the Omarchy patch",
    "hyprland": "keep (GPU question is separate: needs GLES 3.0)",
}

NOTE = {
    "neovim": "built 2023-06-04; depends on libtermkey, which no armv7h repo has; LazyVim main needs Neovim >= 0.11.2",
    "kdenlive": "built 2024-02-15; depends on kfilemetadata5 and purpose5, which no armv7h repo has",
    "quickshell": "same version and pkgrel as Arch x86_64 and ALARM aarch64; Omarchy's own build is 0.3.2-4 with load_qtquick_611.patch",
    "chromium": "ALARM builds chromium for aarch64 only (PKGBUILD buildarch=8)",
    "squeekboard": "research/04 said aarch64 only; it is in armv7h extra",
    "plymouth": "research/04 was not sure; it is in armv7h extra",
    "hyprlock": "research/04 found no armv7h page; it is in armv7h extra (Omarchy 4 does not use it)",
    "hypridle": "research/04 found no armv7h page; it is in armv7h extra (Omarchy 4 does not use it)",
}

rows = []
seen = set()




def date(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.UTC).strftime("%Y-%m-%d") if ts else ""


def add(name, source):
    if name in seen:
        return
    seen.add(name)
    repo, p, via = find(armv7, name)
    arepo, ap, avia = find(arch, name)
    a64repo, a64p, a64via = find(aarch, name)
    ox = oma_x86.get(name)
    oa = oma_a64.get(name)
    req, reqsrc = minver.get(name, ("", ""))
    pkgbuild = os.path.exists(os.path.join(omapkgs, "pkgbuilds", name, "PKGBUILD"))
    hw = name in X86_HW
    if p:
        ref = ox["version"] if ox else (ap["version"] if ap else "")
        note = f"provided by {via}" if via else ""

        def up(v):
            return v.split(":")[-1].rsplit("-", 1)[0]

        status = "fine"
        if ref and up(p["version"]) != up(ref):
            na = [int(x) for x in re.findall(r"\d+", up(p["version"]))[:2]]
            nb = [int(x) for x in re.findall(r"\d+", up(ref))[:2]]
            if na < nb:
                status = "older"
        if resolved.get(via or name) == "FAIL" or resolved.get(name) == "FAIL":
            status = "broken"
        if name in TOO_OLD:
            status = "too-old+broken" if status == "broken" else "too-old"
    else:
        note = ""
        if hw:
            status = "n/a (x86 or other hardware)"
        elif ap and not (ox or oa):
            status = "missing (Arch x86_64 has it, ALARM armv7h does not)"
        elif ap and (ox or oa or pkgbuild):
            status = "missing (Arch x86_64 and Omarchy repo have it, ALARM armv7h does not)"
        elif ox or oa or pkgbuild:
            status = "missing (Omarchy-built package, no armv7h build)"
        else:
            status = "missing (not in any repo read; AUR or source only)"
    action = ACTION.get(name, "")
    if not action:
        action = "drop (not for this hardware)" if hw else ("keep" if p and status in ("fine", "older") else "decide")
    installable = resolved.get(name, "") if p else ""
    rows.append([
        name, source, req,
        repo or "-", p["version"] if p else "-", date(p["builddate"]) if p else "",
        f"{p['isize'] / 1048576:.1f}" if p else "",
        (arepo + " " + ap["version"]) if ap else "-",
        (a64repo + " " + a64p["version"]) if a64p else "-",
        ox["version"] if ox else "-",
        oa["version"] if oa else "-",
        "yes" if pkgbuild else "no",
        installable, status, action, "; ".join(x for x in (note, reqsrc, NOTE.get(name, "")) if x),
    ])


for n in base:
    add(n, "base")
for n in hard:
    add(n, "omarchy-dep")
for n in settings:
    add(n, "omarchy-settings-dep")
for n in qs_deps:
    add(n, "quickshell-dep")
for n in other:
    add(n, "other(ISO cache)")
for n in extra_frame:
    add(n, "frame-extra")

hdr = ["name", "list", "omarchy_required_version", "armv7h_repo", "armv7h_version", "armv7h_builddate",
       "armv7h_installed_MiB", "arch_x86_64", "alarm_aarch64", "omarchy_repo_x86_64_stable",
       "omarchy_repo_aarch64_edge", "omarchy_pkgbuild", "armv7h_deps_resolve", "status", "action", "note"]
with open(out, "w") as fh:
    fh.write("\t".join(hdr) + "\n")
    for r in rows:
        fh.write("\t".join(r) + "\n")

from collections import Counter
c = Counter((r[1], r[13].split(" (")[0]) for r in rows)
for k in sorted(c):
    print(k, c[k])
print("total", len(rows))
