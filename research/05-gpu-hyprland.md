# 05 — Can Hyprland render on Mali-400 MP2 (lima)? Fallbacks.

Date: 2026-10-12. Agent 5 of 6. Scope: GPU / renderer only.
Tags: **[VERIFIED]** = read in source (file:line or URL). **[DOCUMENTED]** = secondary source.
**[UNCONFIRMED]** = inference. Every "works" below means "the code path allows it". Nothing here was run on
the A33. Hardware tests are listed at the end.

Source snapshots read:
- `hyprwm/Hyprland` HEAD `663b29b8` (2026-10-09), VERSION **0.56.0**. Also tag **v0.49.0** (last legacy renderer).
- `hyprwm/aquamarine` HEAD `52ea11f0` (2026-10-03).
- Mesa main via mirror `chaotic-cx/mesa-mirror` `1f495287` (2026-10-12), **26.3.0-devel**
  (`github.com/Mesa3D/mesa` is not reachable from here; gitlab.freedesktop.org is blocked).
- Linux `drivers/gpu/drm/sun4i/*` from `torvalds/linux` master (raw.githubusercontent).
- `basecamp/omarchy` master (VERSION file says 4.0.0.alpha; latest tag **v4.0.4**).
- `hegjon/hypoland` `a01abe58` (2026-10-11), a GLES2 fork of Hyprland 0.56.0.

---

## Summary

1. **Upstream Hyprland 0.56 will NOT start on lima as shipped.** Hyprland and aquamarine both ask for a
   GLES 3.2 context, then 3.0, then abort (`src/render/OpenGL.cpp:204-227`; aquamarine
   `src/backend/drm/Renderer.cpp:490-512`). Lima reports GLES 2.0 only. [VERIFIED]
2. **The override hack is PLAUSIBLE for the default Omarchy look, but untested on lima.**
   `MESA_GLES_VERSION_OVERRIDE=3.0` makes Mesa skip the capability check and create an ES 3.0 context
   (`st_manager.c:1364`), and the GLSL compiler then accepts `#version 300 es`
   (`glsl_parser_extras.cpp:250`). The core shaders (surface, quad, border, shadow, passthru, ext) use
   only features that lima's compilers handle. It breaks on: integer/bitwise ops (fluid_jar blur),
   `textureSize`/`texelFetch` (motion blur and several "glass" blur styles), a 2nd render target
   (screen-share "mirror" path), fp16 precision everywhere. [VERIFIED code paths; behaviour UNCONFIRMED]
   Prior art: the same override boots Hyprland 0.56.2 + Omarchy 4.0.4 on Intel GM45/crocus (GLES2-only)
   — omarchy PR #14764. [DOCUMENTED] Crocus has native ints and fp32, lima does not, so this is evidence for
   the plumbing, not for lima.
3. **A purpose-built GLES2 Hyprland already exists: Hypoland** (fork of Hyprland 0.56.0, GLSL ES 1.00,
   GLES2 aquamarine, Lua config, runs **Omarchy 4** on a 1280x800 GM45). It needs only GLES 2.0 +
   `GL_OES_vertex_array_object` + `GL_EXT_texture_format_BGRA8888`, which Mesa exposes on every gallium
   driver including lima. Its PKGBUILD is `arch=(x86_64)` with `-march=x86-64`; it was never built for ARM.
   One-person project, 2 stars, history squashed to 1 commit. [VERIFIED source; not tested on ARM]
4. **The legacy renderer is a dead end for Omarchy.** It existed up to **0.49.0** (`-DLEGACY_RENDERER`,
   real GLES 2.0 context + `#version 100` shaders) and was removed in 0.50. Omarchy 4.x configures
   Hyprland in **Lua** (needs ≥ 0.55); Omarchy 3.8.x used hyprlang written for 0.50–0.54. Neither runs on
   0.49 without a config port. ALARM armv7h ships hyprland **0.49.0-3** (built Jul 2025), almost certainly
   without the legacy flag. [VERIFIED v0.49 source; ALARM version DOCUMENTED]
5. **Recommended path:** build Hyprland 0.56.x for armv7h (cross or in a fast ARM chroot — there is no
   current armv7h package), try the override first (zero code), and build Hypoland as the parallel
   fallback. Keep blur, shadows, rounding off (Omarchy 4 already ships them off). llvmpipe and Sway are
   the safety nets, not the goal.

---

## Hyprland GL requirements inventory (0.56.0)

