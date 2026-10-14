#!/usr/bin/env python3
"""
extract-bun-js.py — Extrait le JavaScript lisible (et les assets embarques) d'un
binaire Claude Code compile par Bun (`bun build --compile`).

- Version-agnostique : marche sur 2.1.113 jusqu'a la derniere. Ne PAS confondre
  avec la 2.1.112 npm qui est deja du cli.js pur (rien a extraire).
- Multi-plateforme : macOS (section Mach-O __BUN,__bun), Linux (blob appendu a
  l'ELF), Windows (section PE .bun). On ne parse AUCUN format executable : le blob
  Bun est contigu et se termine par sa propre structure de fin, ca suffit.
- Zero dependance externe (stdlib seule) : tourne aussi sur armv7l.

Deux strategies, dans l'ordre :

1. TABLE DES MODULES (obligatoire depuis la 2.1.242). Un binaire Bun standalone se
   termine par une structure `Offsets` (32 octets : byte_count u64, modules
   StringPointer{offset u32, length u32}, entry_point_id u32, 3 mots) puis le trailer
   "\\n---- Bun! ----\\n". Le debut du blob = position de Offsets - byte_count. Chaque
   enregistrement de la table (52 octets) contient des StringPointer relatifs au blob :
   nom virtuel (/$bunfs/root/...), contenu, sourcemap, bytecode, un petit bloc, chemin
   source, puis un mot de flags dont l'octet 1 est le loader Bun (1 = js).
   Depuis la 2.1.242 le bundle n'est plus un monolithe de ~28 Mo mais ~1 640 chunks ESM
   (`chunk-xxxxxxxx.js`, la plupart < 100 Ko) qui s'importent entre eux, plus ~170
   assets (SKILL/README .md.zst, .node natifs...). Un decoupage par « gros blocs de
   texte » n'en voit que ~46 sur 1 640 : d'ou la lecture de la table.

2. CARVE (repli : --carve, ou table illisible = format Bun inconnu). Decoupe lineaire
   des grands blocs de texte imprimable, comme l'ancien script (mais en O(n) : la
   regex `{N,}` de l'ancienne version etait quadratique sur les binaires a chunks,
   5 min au lieu de 4 s).

Sortie (dossier -o) :
  claude-<ver>.cli.js         concatenation de TOUS les modules JS dans l'ordre de la
                              table (1 module = 1 en-tete `// >>> <nom court>`), pour
                              grep / audit / strdiff — PAS executable tel quel. Sur un
                              monolithe (<= 2.1.241) c'est le bundle brut, comme avant.
  claude-<ver>.manifest.json  point d'entree, disposition detectee, liste des modules
                              (nom, source, taille, flags, kind, sha256), totaux.
  bunfs/root/...              miroir exact du systeme de fichiers virtuel Bun : chaque
                              module et asset sous son nom ; les .zst sont aussi
                              decompresses a cote (Python >= 3.14 ou module zstandard).
  block_NNN.js                repli carve uniquement (ancien format de sortie).

Le JS extrait est IDENTIQUE quelle que soit la plateforme du binaire source (seuls les
.node natifs different) : extraire sur une grosse machine, utiliser le resultat partout.
Extraire pour soi = ok ; redistribuer le code compile d'Anthropic = probable conflit
avec leurs CGU. Usage a la discretion de l'utilisateur.
"""
import argparse
import glob
import hashlib
import json
import mmap
import os
import re
import shutil
import struct
import sys

TRAILER = b"\n---- Bun! ----\n"
VFS_PREFIX = b"/$bunfs/"
# (taille de la structure Offsets, position de byte_count dans celle-ci)
OFFSETS_LAYOUTS = ((32, 0), (40, 0), (40, 8), (48, 0), (48, 8))
RECORD_STRIDES = (52, 40, 44, 48, 56, 60, 64)
MODULE_LOADERS = {0, 1, 2, 3}  # bun.options.Loader : jsx, js, ts, tsx
MODULE_EXTS = (".js", ".mjs", ".cjs")
VERSION_RE = re.compile(rb"// Version: (\d+\.\d+\.\d+)")
PRINTABLE_RUN = re.compile(rb"[\t\n\r\x20-\x7e]+")
SANITY_NEEDLES = (b"Claude Code", b"anthropic", b"You are Claude")
HEADER = b"// >>> %s\n"


