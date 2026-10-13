#!/usr/bin/env python3
"""Compile and link each Hyprland (or Hypoland) fragment shader on a real EGL context. No compositor needed.

  shadercheck.py DIR --ctx 3.2|3.0|2.0 [--flavor hyprland|hypoland] [--platform surfaceless|gbm:/dev/dri/renderD128]

DIR is src/render/shaders/glsl of the source tree. The script does what the ShaderLoader does: it puts each
'#include "file"' in line, and it replaces defines.h with one '#define USE_X 0|1' line per feature.
For Hyprland it then runs the glslang preprocessor (glslangValidator -E), as Hyprland does, if the tool is there.
Each fragment shader is compiled and LINKED with the vertex shader that Hyprland uses.

Limits: a link is not a draw. A driver that makes its machine code at the first draw (lima does this) can still
fail later. The same script on the frame is the first test for lima; this run on llvmpipe is its control.
Standard library only (ctypes); it runs on the frame too.
"""
import argparse
import ctypes as C
import os
import re
import subprocess
import sys

EGL_OPENGL_ES_API, EGL_NONE = 0x30A0, 0x3038
EGL_CONTEXT_MAJOR, EGL_CONTEXT_MINOR = 0x3098, 0x30FB
EGL_PLATFORM_SURFACELESS_MESA, EGL_PLATFORM_GBM_KHR = 0x31DD, 0x31D7
GL_FRAGMENT_SHADER, GL_VERTEX_SHADER, GL_COMPILE_STATUS, GL_LINK_STATUS = 0x8B30, 0x8B31, 0x8B81, 0x8B82
GL_VENDOR, GL_RENDERER, GL_VERSION, GL_SLV, GL_EXTENSIONS = 0x1F00, 0x1F01, 0x1F02, 0x8B8C, 0x1F03

FEATURES = {
    "hyprland": ["USE_RGBA", "USE_DISCARD", "USE_TINT", "USE_ROUNDING", "USE_CM", "USE_TONEMAP", "USE_SDR_MOD", "USE_BLUR",
                 "USE_ICC", "USE_MIRROR", "USE_MOTION_BLUR", "USE_BLUR_ALPHA_MASK", "USE_BLUR_MATTE", "USE_ALT_TONEMAP"],
    "hypoland": ["USE_RGBA", "USE_DISCARD", "USE_TINT", "USE_ROUNDING", "USE_BLUR", "USE_BLUR_ALPHA_MASK", "USE_BLUR_MATTE"],
}
# What a plain desktop uses most: textures with alpha, discard, tint; then with rounding; then with blur behind.
COMBOS = [["USE_RGBA", "USE_DISCARD", "USE_TINT"], ["USE_RGBA", "USE_DISCARD", "USE_TINT", "USE_ROUNDING"],
          ["USE_RGBA", "USE_DISCARD", "USE_TINT", "USE_ROUNDING", "USE_BLUR"]]


def make_context(platform, major, minor):
    egl = C.CDLL("libEGL.so.1")
    egl.eglGetPlatformDisplay.restype = C.c_void_p
    egl.eglGetPlatformDisplay.argtypes = [C.c_uint, C.c_void_p, C.c_void_p]
    egl.eglCreateContext.restype = C.c_void_p
    egl.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
    egl.eglMakeCurrent.argtypes = [C.c_void_p] * 4
    egl.eglInitialize.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int)]
    if platform.startswith("gbm:"):
        gbm = C.CDLL("libgbm.so.1")
        gbm.gbm_create_device.restype = C.c_void_p
        fd = os.open(platform[4:], os.O_RDWR)
        dpy = egl.eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, gbm.gbm_create_device(fd), None)
    else:
        dpy = egl.eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, None, None)
    ma, mi = C.c_int(), C.c_int()
    if not dpy or not egl.eglInitialize(dpy, C.byref(ma), C.byref(mi)):
        sys.exit("eglInitialize failed")
    egl.eglBindAPI(EGL_OPENGL_ES_API)
    attrs = (C.c_int * 5)(EGL_CONTEXT_MAJOR, major, EGL_CONTEXT_MINOR, minor, EGL_NONE)
    ctx = egl.eglCreateContext(dpy, None, None, attrs)  # EGL_NO_CONFIG_KHR, as Hyprland does
    if not ctx:
        return None, f"eglCreateContext(ES {major}.{minor}) FAILED, EGL error 0x{egl.eglGetError():04x}"
    if not egl.eglMakeCurrent(dpy, None, None, ctx):
        return None, f"eglMakeCurrent FAILED, EGL error 0x{egl.eglGetError():04x}"
    return egl, None


def gl_lib():
    gl = C.CDLL("libGLESv2.so.2")
    gl.glGetString.restype = C.c_char_p
    return gl


def info_log(gl, obj, shader):
    buf = C.create_string_buffer(8192)
    n = C.c_int()
    (gl.glGetShaderInfoLog if shader else gl.glGetProgramInfoLog)(obj, 8192, C.byref(n), buf)
    return buf.value.decode(errors="replace").strip()


def compile_shader(gl, kind, src):
    sh = gl.glCreateShader(kind)
    data = src.encode()
    arr = (C.c_char_p * 1)(data)
    gl.glShaderSource(sh, 1, arr, None)
    gl.glCompileShader(sh)
    ok = C.c_int()
    gl.glGetShaderiv(sh, GL_COMPILE_STATUS, C.byref(ok))
    return sh, bool(ok.value), info_log(gl, sh, True)