Shaders live in `src/render/shaders/glsl/` (51 files, 3,939 lines). They are **preprocessed at runtime
by glslang** (for `#include`) and then handed to the driver (`ShaderLoader.cpp:92-133`). Variants are
built lazily per feature set, so a shader that cannot compile fails only when that feature is used.
**Shaders can be overridden at runtime without a rebuild**: `loadShader()` looks in a `hyprctl
reloadshaders <path>` directory, then `$HOME/hypr/shaders/<file>`, then the asset paths, before the
built-in copy (`ShaderLoader.cpp:180-200`; `ipc/s1/Commands.cpp:1947`). [VERIFIED]

### Shaders

| Shader(s) | When used | Version | Features that matter for lima |
|---|---|---|---|
| `tex300.vert` (`tex320.vert` only for user screen shaders starting `#version 320 es`) | every draw | 300 es | `in/out`, `mat3*vec3`. Trivial. |
| `surface.frag` (+ `rounding.glsl`, `CM.glsl`, `cm_helpers.glsl`, `tonemap.glsl`, `motion_blur.glsl`) | every window/layer texture | 300 es | `highp float`; `layout(location=0) out`; `layout(location=1) out mirrorColor` only with `USE_MIRROR`; `switch` on int TF (cm_helpers.glsl:129,164 — TFs are compile-time `#define`s); `uniform bool/int`; `textureSize` only with `USE_MOTION_BLUR` (surface.frag:143); `sampler3D` only with `USE_ICC` |
| `quad.frag`, `shadow.frag`, `border.frag` (+ `border.glsl`, `gradient.glsl`) | solid rects, shadows, borders | 300 es | as above; border indexes `uniform vec4 gradient[10]` with a dynamic int (gradient.glsl:51-55); MRT only with mirror |
| `rgbamatte.frag`, `passthru.frag`, `glitch.frag`, `inner_glow.frag` | mattes, copies, lockdead screen, glow | 300 es | MRT only with mirror |
| `ext.frag` | dmabufs needing `GL_TEXTURE_EXTERNAL_OES` | 300 es | `#extension GL_OES_EGL_image_external_essl3 : require`, `samplerExternalOES` |
| `blur1/2.frag`, `blurprepare.frag`, `blurfinish.frag` | only if `decoration:blur` on (Kawase) | 300 es | float only |
| `frostfinish`, `aurorafinish`, `dropsfinish`, `prismfinish`, `acrylicfinish`, `ripplefinish`, `waterfinish`/`waterstep`, `hazefinish`, `heatshimmerfinish` (+ `glassFinish.glsl`) | only if a "glass" blur style is selected | 300 es | `dFdx/dFdy/fwidth`; `textureSize` in acrylic (152), prism (66), ripple (29), water (35,46) |
| `fluidjar*.frag` (9 files) + `fluidJar.glsl` | only if `fluid_jar` blur selected **and** `EXT_color_buffer_half_float` present (`FluidJar.cpp:82-84`) | 300 es | `uvec4` outputs, `usampler2D`, `texelFetch`, `%`, `&`, `|`, `<<`, `>>`, `^` (fluidJar.glsl:24-40,135) |

No shader uses `flat` varyings. Precision is `highp` everywhere (`fluidjar*` also `highp int`).

### Runtime GL / EGL calls and extensions