# ----------------------------------------------------------------- binaire
def find_claude_binary():
    """Auto-detecte le binaire natif Claude Code installe (le plus recent)."""
    home = os.path.expanduser("~")
    candidates = []

    which = shutil.which("claude")
    if which:
        candidates.append(os.path.realpath(which))

    # Versions telechargees par l'auto-updater natif.
    vers = os.path.join(home, ".local", "share", "claude", "versions")
    if os.path.isdir(vers):
        for v in sorted(os.listdir(vers), key=_semver_key, reverse=True):
            candidates.append(os.path.join(vers, v))

    # Extension VS Code (embarque son propre binaire).
    for ext in sorted(
        glob.glob(os.path.join(home, ".vscode*", "extensions", "anthropic.claude-code-*")),
        reverse=True,
    ):
        candidates.append(os.path.join(ext, "resources", "native-binary", "claude"))

    # Packages optionalDependencies natifs dans les node_modules globaux.
    for root in _npm_global_roots():
        base = os.path.join(root, "@anthropic-ai", "claude-code")
        candidates.append(os.path.join(base, "bin", "claude.exe"))
        nm = os.path.join(base, "node_modules", "@anthropic-ai")
        if os.path.isdir(nm):
            for name in os.listdir(nm):
                if name.startswith("claude-code-") and name != "claude-code":
                    candidates.append(os.path.join(nm, name, "claude"))

    # Pad armv7l : binaire pose par install-claude-native-armv7.sh.
    candidates.append("/opt/claude-native/claude")

    seen = set()
    for c in candidates:
        if c in seen:
            continue
        seen.add(c)
        try:
            # > 40 Mo : ecarte les wrappers shell/JS qui s'appellent aussi `claude`.
            if os.path.isfile(c) and os.path.getsize(c) > 40 * 1024 * 1024:
                return c
        except OSError:
            pass
    return None


def _semver_key(v):
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", v)
    return tuple(int(x) for x in m.groups()) if m else (-1, -1, -1)


def _npm_global_roots():
    roots = []
    npm = shutil.which("npm")
    if npm:
        try:
            import subprocess

            out = subprocess.run(
                [npm, "root", "-g"], capture_output=True, text=True, timeout=15
            )
            if out.returncode == 0 and out.stdout.strip():
                roots.append(out.stdout.strip())
        except Exception:
            pass
    home = os.path.expanduser("~")
    nvm = os.path.join(home, ".nvm", "versions", "node")
    if os.path.isdir(nvm):
        for v in os.listdir(nvm):
            roots.append(os.path.join(nvm, v, "lib", "node_modules"))
    roots += [
        "/usr/local/lib/node_modules",
        "/usr/lib/node_modules",
        "/opt/homebrew/lib/node_modules",
        os.path.join(home, ".local", "lib", "node_modules"),
    ]
    return [r for r in roots if os.path.isdir(r)]


def detect_version(binary_path, bundle):
    """Best-effort quand le bundle ne porte pas de `// Version: x.y.z`."""
    d = os.path.dirname(os.path.abspath(binary_path))
    for _ in range(6):
        pj = os.path.join(d, "package.json")
        try:
            with open(pj, "r", encoding="utf-8", errors="ignore") as f:
                data = json.load(f)
            if data.get("name") == "@anthropic-ai/claude-code" and data.get("version"):
                return data["version"]
        except Exception:
            pass
        nd = os.path.dirname(d)
        if nd == d:
            break
        d = nd
    m = re.search(rb'claude-code"[^0-9]{0,40}?(\d+\.\d+\.\d+)', bundle[:2_000_000])
    if m:
        return m.group(1).decode()
    m = re.search(rb'"version"\s*:\s*"(\d+\.\d+\.\d+)"', bundle[:2_000_000])
    if m:
        return m.group(1).decode()
    return "unknown"


