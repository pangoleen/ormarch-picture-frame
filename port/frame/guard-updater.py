#!/usr/bin/env python3
"""Block unsafe upstream install paths on armv7. Safe to run again."""
import pathlib
import sys

omarchy = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path.home() / ".local/share/omarchy"
guard = '# PF1007L guard: no bulk reinstall on armv7\nif [[ $(uname -m) == "armv7l" ]]; then echo "STOP: bulk Omarchy reinstall is not supported on armv7 (see port/frame/armv7-packages.txt)"; exit 1; fi\n'

count = 0
if omarchy.is_dir():
    for name in ("omarchy-pkg-defaults", "omarchy-apply-system", "omarchy-provision-owner"):
        path = omarchy / "bin" / name
        if not path.is_file():
            continue
        text = path.read_text()
        if "PF1007L guard" in text:
            continue
        lines = text.splitlines(keepends=True)
        out = []
        done = False
        for line in lines:
            out.append(line)
            if not done and line.startswith("set "):
                out.append(guard)
                done = True
        if not done:
            out.insert(0, guard)
        backup = path.with_name(path.name + ".before-frame-guard")
        if not backup.exists():
            backup.write_bytes(path.read_bytes())
        path.write_text("".join(out))
        count += 1
        print("Guarded", name)

hook_dir = pathlib.Path("/etc/pacman.d/hooks")
try:
    hook_dir.mkdir(parents=True, exist_ok=True)
except PermissionError:
    print("Skip hook install: need root on the frame")
    print(f"Done. Patched {count} Omarchy helpers.")
    raise SystemExit(0)
hook = hook_dir / "90-pf1007l-guard.hook"
src = pathlib.Path(__file__).with_name("pf-pacman-guard")
dst = pathlib.Path("/usr/lib/pf1007l/pf-pacman-guard")
try:
    if src.is_file() and (not dst.is_file() or dst.read_bytes() != src.read_bytes()):
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
        dst.chmod(0o755)
        print("Installed", dst)
except PermissionError:
    print("Skip guard binary install: need root on the frame")
hook_text = """[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = linux-armv7
Target = linux-armv7-headers
Target = chromium

[Action]
Description = PF1007L guard: block kernel and chromium transactions
When = PreTransaction
Exec = /usr/lib/pf1007l/pf-pacman-guard
AbortOnFail
"""
if hook.read_text() != hook_text if hook.exists() else True:
    hook.write_text(hook_text)
    print("Wrote", hook)
print(f"Done. Patched {count} Omarchy helpers.")