| Requirement | Where | ES 2.0 core? | Hard or soft |
|---|---|---|---|
| ES **3.2 → 3.0** context via `EGL_CONTEXT_MAJOR/MINOR_VERSION`, `EGL_NO_CONFIG_KHR` | `OpenGL.cpp:204-227` | no | **hard** (RASSERT) |
| Same, inside aquamarine `CDRMRenderer::attempt` (run even on single-GPU, in `onReady` to collect GL formats) | aquamarine `Renderer.cpp:490-512`, `DRM.cpp:1541-1546` | no | hard for format list |
| `EGL_EXT_platform_device` **or** `EGL_KHR_platform_gbm` | `OpenGL.cpp:338-364` | — | hard |
| procs `eglCreateSyncKHR`, `eglDupNativeFenceFDANDROID`, `eglWaitSyncKHR` (loaded via `eglGetProcAddress`) | `OpenGL.cpp:315-317` | — | hard (Mesa returns stubs for known names) |
| `GL_EXT_texture_format_BGRA8888` | `OpenGL.cpp:380` | ext | hard. Mesa = `dummy_true` on ES2 (`extensions_table.h:340`) |
| `EGL_EXT_image_dma_buf_import(_modifiers)`, `GL_OES_EGL_image` (`glEGLImageTargetTexture2DOES`, `...RenderbufferStorageOES`) | `OpenGL.cpp:181-182,300-305` | ext | soft (warns, slower) |
| `EGL_ANDROID_native_fence_sync` | `OpenGL.cpp:388` | ext | soft. lima `native_fence_fd = true` (`lima_screen.c:150`) |
| VAOs `glGen/BindVertexArray` | throughout | **no** (ES3 core) | hard under ES3 path |
| `glDrawBuffers(2,…)`, `glClearBufferfv/uiv` | `GLFramebuffer.cpp:49-53`, `FluidJar.cpp:373` | no | 2 targets only for mirror FB |
| `GL_TEXTURE_SWIZZLE_*` | `GLTexture.cpp:225-228`, `GLRenderer.cpp:271-298` | no | used for every BGRA/cairo texture |
| `glUniformMatrix4x2fv` | `Shader.cpp:451` | no | non-square matrix |
| `glTexImage3D(GL_TEXTURE_3D, GL_RGBA16F)` | `GLTexture.cpp:118` | no | ICC LUT only |
| `glInvalidateFramebuffer` | `GLFramebuffer.cpp:259` | no | every FB |
| `GL_RGBA16F`/`ABGR16161616F` FBs, `GL_RGB32F` | `Renderer.cpp:3308`, `OpenGL.cpp:621`, `GLRenderer.cpp:287` | no | only when FP16/HDR or cairo RGB96F |
| NOT used: `glBlitFramebuffer`, `glReadBuffer`, PBOs, `glMapBufferRange`, transform feedback, UBOs | grep of all `gl*(` calls in `src/` | — | — |

Colour management: `render:cm_enabled` defaults **true** (`ConfigValues.cpp:657`) but the CM shader path is
**skipped** whenever source and target image descriptions match (`OpenGL.cpp:1493-1495`), i.e. a plain sRGB
desktop on an sRGB panel runs the non-CM variants. [VERIFIED]

### aquamarine (DRM backend)

- Atomic KMS by default, legacy fallback if `DRM_CLIENT_CAP_ATOMIC` fails or `AQ_NO_ATOMIC=1`
  (`DRM.cpp:751-755`). [VERIFIED]
- Split display/render devices (sun4i-drm card + lima renderD): it matches a render node by parent, else
  falls back to **the only renderD on the system** (`Session.cpp:221-270`; comment cites Asahi and notes
  that without it Mesa drops to llvmpipe). On the A33 lima is the only renderD, so it is picked. [VERIFIED]
- GBM allocator; its own trivial `#version 300 es` blit shaders (`Renderer.cpp:85-124`). [VERIFIED]

### sun4i-drm (A33 display engine 1.0)

- `DRIVER_ATOMIC` set (`sun4i_drv.c:48`). [VERIFIED]
- 4 layers per backend: 1 PRIMARY + 3 OVERLAY, **no CURSOR plane** → software cursor
  (`sun4i_layer.c:239-247`). [VERIFIED]
- Formats include `XRGB8888`, `ARGB8888`, `BGRX8888`, `RGB565`, YUV (via frontend); modifiers
  `LINEAR` and `ALLWINNER_TILED` (frontend only) (`sun4i_layer.c:141-188`). No 10-bit, no FP16 scanout
  — so Hyprland's FP16 path stays off. [VERIFIED]
- zpos and alpha properties exist (`sun4i_layer.c:221-223`). Whether the backend's plane-count /
  alpha-layer limits reject aquamarine overlay commits is **[UNCONFIRMED]** — test.

---

## Lima capability vs requirements (Mesa 26.3-devel)