# ------------------------------------------------------- table des modules
def parse_module_graph(mm, trailer_pos):
    """Retourne la graphe de modules Bun ou None si la disposition est inconnue."""
    for size, bc_pos in OFFSETS_LAYOUTS:
        if trailer_pos - size < 0:
            continue
        hdr = mm[trailer_pos - size : trailer_pos]
        byte_count = struct.unpack_from("<Q", hdr, bc_pos)[0]
        mod_off, mod_len, entry = struct.unpack_from("<III", hdr, bc_pos + 8)
        base = trailer_pos - size - byte_count
        if base < 0 or mod_len == 0 or mod_off + mod_len > byte_count:
            continue
        for stride in RECORD_STRIDES:
            if mod_len % stride:
                continue
            count = mod_len // stride
            if entry >= count:
                continue
            modules = _read_records(mm, base, mod_off, count, stride, byte_count)
            if modules is None:
                continue
            return {
                "base": base,
                "byte_count": byte_count,
                "entry": entry,
                "offsets_size": size,
                "record_stride": stride,
                "modules": modules,
            }
    return None


def _read_records(mm, base, mod_off, count, stride, byte_count):
    def sp(rec, pos):
        o, l = struct.unpack_from("<II", rec, pos)
        return (o, l) if o + l <= byte_count else None

    def data(ptr):
        return mm[base + ptr[0] : base + ptr[0] + ptr[1]]

    records = [mm[base + mod_off + i * stride : base + mod_off + (i + 1) * stride] for i in range(count)]

    names = []
    for rec in records:
        p = sp(rec, 0)
        names.append(data(p) if p and 0 < p[1] < 4096 else None)
    valid = sum(1 for n in names if n and n.startswith(VFS_PREFIX))
    if valid < max(1, int(count * 0.99)):
        return None

    if stride == 52:
        # Disposition verifiee (Bun 1.3, Claude Code 2.1.25x) :
        # name(0) contents(8) sourcemap(16) bytecode(24) extra(32) source(40) flags(48)
        c_pos, sm_pos, bc_pos, src_pos, fl_pos = 8, 16, 24, 40, 48
    else:
        # Disposition inconnue : le contenu est le StringPointer a 8 ou 12 qui tient
        # dans le blob pour tous les enregistrements ; le reste n'est pas interprete.
        c_pos = None
        for cand in (8, 12):
            if all(sp(r, cand) is not None for r in records):
                c_pos = cand
                break
        if c_pos is None:
            return None
        sm_pos = bc_pos = src_pos = fl_pos = None

    modules = []
    for i, rec in enumerate(records):
        name = names[i]
        contents = sp(rec, c_pos)
        if name is None or contents is None:
            return None
        flags = struct.unpack_from("<I", rec, fl_pos)[0] if fl_pos is not None else None
        source = data(sp(rec, src_pos) or (0, 0)) if src_pos is not None else name
        bytecode = sp(rec, bc_pos) if bc_pos is not None else (0, 0)
        modules.append(
            {
                "index": i,
                "name": name,
                "source": source or name,
                "contents": contents,
                "bytecode_size": bytecode[1] if bytecode else 0,
                "flags": flags,
                "kind": _kind(name, flags, mm, base, contents),
            }
        )
    return modules


def _kind(name, flags, mm, base, contents):
    """'module' = source JS/TS a bundler ; 'asset' = fichier servi tel quel."""
    if flags is not None:
        return "module" if ((flags >> 8) & 0xFF) in MODULE_LOADERS else "asset"
    short = name.rsplit(b"/", 1)[-1]
    if short.endswith(MODULE_EXTS):
        return "module"
    if b"." not in short:
        head = mm[base + contents[0] : base + contents[0] + 40]
        if head.startswith(b"// @bun") or head.startswith(b"(function"):
            return "module"
    return "asset"


def vfs_relpath(name):
    """b'/$bunfs/root/chunk-x.js' -> 'root/chunk-x.js' (None si suspect)."""
    if not name.startswith(VFS_PREFIX):
        return None
    parts = [p for p in name[len(VFS_PREFIX) :].decode("utf-8", "replace").split("/") if p and p != "."]
    if not parts or any(p == ".." for p in parts):
        return None
    return "/".join(parts)