def link(gl, vs, fs):
    prog = gl.glCreateProgram()
    gl.glAttachShader(prog, vs)
    gl.glAttachShader(prog, fs)
    gl.glLinkProgram(prog)
    ok = C.c_int()
    gl.glGetProgramiv(prog, GL_LINK_STATUS, C.byref(ok))
    log = info_log(gl, prog, False)
    gl.glDeleteProgram(prog)
    return bool(ok.value), log


def inline(d, name, defines, depth=0, seen=None):
    seen = seen if seen is not None else set()
    out = []
    for line in open(os.path.join(d, name), encoding="utf-8"):
        s = line.strip()
        if s.startswith("#extension GL_ARB_shading_language_include") or s.startswith("#define ALLOW_INCLUDES"):
            continue
        m = re.match(r'#include\s+"([^"]+)"', s)
        if not m:
            out.append(line.rstrip("\n"))
            continue
        inc = m.group(1)
        seen.add(inc)
        if inc == "defines.h" and defines is not None:
            out.append(defines)
        elif depth < 16 and os.path.exists(os.path.join(d, inc)):
            out.append(inline(d, inc, defines, depth + 1, seen)[0])
        else:
            out.append(f"// include {inc} not found")
    return "\n".join(out), seen


def glslang_preprocess(src, stage):
    try:
        r = subprocess.run(["glslangValidator", "-E", "--stdin", "-S", stage], input=src, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired):
        return src, "glslangValidator not usable"
    if r.returncode != 0:
        return src, "glslang preprocess FAILED: " + (r.stdout + r.stderr).strip().splitlines()[0][:200]
    return "\n".join(l for l in r.stdout.splitlines() if not l.startswith("#line ")), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--ctx", default="3.2")
    ap.add_argument("--flavor", default="hyprland", choices=FEATURES)
    ap.add_argument("--platform", default="surfaceless")
    ap.add_argument("-v", action="store_true", help="print the info log of each failure in full")
    a = ap.parse_args()
    major, minor = (int(x) for x in a.ctx.split("."))
    egl, err = make_context(a.platform, major, minor)
    env = {k: v for k, v in os.environ.items() if k.startswith(("MESA_", "LIBGL_", "GALLIUM_"))}
    print(f"# flavor={a.flavor} requested context=ES {a.ctx} platform={a.platform} env={env}")
    if err:
        print("# " + err)
        print("RESULT: no context, 0 shaders tested")
        return 2
    gl = gl_lib()
    exts = (gl.glGetString(GL_EXTENSIONS) or b"").decode().split()
    print(f"# GL_VERSION  = {gl.glGetString(GL_VERSION).decode()}")
    print(f"# GL_RENDERER = {gl.glGetString(GL_RENDERER).decode()}")
    print(f"# GLSL        = {gl.glGetString(GL_SLV).decode()}")
    print(f"# extensions  = {len(exts)}; of interest: " + " ".join(
        e for e in exts if re.search(r"half_float|color_buffer_float|BGRA8888|EGL_image|vertex_array_object|texture_float|standard_derivatives|draw_buffers|texture_3D|rg$", e)))
    feats = FEATURES[a.flavor]
    verts = [("tex300.vert", "vert")] if a.flavor == "hyprland" else [("tex.vert", "vert")]
    vsrc = inline(a.dir, verts[0][0], None)[0]
    if a.flavor == "hyprland":
        vsrc, perr = glslang_preprocess(vsrc, "vert")
    vs, vok, vlog = compile_shader(gl, GL_VERTEX_SHADER, vsrc)
    print(f"{'OK  ' if vok else 'FAIL'} {verts[0][0]:24s} (vertex shader){'' if vok else '  ' + vlog.splitlines()[0][:160] if vlog else ''}")
    n_ok = n_fail = 0
    for frag in sorted(f for f in os.listdir(a.dir) if f.endswith(".frag")):
        uses_defines = "defines.h" in inline(a.dir, frag, "")[1]
        variants = [("base", [])]
        if uses_defines:
            variants += [(f, [f]) for f in feats] + [("+".join(x[4:] for x in c), c) for c in COMBOS if all(x in feats for x in c)]
        for vname, on in variants:
            defines = "\n".join(f"#define {f} {1 if f in on else 0}" for f in feats) if uses_defines else None
            src = inline(a.dir, frag, defines)[0]
            perr = None
            if a.flavor == "hyprland":
                src, perr = glslang_preprocess(src, "frag")
            fs, ok, log = compile_shader(gl, GL_FRAGMENT_SHADER, src)
            stage = "compile"
            if ok and vok:
                ok, log = link(gl, vs, fs)
                stage = "link"
            gl.glDeleteShader(fs)
            n_ok += ok
            n_fail += not ok
            first = (perr or (log.splitlines()[0] if log else "")).strip()[:170]
            print(f"{'OK  ' if ok else 'FAIL'} {frag:24s} {vname:34s}{'' if ok else f' [{stage}] {first}'}")
            if a.v and not ok:
                print("     " + log.replace("\n", "\n     ")[:1500])
    print(f"RESULT: {n_ok} variants compile and link, {n_fail} fail")
    return 0 if n_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