| Requirement | Lima | Evidence |
|---|---|---|
| GLES version without override | **2.0** (`compute_version_es2` needs >40 features + `MaxColorAttachments >= 4` for 3.0) | `version.c:482-517`; lima docs "Will Lima support … ES 3.x? **No.**" (`docs/drivers/lima.rst:161`) |
| GLSL feature level | 120 (default, lima does not set it) | `u_screen.c:65-66` |
| Render targets | **1** (default) | `u_screen.c:49`; lima does not override |
| Native integers | **no** — `no_integers = true`, `nir_lower_int_to_float` | `lima_program.c:63,84,149,280` |
| Bitwise ops (`& | ^ << >>`) | **not lowerable** — `nir_lower_int_to_float` asserts/returns false on any other int op | `nir_lower_int_to_float.c:255-262` |
| Fragment precision | **FP16 only**, `highp` ignored; FP24 only for unmodified varying→texture coords | `lima.rst:120-133` |
| `textureSize` (txs), `texelFetch` (txf) | **unsupported** in ppir (`tex/txb/txl` only) | `ir/pp/nir.c:555-561` |
| `dFdx/dFdy/fwidth` | yes | `lima_screen.c:193`; `ir/pp/nir.c:505-507` |
| `samplerExternalOES` / `_essl3` | yes (ext always on; essl3 needs ctx ≥ 3.0) | `extensions.c:305`; `extensions_table.h:453-454`; `ir/pp/nir.c:569` |
| 3D textures | yes (`max_texture_3d_levels` set) | `lima_screen.c:170`, `st_extensions.c:138` |
| Texture swizzle | yes | `lima_screen.c:152` |
| Indirect uniform indexing (gradient[10]) | yes in FS | `lima_screen.c:136` |
| VAOs | ES2: `OES_vertex_array_object` dummy_true; ES3: core | `extensions_table.h:514` |
| BGRA8888 upload/read | dummy_true | `extensions_table.h:288,340` |
| Native fence fd | yes | `lima_screen.c:150` |
| Render to FP16 | possible but clamped to [0,1] | `lima.rst:138` |
| Loops / break / continue | yes; other jumps not | `ir/pp/nir.c:690-707` |

---

## Version-override hack verdict

**Verdict: PLAUSIBLE for the core compositor with Omarchy-4 defaults; IMPLAUSIBLE for fluid_jar,
motion blur, mirror/screen-share variants and several glass blur styles. Must be tested on hardware.**

The exact path [VERIFIED]:

1. EGL asks the frontend for the max ES version. `get_version()` returns the override **before** any
   capability check: `if (_mesa_override_gl_version_contextless(...)) return version;`
   (`mesa/state_tracker/st_manager.c:1356-1366`; same in `frontends/dri/dri_util.c:149-153`). So a 3.0
   (not 3.2) request succeeds. Hyprland's 3.2 attempt fails, it logs and retries 3.0 (`OpenGL.cpp:213`).
2. The context gets `ctx->Version = 30` (`main/context.c:1001` → `version.c:196-216`), so ES3 entry
   points (VAO, `glDrawBuffers`, `glTexImage3D`, swizzle, `glInvalidateFramebuffer`) are dispatched.
3. The GLSL front end adds `300 es` to the accepted list when `_mesa_is_gles3_compatible(ctx)`
   (`compiler/glsl/glsl_parser_extras.cpp:250-254`; `_mesa_is_gles3` = ES2 API && Version ≥ 30,
   `main/context.h:332-335`). `MESA_GLSL_VERSION_OVERRIDE` only changes `consts->GLSLVersion`
   (desktop GLSL, `st_extensions.c:1234`) — **for ES it is not needed**; harmless.
4. NIR then goes to lima's real compilers, which do not care about the advertised version:
   - ints → floats (`nir_lower_int_to_float`); `switch`/`uniform int`/`bool` survive this.
   - **bitwise ops fail** → fluid_jar cannot compile (it is also gated on `EXT_color_buffer_half_float`;
     whether Mesa exposes that on lima is UNCONFIRMED — if yes and the user picks fluid_jar, it breaks).
   - **`textureSize`/`texelFetch` fail** at ppir (`ir/pp/nir.c:560`) → motion blur and acrylic/prism/
     ripple/water blur variants break. Not used by Omarchy defaults.
   - **2nd colour output** → `ppir_output_invalid` (`ppir.h:230-235`, `nir.c:441-443`) and
     `glDrawBuffers(2)` exceeds `MaxDrawBuffers=1` → the "mirror" FB used when a monitor
     `needsUnmodifiedCopy()` (screen-share / mirror, `OpenGL.cpp:154-156`) fails. Desktop without
     screen-share does not hit it.
   - **FP16 precision**: `gl_FragCoord` above x=1024 has 1.0 px spacing in FP16, so `rounding.glsl` and
     the border gradient may jitter or band. Omarchy 4 sets `rounding = 0`
     (`omarchy/default/hypr/looknfeel.lua`). `pow(x, roundingPower)` can overflow FP16 (max 65504) with
     large radii. [UNCONFIRMED visual effect]