def _zstd_decompress():
    try:
        from compression import zstd  # Python >= 3.14

        return zstd.decompress
    except Exception:
        pass
    try:
        import zstandard

        return zstandard.ZstdDecompressor().decompress
    except Exception:
        return None


def extract_graph(mm, graph, binary, out, label):
    base = graph["base"]
    modules = graph["modules"]

    def data(m):
        o, l = m["contents"]
        return mm[base + o : base + o + l]

    entry = modules[graph["entry"]]
    js_modules = [m for m in modules if m["kind"] == "module"]

    # Version : le bandeau `// Version: x.y.z` du point d'entree, sinon n'importe quel module.
    ver = label
    if not ver:
        for m in [entry] + js_modules:
            hit = VERSION_RE.search(data(m)[:4096])
            if hit:
                ver = hit.group(1).decode()
                break
    if not ver:
        ver = detect_version(binary, data(js_modules[0]) if js_modules else b"")

    os.makedirs(out, exist_ok=True)
    decompress = _zstd_decompress()
    decoded = 0
    skipped = []
    for m in modules:
        rel = vfs_relpath(m["name"])
        if rel is None:
            skipped.append(m["name"].decode("utf-8", "replace"))
            continue
        path = os.path.join(out, "bunfs", rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        blob = data(m)
        with open(path, "wb") as f:
            f.write(blob)
        m["path"] = os.path.relpath(path, out)
        m["sha256"] = hashlib.sha256(blob).hexdigest()
        if rel.endswith(".zst") and decompress is not None:
            try:
                with open(path[: -len(".zst")], "wb") as f:
                    f.write(decompress(blob))
                decoded += 1
            except Exception:
                pass

    # Concatenation greppable de tout le JS, dans l'ordre de la table.
    main_path = os.path.join(out, "claude-%s.cli.js" % ver)
    with open(main_path, "wb") as f:
        if len(js_modules) == 1:
            f.write(data(js_modules[0]))
        else:
            for m in js_modules:
                f.write(HEADER % m["name"].rsplit(b"/", 1)[-1])
                f.write(data(m))
                f.write(b"\n")

    manifest = {
        "version": ver,
        "binary": os.path.abspath(binary),
        "layout": {
            "kind": "module-graph",
            "offsets_size": graph["offsets_size"],
            "record_stride": graph["record_stride"],
            "blob_offset": base,
            "blob_size": graph["byte_count"],
        },
        "entry": entry["name"].decode("utf-8", "replace"),
        "entry_source": entry["source"].decode("utf-8", "replace"),
        "module_count": len(modules),
        "js_module_count": len(js_modules),
        "js_total_bytes": sum(m["contents"][1] for m in js_modules),
        "bytecode_total_bytes": sum(m["bytecode_size"] for m in modules),
        "concatenated": os.path.basename(main_path),
        "modules": [
            {
                "name": m["name"].decode("utf-8", "replace"),
                "source": m["source"].decode("utf-8", "replace"),
                "size": m["contents"][1],
                "kind": m["kind"],
                "flags": m["flags"],
                "bytecode_size": m["bytecode_size"],
                "path": m.get("path"),
                "sha256": m.get("sha256"),
            }
            for m in modules
        ],
    }
    manifest_path = os.path.join(out, "claude-%s.manifest.json" % ver)
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)

    print("Version      : %s" % ver)
    print("Disposition  : table des modules (Offsets %d o, enregistrements %d o)"
          % (graph["offsets_size"], graph["record_stride"]))
    print("Entree       : %s  (source %s)" % (manifest["entry"], manifest["entry_source"]))
    print("Modules      : %d dont %d JS (%.1f Mo) et %d assets ; bytecode ignore (%.1f Mo)"
          % (len(modules), len(js_modules), manifest["js_total_bytes"] / 1e6,
             len(modules) - len(js_modules), manifest["bytecode_total_bytes"] / 1e6))
    print("Miroir VFS   : %s/bunfs/  (%d .zst decompresses a cote)" % (out, decoded))
    print("Concat. JS   : %s" % main_path)
    print("Manifeste    : %s" % manifest_path)
    if skipped:
        print("Ignores      : %d noms hors /$bunfs/ ou suspects : %s" % (len(skipped), ", ".join(skipped[:5])))
    _sanity(main_path)


