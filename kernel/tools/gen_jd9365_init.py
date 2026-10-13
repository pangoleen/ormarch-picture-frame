#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0+
"""
Generate the PF1007L panel entry for drivers/gpu/drm/panel/panel-jadard-jd9365da-h3.c.

Inputs (all from THIS frame, nothing is typed by hand):
  --seq     dumps/panel/sq9365_init_sequence.txt   vendor DSI init sequence
  --fex     dumps/sys_config.fex                   vendor board config ([lcd0_para])
  --driver  the driver source to patch. Two bases are in use (see regen_patch.sh):
            refs/kernel/linux-7.2.10/drivers/gpu/drm/panel/panel-jadard-jd9365da-h3.c
            (Linux v7.2.10 = the stock linux-armv7 7.2.10-1 kernel; this one is built)
            refs/linux-snippets/panel-jadard-jd9365da-h3.c   (mainline master)

Outputs:
  --out-patch  unified diff against the driver (apply with `patch -p1` or `git apply`)
  --out-c      (optional) only the generated C block

Checks (the script stops with exit code 1 if one fails):
  1. The generated C is parsed again with a small model of the driver helpers.
     The result must be the same list of DSI writes and delays as the sequence
     file. One normalisation is applied and reported: the vendor table has
     "11 00" and "29 00" (command + one zero parameter); the driver helpers
     mipi_dsi_dcs_exit_sleep_mode_multi() / mipi_dsi_dcs_set_display_on_multi()
     send the same commands with no parameter.
  2. The helper model is checked against the driver source
     (jadard_enable_standard_cmds and jd9365da_switch_page must have the
     expected bodies).
  3. The display timing arithmetic is checked (sums equal lcd_ht / lcd_vt).

Extra: --compare prints how far each panel that is already in the driver is
from this sequence (number of different register writes).

No device access. Read-only on dumps/ and refs/.
"""

import argparse
import difflib
import re
import sys
from pathlib import Path

# ----------------------------------------------------------------------------
# Names. PLACEHOLDERS: review before any upstream submission.
# The name comes from the vendor fex: lcd_driver_name = "yhk_zr789_sq9365_101".
# The real panel maker and part number are not known (label on the panel back).
# ----------------------------------------------------------------------------
COMPATIBLE = "yhk,zr789-sq9365-101"
C_PREFIX = "yhk_zr789_sq9365_101"

KERNEL_PATH = "drivers/gpu/drm/panel/panel-jadard-jd9365da-h3.c"

PAGE_REG = 0xE0
STANDARD_CMDS_4LANE = [(0xE1, 0x93), (0xE2, 0x65), (0xE3, 0xF8), (0x80, 0x03)]
STANDARD_CMDS_2LANE = [(0xE1, 0x93), (0xE2, 0x65), (0xE3, 0xF8), (0x80, 0x01)]

DCS_EXIT_SLEEP = 0x11
DCS_DISPLAY_ON = 0x29
DCS_SET_TEAR_ON = 0x35
DCS_NOP = 0x00


def die(msg):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(1)