5. What the override cannot fix: any ES3 GL call whose gallium path lima does not implement (e.g. RGBA16F
   3D textures for ICC). Default desktop does not use those. [UNCONFIRMED in practice]

Why the crocus precedent is weaker evidence than it looks: Gen4/5 has native integers, fp32 fragment
shading and GLSL 1.20/1.30 hardware paths. Lima has none of these. The PR only proves that Hyprland's
ES3 *plumbing* runs on a driver that "lies" about 3.0. [DOCUMENTED, PR #14764]

---

## Legacy renderer verdict

- **Last version: 0.49.0.** Build flag `-DLEGACY_RENDERER=ON` / meson `legacy_renderer` → `GLES_VERSION
  GLES2`, real `EGL_CONTEXT_CLIENT_VERSION 2` context, RASSERT if that fails (`v0.49.0 CMakeLists.txt:102,219`;
  `src/render/OpenGL.cpp:165-182`). Shaders: `tex.vert` + `*_legacy.frag`/`rgba`/`rgbx`/`quad`/`ext`
  with **no `#version` line → GLSL ES 1.00**. So yes, it targeted GLES 2.0. [VERIFIED]
- **Removed in 0.50.0** (July 2025; "Hyprland now requires at least GLES 3.0"). [DOCUMENTED: Phoronix, release
  notes via search]
- **AUR `hyprland-legacyrenderer-git`**: stuck at 0.39.1.r119, maintainer discontinued it. Would need a
  PKGBUILD `arch` change for armv7h; untested. [DOCUMENTED]
- **ALARM armv7h `hyprland` = 0.49.0-3**, built 2025-07-08, while hyprutils etc. were rebuilt in 2026 —
  suggests ≥0.50 has not been built for armv7h (cause UNCONFIRMED). Arch's PKGBUILD does not enable the
  legacy flag [UNCONFIRMED], so even that 0.49 is an ES3 build.
- **Config incompatibility with Omarchy: total.** Omarchy v4.0.x (current release) ships only Lua files
  (`default/hypr/*.lua`, `hl.config({...})`, `hl.animation(...)`); Lua config arrived in Hyprland 0.55
  (May 2026). Omarchy v3.8.4 ships hyprlang `.conf` written for 0.50+ syntax. Omarchy's `bin/` scripts call
  current `hyprctl` dispatchers. Running 0.49 means porting both config and scripts backwards, and
  losing Omarchy updates forever.
- **Verdict: reject.** Hypoland is the legacy-renderer idea done against 0.56 + Lua, which is what
  Omarchy needs.

---

## Prior art

| What | Hardware | Result | Tag |
|---|---|---|---|
| omarchy PR #14764 (open, 2026-10-09): `MESA_GLES_VERSION_OVERRIDE=3.0` + `MESA_GLSL_VERSION_OVERRIDE=300`, set via `hl.env` when a Gen4/5 iGPU is detected | Intel GM45, crocus (GLES 2.0), Omarchy 4.0.4, Hyprland 0.56.2, Mesa 26.2.2 | "boots to a working desktop"; log shows 3.2 fail → 3.0 OK. `kms_swrast` "also works, but is slow". No perf numbers. | DOCUMENTED |
| `hegjon/hypoland` 0.1.0 (Hyprland 0.56.0 fork, GLES2/GLSL ES 1.00, embedded GLES2 aquamarine; CM/HDR/motion-blur and glass/fluid blurs removed; blur/shadows/animations off by default; opacity ≥0.98 drawn opaque for fill rate) | ThinkPad X200, GM45, **1280x800**, Omarchy 4 screenshots | runs; x86_64 only so far | VERIFIED source, DOCUMENTED result |
| aquamarine render-node fallback comment | Apple Silicon (split KMS/GPU nodes) | without it "Mesa is forced to llvmpipe and the desktop runs in software" → Hyprland does run on llvmpipe | VERIFIED (`Session.cpp:221-232`) |
| Asahi user with `MESA_GLES_VERSION_OVERRIDE=3.1` crashes Hyprland; Sway fine | Apple GPU | override is not always benign | DOCUMENTED (Hyprland #2276) |
| Hyprland on Pi 5 V3D (hardware) | Cortex-A76 | ~29 fps idle, ~19-20 fps with one Alacritty (old Mesa 23.3) — shows Hyprland can be slow even with a GPU | DOCUMENTED (Gentoo forum) |
| llvmpipe on an ARM Cortex-A7 board | — | glmark2 score 13 (2016, old Mesa) | DOCUMENTED (fdo bug 93570) |
| lima itself | PinePhone/Pinebook (A64, Mali-400 MP2) | dEQP GLES2 97%; tested display drivers include **sun4i-drm**; wlroots-based Phosh/phoc runs on it | VERIFIED (`lima.rst`), phoc DOCUMENTED |
| Hyprland issues for "lima"/"Mali-400"/"Mali-450" | — | **none found** (scoped to two web searches; GitHub issue search API is blocked in this session) | null result, scoped |

---

## Ranked options + experiment order

Ranking is by "how close to real Omarchy" × "chance it works". All are UNCONFIRMED on A33.

1. **Upstream Hyprland 0.56.x on lima + `MESA_GLES_VERSION_OVERRIDE=3.0`.** Real Hyprland, real Omarchy
   4, zero code. Set the env before Hyprland starts. The PR sets it with `hl.env` and reports that this is early
   enough; whether that also covers aquamarine's first context is UNCONFIRMED, so set it in the
   session/uwsm environment as well. Keep blur,
   shadows, rounding off; never pick fluid_jar / motion blur / glass blurs; expect screen-share to fail.
   Risk: hidden ES3 calls lima mis-implements, FP16 artefacts, GL errors in the mirror path.
2. **Hypoland on lima.** GLES2-native, honest about capability, already tuned for weak fill rate, Omarchy-4
   compatible (same Lua config, hyprctl, IPC). Work: change PKGBUILD `arch`/`-march`, build for armv7h,
   possibly fix 32-bit issues. Risk: one-maintainer fork, x86-only testing, lags upstream.
3. **Upstream Hyprland on llvmpipe** (`MESA_LOADER_DRIVER_OVERRIDE=kms_swrast` or no lima). Functionally
   sure (llvmpipe does ES 3.2), visually perfect, but slow: 4× A7 must shade 1 Mpx per full redraw while also
   running clients; scanout buffers are CMA/write-combined, so CPU read-back can be very slow.
   Estimate (UNCONFIRMED): single-digit to low-teens fps on full-screen damage, OK on small damage.
4. **Port upstream shaders/GL calls to GLES2 yourself.** This is what Hypoland did: 19 shaders rewritten to
   `#version 100`, VAO→OES, swizzle→BGRA upload, CM/HDR stripped, aquamarine forked. Only worth it as
   "rebase Hypoland onto newer upstream", not from scratch. Note: a shader-only override via
   `~/hypr/shaders/` does NOT work alone, because the context and GL calls are still ES3.
5. **Sway / SwayFX (wlroots GLES2) with Omarchy theming** (waybar, mako, themes, same keybind ideas).
   Most likely to just work on lima (wlroots GLES2 is the PinePhone stack). SwayFX gives rounded corners,
   shadows, blur on GLES2 (UNCONFIRMED on lima). Not "real Omarchy": Omarchy's scripts and menus talk to
   `hyprctl`. wlroots `WLR_RENDERER=pixman` is the CPU-only fallback.
6. **Hyprland 0.49 legacy renderer** — reject (config/scripts incompatible, see above).

### Experiment order (cheapest first, each with a positive control)

0. **Baseline the stack, not Hyprland.** `drm_info` (atomic? planes? formats), `eglinfo` (GBM platform:
   `OpenGL ES 2.0 Mesa`, extensions list — record whether `GL_EXT_color_buffer_half_float` is there),
   `kmscube` and `glmark2-es2-drm` at 1280x800. This proves lima + sun4i-drm work at all and gives a
   fill-rate number. Positive control for later "Hyprland is slow" claims.
1. **Override at the GL level, no compositor.** `MESA_GLES_VERSION_OVERRIDE=3.0 eglinfo` → must show
   `OpenGL ES 3.0`. Then compile Hyprland's real shader sources (copy `src/render/shaders/glsl/`, run them
   through `glslangValidator -E` like Hyprland does, feed to a tiny GLES3 test or `shader-db`-style runner
   on the board). Record pass/fail per shader. Positive control: the same runner on llvmpipe must pass all.
   Expected fails: fluidjar*, motion blur, acrylic/prism/ripple/water, any `USE_MIRROR` variant.
2. **Get a Hyprland ≥0.55 armv7h build.** No package exists (ALARM stops at 0.49.0). Cross-compile or
   build in an armv7 chroot on a fast host (qemu-user or a real ARM box). Do not build on the 1 GB A33.
3. **Run Hyprland 0.56 with the override**, from a TTY, minimal Lua config (no blur/shadow/rounding/anim),
   `AQ_TRACE=1`, `debug:gl_debugging`. Check: log says "retrying 3.0" then renders; open foot/alacritty;
   measure fps with `debug:overlay`. Then the full Omarchy 4 config. Watch for GL errors and FP16
   artefacts on borders.
4. **In parallel, build Hypoland for armv7h** and run the same test. Compare fps and artefacts with step 3.
   This is also the control for step 3: if both fail the same way, suspect kernel/KMS, not the renderer.
5. **llvmpipe control run** (`MESA_LOADER_DRIVER_OVERRIDE=kms_swrast`): gives the "software" fps floor and
   a known-good image to compare artefacts against.
6. Only if 3–5 all fail: **Sway/SwayFX + Omarchy theming**.

Pick the winner of 3 vs 4 on: (a) stable desktop without GL errors, (b) fps during workspace switch /
window open with animations on, (c) how much of Omarchy's tooling (`hyprctl` scripts, menus) works.

---

## Sources

Local source reads (clones under `scratchpad/repos/`):
- Hyprland 0.56.0 `663b29b8`: `src/render/OpenGL.cpp`, `src/render/ShaderLoader.cpp`, `src/render/shaders/glsl/*`,
  `src/render/gl/GLFramebuffer.cpp`, `GLTexture.cpp`, `src/render/GLRenderer.cpp`, `src/render/Shader.cpp`,
  `src/render/gl/blur/FluidJar.cpp`, `src/Compositor.cpp`, `src/config/values/ConfigValues.cpp`
- Hyprland v0.49.0: `CMakeLists.txt`, `meson_options.txt`, `src/render/OpenGL.cpp`, `src/render/shaders/glsl/`
- aquamarine `52ea11f0`: `src/backend/drm/DRM.cpp`, `src/backend/drm/Renderer.cpp`, `src/backend/Session.cpp`
- Mesa 26.3-devel `1f495287` (mirror https://github.com/chaotic-cx/mesa-mirror): `src/gallium/drivers/lima/lima_screen.c`,
  `lima_program.c`, `ir/pp/nir.c`, `ir/pp/ppir.h`, `src/gallium/auxiliary/util/u_screen.c`,
  `src/mesa/main/version.c`, `context.c`, `context.h`, `extensions.c`, `extensions_table.h`,
  `src/mesa/state_tracker/st_manager.c`, `st_extensions.c`, `src/compiler/glsl/glsl_parser_extras.cpp`,
  `src/compiler/nir/nir_lower_int_to_float.c`, `docs/drivers/lima.rst`
- Linux sun4i: https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/sun4i/sun4i_layer.c , `sun4i_drv.c`, `sun4i_backend.c`, `sun4i_frontend.c`
- Omarchy master + tags v4.0.4 / v3.8.4: https://github.com/basecamp/omarchy (`default/hypr/looknfeel.lua`, `glass.lua`)
- Hypoland: https://github.com/hegjon/hypoland (README, `src/helpers/GLES2Compat.hpp`, `src/render/OpenGL.cpp`, `packaging/arch/PKGBUILD`)

Web:
- https://github.com/omacom/omarchy/pull/14764 (GLES 3.0 override on crocus)
- https://phoronix.com/news/Hyprland-0.50-Released ; https://alternativeto.net/news/2025/7/hyprland-0-50-drops-legacy-renderer-adds-privacy-controls-and-experimental-triple-buffering/
- https://aur.archlinux.org/packages/hyprland-legacyrenderer-git
- https://archlinuxarm.org/packages/armv7h/hyprland (via search snippet; site not reachable)
- https://phoronix.com/news/Hyprland-0.55-Wayland-Comp ; https://hypr.land/news/26_lua/ (via snippet)
- https://github.com/hyprwm/Hyprland/issues/2276 (Asahi override crash)
- https://forums.gentoo.org/viewtopic.php?p=8814560 (Pi 5 Hyprland fps)
- https://bugs.freedesktop.org/show_bug.cgi?id=93570 (llvmpipe on ARM, via snippet)
- https://github.com/wlrfx/swayfx (GLES2 fx_renderer)