def _sanity(path):
    with open(path, "rb") as f:
        blob = f.read()
    print("Verif        :", "  ".join("%s=%d" % (n.decode(), blob.count(n)) for n in SANITY_NEEDLES))


# ------------------------------------------------------------------- carve
def carve(mm, min_run):
    """(start, end) des runs de texte imprimable >= min_run — lineaire en O(n)."""
    return [(m.start(), m.end()) for m in PRINTABLE_RUN.finditer(mm) if m.end() - m.start() >= min_run]


def extract_carve(mm, binary, out, label, min_run):
    runs = carve(mm, min_run)
    if not runs:
        sys.exit("Aucun bloc de texte >= %d octets trouve." % min_run)
    runs.sort(key=lambda r: r[1] - r[0], reverse=True)
    os.makedirs(out, exist_ok=True)

    a, b = runs[0]
    bundle = mm[a:b]
    ver = label or detect_version(binary, bundle)
    hit = VERSION_RE.search(bundle[:4096])
    if not label and hit:
        ver = hit.group(1).decode()
    main_path = os.path.join(out, "claude-%s.cli.js" % ver)
    with open(main_path, "wb") as f:
        f.write(bundle)
    for i, (a, b) in enumerate(runs[1:], 1):
        with open(os.path.join(out, "block_%03d.js" % i), "wb") as f:
            f.write(mm[a:b])
    print("Version      : %s" % ver)
    print("Disposition  : carve (repli) — %d blocs >= %d o, le plus gros = %s (%.1f Mo)"
          % (len(runs), min_run, main_path, len(bundle) / 1e6))
    print("ATTENTION    : sur un binaire >= 2.1.242 le carve ne voit qu'une fraction des chunks.")
    _sanity(main_path)


# -------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(
        description="Extrait le JS lisible (et les assets) d'un binaire Claude Code compile par Bun."
    )
    ap.add_argument("binary", nargs="?", help="Chemin du binaire (defaut : auto-detection).")
    ap.add_argument("-o", "--out", default="claude-js-extracted", help="Dossier de sortie.")
    ap.add_argument("--label", help="Force l'etiquette de version dans les noms.")
    ap.add_argument("--carve", action="store_true",
                    help="Force l'ancien decoupage par blocs de texte (ignore la table des modules).")
    ap.add_argument("--min-run", type=int, default=100_000,
                    help="Carve : taille min d'un bloc (octets, defaut 100000).")
    args = ap.parse_args()

    binary = args.binary or find_claude_binary()
    if not binary:
        sys.exit(
            "Aucun binaire trouve. Donne le chemin en argument, ex. :\n"
            "  extract-bun-js.py /chemin/vers/claude\n"
            "(la 2.1.112 npm est deja du cli.js pur : rien a extraire)."
        )
    if not os.path.isfile(binary):
        sys.exit("Fichier introuvable : %s" % binary)

    print("Binaire      : %s (%.0f Mo)" % (binary, os.path.getsize(binary) / 1e6))
    with open(binary, "rb") as f:
        mm = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            trailer_pos = mm.rfind(TRAILER)
            if trailer_pos < 0:
                sys.exit(
                    "Trailer Bun \"---- Bun! ----\" absent : ce n'est pas un binaire\n"
                    "Bun standalone. (Si c'est la 2.1.112 npm, c'est deja du cli.js.)"
                )
            print("Trailer Bun  : OK (offset %d)" % trailer_pos)
            graph = None if args.carve else parse_module_graph(mm, trailer_pos)
            if graph is None:
                if not args.carve:
                    print("Table des modules illisible (format Bun inconnu) -> repli carve.")
                extract_carve(mm, binary, args.out, args.label, args.min_run)
            else:
                extract_graph(mm, graph, binary, args.out, args.label)
        finally:
            mm.close()


if __name__ == "__main__":
    main()