# ----------------------------------------------------------------------------
# 1. Sequence file
# ----------------------------------------------------------------------------
def parse_sequence(path):
    """Return a list of ops: ("w", cmd, (params...)) or ("delay", ms)."""
    ops = []
    ended = False
    for n, raw in enumerate(Path(path).read_text().splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if ended:
            die(f"{path}:{n}: data after the end marker")
        if line.startswith("#"):
            m = re.match(r"#\s*special:\s*cmd=0x([0-9a-fA-F]+)\s+count=(\d+)", line)
            if not m:
                continue  # plain comment
            cmd, count = int(m.group(1), 16), int(m.group(2))
            if cmd == 0xFF0:
                ops.append(("delay", count))
            elif cmd == 0xFF1:
                ended = True
            else:
                die(f"{path}:{n}: unknown special command 0x{cmd:x}")
            continue
        parts = line.split()
        try:
            vals = [int(p, 16) for p in parts]
        except ValueError:
            die(f"{path}:{n}: cannot parse '{line}'")
        if any(v > 0xFF for v in vals):
            die(f"{path}:{n}: value larger than one byte")
        ops.append(("w", vals[0], tuple(vals[1:])))
    if not ended:
        die(f"{path}: no end marker (special cmd=0xff1)")
    return ops


# ----------------------------------------------------------------------------
# 2. C generation, in the style of the driver
# ----------------------------------------------------------------------------
def emit_init(ops, func, exact_11_29=False, post_delay_ms=0, post_delay_note=""):
    out = []
    out.append(f"static int {func}(struct jadard *jadard)")
    out.append("{")
    out.append("\tstruct mipi_dsi_multi_context dsi_ctx = { .dsi = jadard->dsi };")
    out.append("")
    i = 0
    first = True
    while i < len(ops):
        op = ops[i]
        if op[0] == "delay":
            if out[-1] != "":
                out.append("")
            out.append(f"\tmipi_dsi_msleep(&dsi_ctx, {op[1]});")
            out.append("")
            i += 1
            continue
        _, cmd, params = op
        if cmd == PAGE_REG and len(params) == 1:
            if not first and out[-1] != "":
                out.append("")
            out.append(f"\tjd9365da_switch_page(&dsi_ctx, 0x{params[0]:02x});")
            # The driver has a helper for E1 93 / E2 65 / E3 F8 / 80 03 (4 lanes).
            nxt = [(o[1], o[2][0]) for o in ops[i + 1:i + 5]
                   if o[0] == "w" and len(o[2]) == 1]
            if i == 0 and params[0] == 0x00 and nxt == STANDARD_CMDS_4LANE:
                out.append("\tjadard_enable_standard_cmds(&dsi_ctx);")
                i += 5
            else:
                i += 1
            first = False
            continue
        if cmd == DCS_EXIT_SLEEP and params in ((), (0x00,)) and not (exact_11_29 and params):
            if out[-1] != "":
                out.append("")
            out.append("\tmipi_dsi_dcs_exit_sleep_mode_multi(&dsi_ctx);")
            i += 1
            continue
        if cmd == DCS_DISPLAY_ON and params in ((), (0x00,)) and not (exact_11_29 and params):
            if out[-1] != "":
                out.append("")
            out.append("\tmipi_dsi_dcs_set_display_on_multi(&dsi_ctx);")
            i += 1
            continue
        args = ", ".join(f"0x{v:02x}" for v in (cmd,) + params)
        out.append(f"\tmipi_dsi_dcs_write_seq_multi(&dsi_ctx, {args});")
        first = False
        i += 1
    if out[-1] != "":
        out.append("")
    if post_delay_ms:
        if post_delay_note:
            out.append(f"\t/* {post_delay_note} */")
        out.append(f"\tmipi_dsi_msleep(&dsi_ctx, {post_delay_ms});")
        out.append("")
    out.append("\treturn dsi_ctx.accum_err;")
    out.append("}")
    return "\n".join(out) + "\n"


# ----------------------------------------------------------------------------
# 3. A small model of the driver helpers: C text -> list of ops
# ----------------------------------------------------------------------------
SYMBOLS = {
    "MIPI_DCS_SET_TEAR_ON": DCS_SET_TEAR_ON,
    "MIPI_DSI_DCS_TEAR_MODE_VBLANK": 0x00,
    "JD9365DA_DCS_SWITCH_PAGE": PAGE_REG,
}


def c_int(tok):
    tok = tok.strip()
    if tok in SYMBOLS:
        return SYMBOLS[tok]
    return int(tok, 0)


class ModelError(Exception):
    pass


def expand_c(body, lanes=4):
    """Expand one init function body to ops.

    Raises ModelError on any line it does not understand, so a silent
    mismatch is not possible. Understands the lane conditionals that the
    driver uses: "if (jadard->dsi->lanes == 4)" / "!= 4", with or without
    braces, and "else".
    """
    ops = []
    stack = []          # one bool per open "{" block: is the block active?
    pending = None      # condition for the next single statement (if without braces)
    last_cond = None    # condition of the last "if" without braces (for "else")
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line.startswith("/*") or line.startswith("*") or line.startswith("//"):
            continue
        m = re.match(r"if \(jadard->dsi->lanes (==|!=) (\d)\)( \{)?$", line)
        if m:
            cond = (lanes == int(m.group(2))) == (m.group(1) == "==")
            if m.group(3):
                stack.append(cond)
            else:
                pending = last_cond = cond
            continue
        if re.match(r"\} else\s+\{$", line):
            if not stack:
                raise ModelError("else without if")
            stack.append(not stack.pop())
            continue
        if line == "else":
            if last_cond is None:
                raise ModelError("else without if")
            pending = not last_cond
            continue
        if line == "}":
            if not stack:
                raise ModelError("unbalanced }")
            stack.pop()
            continue
        run = all(stack) and (pending is None or pending)
        pending = None
        if line.startswith("struct mipi_dsi_multi_context"):
            continue
        if re.match(r"return (dsi_ctx\.accum_err|0);$", line):
            continue
        m = re.match(r"jd9365da_switch_page\(&dsi_ctx, (\w+)\);$", line)
        if m:
            if run:
                ops.append(("w", PAGE_REG, (c_int(m.group(1)),)))
            continue
        if line == "jadard_enable_standard_cmds(&dsi_ctx);":
            std = STANDARD_CMDS_4LANE if lanes == 4 else STANDARD_CMDS_2LANE
            if run:
                ops.extend(("w", c, (v,)) for c, v in std)
            continue
        m = re.match(r"mipi_dsi_dcs_write_seq_multi\(&dsi_ctx, (.+)\);$", line)
        if m:
            vals = [c_int(t) for t in m.group(1).split(",")]
            if run:
                ops.append(("w", vals[0], tuple(vals[1:])))
            continue
        if line == "mipi_dsi_dcs_exit_sleep_mode_multi(&dsi_ctx);":
            if run:
                ops.append(("w", DCS_EXIT_SLEEP, ()))
            continue
        if line == "mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);":
            if run:
                ops.append(("w", DCS_DISPLAY_ON, ()))
            continue
        m = re.match(r"mipi_dsi_dcs_set_tear_on_multi\(&dsi_ctx, (\w+)\);$", line)
        if m:
            if run:
                ops.append(("w", DCS_SET_TEAR_ON, (c_int(m.group(1)),)))
            continue
        m = re.match(r"(?:mipi_dsi_msleep\(&dsi_ctx, |msleep\()(\d+)\);$", line)
        if m:
            if run:
                ops.append(("delay", int(m.group(1))))
            continue
        raise ModelError(f"cannot parse C line: {line!r}")
    if stack:
        raise ModelError("unbalanced {")
    return ops


def check_helper_model(driver_text):
    """The model above is only valid if the driver helpers are what we think."""
    want_macro = ("#define jd9365da_switch_page(dsi_ctx, page) \\\n"
                  "\tmipi_dsi_dcs_write_seq_multi(dsi_ctx, JD9365DA_DCS_SWITCH_PAGE, (page))")
    if want_macro not in driver_text:
        die("driver: jd9365da_switch_page() is not the expected macro")
    if "#define JD9365DA_DCS_SWITCH_PAGE\t0xe0" not in driver_text:
        die("driver: JD9365DA_DCS_SWITCH_PAGE is not 0xe0")
    want_std = (
        "static void jadard_enable_standard_cmds(struct mipi_dsi_multi_context *dsi_ctx)\n"
        "{\n"
        "\tmipi_dsi_dcs_write_seq_multi(dsi_ctx, 0xe1, 0x93);\n"
        "\tmipi_dsi_dcs_write_seq_multi(dsi_ctx, 0xe2, 0x65);\n"
        "\tmipi_dsi_dcs_write_seq_multi(dsi_ctx, 0xe3, 0xf8);\n"
        "\tif (dsi_ctx->dsi->lanes == 2)\n"
        "\t\tmipi_dsi_dcs_write_seq_multi(dsi_ctx, 0x80, 0x01);\n"
        "\telse\n"
        "\t\tmipi_dsi_dcs_write_seq_multi(dsi_ctx, 0x80, 0x03);\n"
        "}\n")
    if want_std not in driver_text:
        die("driver: jadard_enable_standard_cmds() is not the expected function")
    # Sleep-out / display-on must not be sent a second time by common code.
    m = re.search(r"static int jadard_prepare\(.*?\n}\n", driver_text, re.S)
    if not m:
        die("driver: jadard_prepare() not found")
    for bad in ("exit_sleep_mode", "set_display_on"):
        if bad in m.group(0):
            die(f"driver: jadard_prepare() already sends {bad}; the init function must not")
    if re.search(r"\.enable\s*=", driver_text.split("static const struct drm_panel_funcs jadard_funcs")[1].split("};")[0]):
        die("driver: jadard_funcs has an .enable hook; check for a second display-on")


def driver_init_functions(driver_text):
    """Yield (name, body) of every init function in the driver."""
    for m in re.finditer(r"^static int (\w+)\(struct jadard \*jadard\)\n\{\n(.*?)^\};?\n",
                         driver_text, re.S | re.M):
        yield m.group(1), m.group(2)


def reg_map(ops):
    """(page, reg) -> value, for the register writes (page-aware compare)."""
    page, out = None, {}
    for op in ops:
        if op[0] != "w" or len(op[2]) != 1:
            continue
        if op[1] == PAGE_REG:
            page = op[2][0]
            continue
        out[(page, op[1])] = op[2][0]
    return out


def normalise(ops):
    """Vendor '11 00' / '29 00' == helper form with no parameter."""
    out, changed = [], []
    for op in ops:
        if op[0] == "w" and op[1] in (DCS_EXIT_SLEEP, DCS_DISPLAY_ON) and op[2] == (0x00,):
            out.append(("w", op[1], ()))
            changed.append(op[1])
        else:
            out.append(op)
    return out, changed


# ----------------------------------------------------------------------------
# 4. Timings from the fex
# ----------------------------------------------------------------------------
def parse_fex_section(path, section):
    vals, cur = {}, None
    for raw in Path(path).read_text().splitlines():
        line = raw.strip()
        if line.startswith("[") and line.endswith("]"):
            cur = line[1:-1]
            continue
        if cur == section and "=" in line and not line.startswith(";"):
            k, v = (s.strip() for s in line.split("=", 1))
            vals[k] = v
    if not vals:
        die(f"{path}: section [{section}] not found")
    return vals


def timings_from_fex(path):
    f = parse_fex_section(path, "lcd0_para")

    def num(k):
        return int(f[k], 0)

    if num("lcd_if") != 4:
        die("fex: lcd_if is not 4 (MIPI-DSI)")
    if num("lcd_dsi_if") != 0:
        die("fex: lcd_dsi_if is not 0 (video mode); review the mode flags")
    if num("lcd_dsi_format") != 0:
        die("fex: lcd_dsi_format is not 0 (RGB888)")
    t = {
        "x": num("lcd_x"), "y": num("lcd_y"),
        "ht": num("lcd_ht"), "hbp_fex": num("lcd_hbp"), "hspw": num("lcd_hspw"),
        "vt": num("lcd_vt"), "vbp_fex": num("lcd_vbp"), "vspw": num("lcd_vspw"),
        "dclk_mhz": num("lcd_dclk_freq"), "lanes": num("lcd_dsi_lane"),
        "w_mm": num("lcd_width"), "h_mm": num("lcd_height"),
        "name": f["lcd_driver_name"].strip('"'),
    }
    # Allwinner BSP convention: lcd_hbp and lcd_vbp INCLUDE the sync width.
    # Primary source: BSP de_dsi.c (sun8iw5): "dsi_hbp = (hbp-hspw)*...",
    # "basic_size0.vbp = vbp-vspw", "vfp = lcd_vt - lcd_y - lcd_vbp".
    t["hsync"] = t["hspw"]
    t["hbp"] = t["hbp_fex"] - t["hspw"]
    t["hfp"] = t["ht"] - t["x"] - t["hbp_fex"]
    t["vsync"] = t["vspw"]
    t["vbp"] = t["vbp_fex"] - t["vspw"]
    t["vfp"] = t["vt"] - t["y"] - t["vbp_fex"]
    for k in ("hsync", "hbp", "hfp", "vsync", "vbp", "vfp"):
        if t[k] <= 0:
            die(f"timing {k} = {t[k]} is not positive")
    if t["x"] + t["hfp"] + t["hsync"] + t["hbp"] != t["ht"]:
        die("horizontal sum does not equal lcd_ht")
    if t["y"] + t["vfp"] + t["vsync"] + t["vbp"] != t["vt"]:
        die("vertical sum does not equal lcd_vt")
    t["refresh"] = t["dclk_mhz"] * 1e6 / (t["ht"] * t["vt"])
    if not 50 <= t["refresh"] <= 70:
        die(f"refresh {t['refresh']:.2f} Hz is outside 50-70 Hz; is lcd_vt doubled?")
    return t


def print_timings(t):
    print("Display timings (fex [lcd0_para] -> drm_display_mode):")
    print(f"  hsync  = lcd_hspw                    = {t['hsync']}")
    print(f"  hbp    = lcd_hbp - lcd_hspw          = {t['hbp_fex']} - {t['hspw']} = {t['hbp']}")
    print(f"  hfp    = lcd_ht - lcd_x - lcd_hbp    = {t['ht']} - {t['x']} - {t['hbp_fex']} = {t['hfp']}")
    print(f"  check  : {t['x']} + {t['hfp']} + {t['hsync']} + {t['hbp']} = {t['x'] + t['hfp'] + t['hsync'] + t['hbp']} (lcd_ht = {t['ht']})")
    print(f"  vsync  = lcd_vspw                    = {t['vsync']}")
    print(f"  vbp    = lcd_vbp - lcd_vspw          = {t['vbp_fex']} - {t['vspw']} = {t['vbp']}")
    print(f"  vfp    = lcd_vt - lcd_y - lcd_vbp    = {t['vt']} - {t['y']} - {t['vbp_fex']} = {t['vfp']}")
    print(f"  check  : {t['y']} + {t['vfp']} + {t['vsync']} + {t['vbp']} = {t['y'] + t['vfp'] + t['vsync'] + t['vbp']} (lcd_vt = {t['vt']})")
    print(f"  refresh= {t['dclk_mhz']} MHz / ({t['ht']} x {t['vt']}) = {t['refresh']:.3f} Hz")


def emit_desc(t, extra_desc_lines):
    x, y = t["x"], t["y"]
    lines = [
        f"static const struct jadard_panel_desc {C_PREFIX}_desc = {{",
        "\t.mode_4ln = &(const struct drm_display_mode) {",
        f"\t\t.clock\t\t= {t['dclk_mhz'] * 1000},",
        "",
        f"\t\t.hdisplay\t= {x},",
        f"\t\t.hsync_start\t= {x} + {t['hfp']},",
        f"\t\t.hsync_end\t= {x} + {t['hfp']} + {t['hsync']},",
        f"\t\t.htotal\t\t= {x} + {t['hfp']} + {t['hsync']} + {t['hbp']},",
        "",
        f"\t\t.vdisplay\t= {y},",
        f"\t\t.vsync_start\t= {y} + {t['vfp']},",
        f"\t\t.vsync_end\t= {y} + {t['vfp']} + {t['vsync']},",
        f"\t\t.vtotal\t\t= {y} + {t['vfp']} + {t['vsync']} + {t['vbp']},",
        "",
        f"\t\t.width_mm\t= {t['w_mm']},",
        f"\t\t.height_mm\t= {t['h_mm']},",
        "\t\t.type\t\t= DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED,",
        "\t},",
        f"\t.lanes = {t['lanes']},",
        "\t.format = MIPI_DSI_FMT_RGB888,",
        f"\t.init = {C_PREFIX}_init_cmds,",
    ]
    lines += extra_desc_lines
    lines += [
        "\t/*",
        "\t * Non-burst video mode with sync pulses (vendor lcd_dsi_if = 0).",
        "\t * Do not use the driver default: it has MIPI_DSI_MODE_VIDEO_BURST.",
        "\t */",
        "\t.mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_SYNC_PULSE |",
        "\t\t      MIPI_DSI_MODE_NO_EOT_PACKET | MIPI_DSI_MODE_LPM,",
        "};",
    ]
    return "\n".join(lines) + "\n"


# ----------------------------------------------------------------------------
# 5. Patch assembly
# ----------------------------------------------------------------------------
DEFAULT_PATCH_STATE = "DRAFT - not compiled, not tested on hardware. Do not send upstream as is."

PATCH_HEADER = """\
{state}

drm/panel: jadard-jd9365da-h3: add the PF1007L photo-frame panel

Add the 10.1 inch 800x1280 MIPI-DSI panel of the EFERCRO PF1007L board
(Humblestead HM-PF1007-BK photo frame, Allwinner A33). The vendor panel
driver name is "{name}". The vendor init table starts
with the JD9365DA sequence (E1 93, E2 65, E3 F8, 80 03). The controller ID
was not read from the hardware.

- The init function is generated by kernel/tools/gen_jd9365_init.py from
  the vendor init table (dumps/panel/sq9365_init_sequence.txt). The script
  checks that the code gives the same writes and delays as the table.
- The mode comes from the vendor sys_config.fex [lcd0_para]:
  {dclk} MHz, {x}+{hfp}+{hsync}+{hbp} = {ht}, {y}+{vfp}+{vsync}+{vbp} = {vt}, {refresh:.2f} Hz.
- mode_flags: non-burst video with sync pulses (vendor lcd_dsi_if = 0).

Open points:
- The compatible "{compat}" is a PLACEHOLDER made from the
  vendor driver name. The panel maker and part number are not known. Neither
  "yhk" nor a real maker is in vendor-prefixes.yaml. The binding
  (jadard,jd9365da-h3.yaml) also needs the new compatible.
- Power sequence fields: {delays_state}
---
"""


def build_patch(driver_text, block, t, delays_state, state=DEFAULT_PATCH_STATE):
    marker = "static int jadard_dsi_probe(struct mipi_dsi_device *dsi)\n"
    if driver_text.count(marker) != 1:
        die("driver: jadard_dsi_probe() marker not found exactly once")
    new = driver_text.replace(marker, block + "\n" + marker)
    sentinel = "\t{ /* sentinel */ }\n};\nMODULE_DEVICE_TABLE(of, jadard_of_match);"
    if new.count(sentinel) != 1:
        die("driver: of_match sentinel not found exactly once")
    entry = ("\t{\n"
             f"\t\t.compatible = \"{COMPATIBLE}\",\n"
             f"\t\t.data = &{C_PREFIX}_desc\n"
             "\t},\n")
    new = new.replace(sentinel, entry + sentinel)
    diff = difflib.unified_diff(
        driver_text.splitlines(keepends=True), new.splitlines(keepends=True),
        fromfile="a/" + KERNEL_PATH, tofile="b/" + KERNEL_PATH, n=3)
    header = PATCH_HEADER.format(
        state=state, name=t["name"], dclk=t["dclk_mhz"], x=t["x"], y=t["y"], ht=t["ht"], vt=t["vt"],
        hfp=t["hfp"], hsync=t["hsync"], hbp=t["hbp"], vfp=t["vfp"], vsync=t["vsync"],
        vbp=t["vbp"], refresh=t["refresh"], compat=COMPATIBLE, delays_state=delays_state)
    return header + "".join(diff), new


# ----------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seq", required=True)
    ap.add_argument("--fex", required=True)
    ap.add_argument("--driver", required=True)
    ap.add_argument("--out-patch")
    ap.add_argument("--out-c")
    ap.add_argument("--out-driver", help="write the patched driver file (for a check with patch(1))")
    ap.add_argument("--compare", action="store_true", help="compare with the panels already in the driver")
    ap.add_argument("--desc-extra", action="append", default=[],
                    help="extra line for the panel desc, e.g. '.lp11_before_reset = true,' (repeatable)")
    ap.add_argument("--vendor-exact-11-29", action="store_true",
                    help="send 0x11 and 0x29 with the zero parameter byte, as the vendor does "
                         "(DSI type 0x15), not with the driver helpers (type 0x05). For an A/B test.")
    ap.add_argument("--post-init-delay-ms", type=int, default=0,
                    help="extra delay after the table. The vendor code waits 150 ms between the "
                         "end of the table and the start of the HS clock (power-sequence.md, step 14). "
                         "This delay is NOT in the sequence file.")
    ap.add_argument("--delays-state", default="NOT SET (zero).",
                    help="text for the patch header")
    ap.add_argument("--patch-state", default=DEFAULT_PATCH_STATE,
                    help="first lines of the patch header: the base tree and what was built or tested")
    args = ap.parse_args()

    driver_text = Path(args.driver).read_text()
    check_helper_model(driver_text)

    seq_ops = parse_sequence(args.seq)
    writes = [o for o in seq_ops if o[0] == "w"]
    delays = [o for o in seq_ops if o[0] == "delay"]
    print(f"Sequence file: {len(writes)} writes, {len(delays)} delays "
          f"({', '.join(str(d[1]) + ' ms' for d in delays)})")
    if any(len(o[2]) != 1 for o in writes):
        die("sequence: a write does not have exactly one parameter")
    head = [(o[1], o[2][0]) for o in writes[:5]]
    if head != [(PAGE_REG, 0x00)] + STANDARD_CMDS_4LANE:
        die("sequence: does not start with E0 00, E1 93, E2 65, E3 F8, 80 03")

    t = timings_from_fex(args.fex)
    print_timings(t)
    if t["lanes"] != 4:
        die("fex: lcd_dsi_lane is not 4")

    func = f"{C_PREFIX}_init_cmds"
    init_c = emit_init(
        seq_ops, func, exact_11_29=args.vendor_exact_11_29,
        post_delay_ms=args.post_init_delay_ms,
        post_delay_note="Vendor LCD_panel_init(): wait before the HS clock starts." if args.post_init_delay_ms else "")
    extra = ["\t" + line.strip() for line in args.desc_extra]
    desc_c = emit_desc(t, extra)
    block = init_c + "\n" + desc_c

    # ---- Check 1: generated code == sequence file ---------------------------
    m = re.match(r"static int \w+\(struct jadard \*jadard\)\n\{\n(.*)^\}\n", init_c, re.S | re.M)
    try:
        gen_ops = expand_c(m.group(1), lanes=t["lanes"])
    except ModelError as e:
        die(f"helper model: {e}")
    if args.vendor_exact_11_29:
        want_ops, changed = list(seq_ops), []
    else:
        want_ops, changed = normalise(seq_ops)
    if args.post_init_delay_ms:
        # The extra delay is an addition from the vendor CODE, not from the table.
        # It must be the last op, and the ops before it must equal the table.
        if not gen_ops or gen_ops[-1] != ("delay", args.post_init_delay_ms):
            die("post-init delay is not the last generated op")
        gen_ops = gen_ops[:-1]
    if gen_ops != want_ops:
        for i, (a, b) in enumerate(zip(gen_ops, want_ops)):
            if a != b:
                die(f"generated code differs from the sequence at op {i}: code {a}, file {b}")
        die(f"generated code has {len(gen_ops)} ops, sequence file has {len(want_ops)}")
    n_reg = sum(1 for o in want_ops if o[0] == "w" and len(o[2]) == 1)
    print(f"CHECK 1 PASS: generated C == sequence file "
          f"({len(want_ops)} ops: {n_reg} one-parameter writes, "
          f"{sum(1 for o in want_ops if o[0] == 'w' and not o[2])} commands with no parameter, "
          f"{len(delays)} delays).")
    if changed:
        print("  Normalised (reported, not hidden): vendor sends "
              + " and ".join(f"'{c:02X} 00'" for c in changed)
              + " as command + one zero parameter; the driver helpers send the command with no parameter.")
    if args.post_init_delay_ms:
        print(f"  Added after the table (not in the sequence file): {args.post_init_delay_ms} ms delay, "
              "from the vendor code (power-sequence.md Table 1, step 14).")
    print("CHECK 2 PASS: driver helpers match the model; jadard_prepare() sends no sleep-out / display-on.")
    print("CHECK 3 PASS: timing sums equal lcd_ht / lcd_vt.")

    # ---- Optional: distance to the panels that are already in the driver -----
    if args.compare:
        ours = reg_map(want_ops)
        print("\nRegister-level distance to existing panels (4-lane expansion):")
        print(f"  {'init function':38s} {'writes':>6s} {'same':>5s} {'differ':>6s} {'only ours':>9s} {'only theirs':>11s}")
        rows = []
        skipped = []
        for name, body in driver_init_functions(driver_text):
            try:
                theirs = reg_map(expand_c(body, lanes=4))
            except (ModelError, ValueError) as e:
                skipped.append(f"{name}: {e}")
                continue
            same = sum(1 for k in ours if k in theirs and ours[k] == theirs[k])
            differ = sum(1 for k in ours if k in theirs and ours[k] != theirs[k])
            only_ours = sum(1 for k in ours if k not in theirs)
            only_theirs = sum(1 for k in theirs if k not in ours)
            rows.append((differ + only_ours + only_theirs, name, len(theirs), same, differ, only_ours, only_theirs))
        for _, name, n, same, differ, oo, ot in sorted(rows):
            print(f"  {name:38s} {n:6d} {same:5d} {differ:6d} {oo:9d} {ot:11d}")
        print(f"  (this panel: {len(ours)} register writes after page tracking)")
        for sk in skipped:
            print(f"  skipped, the model does not cover it: {sk}")

    if args.out_c:
        Path(args.out_c).write_text(block)
        print(f"wrote {args.out_c}")
    if args.out_patch or args.out_driver:
        patch, new_driver = build_patch(driver_text, block, t, args.delays_state, args.patch_state)
        if args.out_patch:
            Path(args.out_patch).write_text(patch)
            print(f"wrote {args.out_patch}")
        if args.out_driver:
            Path(args.out_driver).write_text(new_driver)
            print(f"wrote {args.out_driver}")


if __name__ == "__main__":
    main()
