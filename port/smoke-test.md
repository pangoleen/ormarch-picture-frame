# Smoke test: the Omarchy 4 shell stack on 32-bit Arch Linux ARM (armv7h)

Date: 2026-10-12. No hardware. All tests ran in Docker (OrbStack) on an Apple-silicon Mac.
The 32-bit tests ran under QEMU user emulation. The 64-bit control ran natively.

## Answer

| Question | Answer | Tag |
|---|---|---|
| Does Quickshell install on armv7h? | **Yes.** `quickshell 0.3.2-1` is in ALARM armv7h `extra`. We do not need to build it. | [VERIFIED] |
| Does Quickshell start on armv7h? | **Yes.** It loads QML, stays up, draws a layer-shell bar, runs timers and child processes. | [VERIFIED] in QEMU |
| Does the Omarchy **v4.0.4** shell load? | It loads and stays up. **But it has 222 QML errors and no colours.** Cause: Qt 6.12 has a new `Color` type that hides Omarchy's `Color` singleton. This is **not** a 32-bit problem: the 64-bit control has the same 222 errors. | [VERIFIED] |
| Is there a fix? | **Yes, two.** (1) Pin `import QtQuick` to `6.11` in `shell/` → 0 errors. (2) Use upstream `quattro` (commit `defbf90e`, newer than v4.0.4) → 0 errors with the stock Quickshell. | [VERIFIED] |
| Are there errors that are real on 32-bit only? | **None found.** For each run, the armv7l log and the aarch64 log are the same after I remove addresses, PIDs and times. The only differences are timing lines (section 4d). | [VERIFIED], scoped to what the test opened |
| Does Hyprland start? | **Not tested to the end.** `Hyprland --version` runs. Hyprland then stops with `no allocator available`, because the container has no DRM device. The 64-bit control stops at the same line. | [VERIFIED] null result |
| neovim | **Broken on armv7h.** `neovim 0.9.1-1` (built 2023-06-04) cannot be installed: it needs `libtermkey`, which no armv7h repo has. LazyVim needs Neovim ≥ 0.11.2. | [VERIFIED] |
| Memory of the idle shell | Quickshell process only: **220–260 MiB** with a wallpaper scaled to 1280×800 and llvmpipe. **About 410 MiB** with Omarchy's default 6016×3384 wallpaper. **About 105 MiB** with the Qt Quick software backend. The image picker takes it to **over 700 MiB**. See section 5. | QEMU/llvmpipe measurement |

**Recommendation:** fork upstream `quattro` at a commit newer than v4.0.4, not the v4.0.4 tag.
The newer tree has three things that v4.0.4 does not have: the Qt 6.12 fix, limits on the decode size of wallpapers
(the v4.0.4 image picker uses more than 700 MiB), and the aarch64 platform code that `research/04` wants to copy.
Cost: `quattro` has no release tag after v4.0.4, so we pin a commit. [UNCONFIRMED judgement]

## What I ran and what I only read

- **Ran:** all commands in sections 1, 3, 4 and 5. The outputs are in `port/logs/`.
- **Read only:** the Omarchy repo at tag v4.0.4, `omacom/omarchy-pkgs` (PKGBUILDs), the LazyVim source,
  the pacman sync databases of ALARM armv7h, ALARM aarch64, Arch x86_64 and `pkgs.omarchy.org`.
- **Not done:** a test on the frame, a test with the Mali-400 GPU, a full Hyprland session.

Tags in this file: **[VERIFIED]** = I ran it today in the container, or I read it in the source (path given).
It is **not** a test on the frame. **[DOCUMENTED]** = from a second-hand source. **[UNCONFIRMED]** = my inference.

---

## 1. Container recipe

Files: `port/Dockerfile`, `port/run-all.sh` (host), `port/run-shell-test.sh` (in the container).

```sh
# from the project root
git clone --depth 1 --branch v4.0.4 https://github.com/basecamp/omarchy refs/omarchy
# optional, for the comparison runs c3 and c10 (the newer upstream shell):
git -C refs/omarchy fetch --depth 1 origin quattro
mkdir -p refs/omarchy-quattro
git -C refs/omarchy archive FETCH_HEAD shell bin config default/themed default/omarchy version | tar -x -C refs/omarchy-quattro

port/run-all.sh armv7     # 32-bit test, about 25 minutes
port/run-all.sh arm64     # 64-bit control, about 15 minutes
```

`run-all.sh` builds the image (armv7: about 4 minutes and 1.75 GB; arm64: about 1.5 minutes and 2.0 GB),
runs every test, and removes its container. It keeps the image. **I removed both images and their build cache
at the end of this session**, because the disk is short. The script builds them again.
The final form of `run-all.sh` ran end to end on both platforms, except test c10, which I added last and ran by hand with the same command.

| Item | Value |
|---|---|
| Base image | `menci/archlinuxarm:base`, index `sha256:f66f11c5442a9a1d27ebea0190eb79f9a0d654eb2699441ec69ad2fc3c81d54c`, built 2026-10-12 06:57 UTC |
| `linux/arm/v7` manifest | `sha256:9c43138e53ee540e75530308e979cd1e87d87250f569a88521866d5345ebf25b` |
| `linux/arm64` manifest | `sha256:04fa7026ab3979652115a8fea047f50c69fd1a71bc21bd7cb3b3a9aa86a8bb0d` |
| `uname -m` | `armv7l` (test), `aarch64` (control) |
| Kernel | `7.0.14-orbstack` (the OrbStack VM kernel, not an ALARM kernel) |
| pacman | `7.1.0`, repos `core extra alarm aur` from `mirror.archlinuxarm.org/armv7h` |
| Omarchy | tag `v4.0.4` = commit `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` (2026-09-14), mounted read-only at `/omarchy` |
| Newer Omarchy for comparison | branch `quattro` = commit `defbf90e893e741067e48f4a27d2ec694c71358e` (2026-10-12), `shell bin config default` only, in `refs/omarchy-quattro` |

Three things did not work at first. All three are container or emulation artefacts, not armv7h faults:

| Symptom | Cause | Fix in the recipe |
|---|---|---|
| `pacman -Sy`: `restricting filesystem access failed because Landlock is not supported by the kernel!` | pacman 7 puts its downloader in a Landlock sandbox. QEMU user emulation does not pass the Landlock system calls. [UNCONFIRMED: I did not trace the system call] | `pacman --disable-sandbox` |
| `sway: Operation not permitted` | The sway binary has the file capability `cap_sys_nice`. Docker's default capability set does not have it. | `setcap -r /usr/bin/sway` |
| The "arm64" image was `armv7l` | I pinned the image **index** digest. Docker already had the arm/v7 platform of that index and used it for `--platform linux/arm64`. | The Dockerfile pins each **platform manifest** digest. `run-all.sh` prints `uname -m`. |

## 2. Packages

Full table: `port/packages-armv7h.tsv` (239 rows; made by `port/pkgtable.py`).
It joins Omarchy's lists with the ALARM armv7h sync databases (`core`, `extra`, `alarm`, `aur`, read 2026-10-12).
For each package that the index lists, I also asked pacman to resolve its dependencies in the container
(`pacman -S --print <name>`; result in column `armv7h_deps_resolve`, raw output in `port/logs/resolve-armv7h.txt`).

To make the table again: copy `/var/lib/pacman/sync/*.db` out of the armv7h container (as `alarm-armv7h-<repo>.db`),
download the sync databases of Arch x86_64 (`core`, `extra`), ALARM aarch64 and `pkgs.omarchy.org` (`stable/x86_64`, `edge/aarch64`),
then run `python3 -I port/pkgtable.py <omarchy> <omarchy-pkgs> <armv7h db dir> <other db dir> port/logs/resolve-armv7h.txt port/packages-armv7h.tsv`.
The names of the files that the script expects are at the top of the script.

Sources of the names [VERIFIED, read]:
- `install/omarchy-base.packages` at v4.0.4: **147 names** (not 161: `research/04` read `quattro` HEAD).
- `install/omarchy-other.packages`: 55 more names (ISO cache; most are x86 or laptop hardware).
- Hard dependencies of the `omarchy` and `omarchy-settings` packages (`omacom/omarchy-pkgs`, `pkgbuilds/omarchy*/PKGBUILD`).
- Dependencies of Omarchy's own Quickshell build (`pkgbuilds/quickshell/PKGBUILD`).

### Result for the 147 base names

| Status | Count | Meaning |
|---|---|---|
| fine | 116 | In ALARM armv7h, same upstream version as Arch x86_64 (major.minor), dependencies resolve |
| older | 3 | In ALARM armv7h, older than Arch x86_64, dependencies resolve: `fastfetch`, `xournalpp`, `yt-dlp` |
| broken | 1 | In the index, but pacman cannot install it: `kdenlive` |
| missing | 26 | Not in any ALARM armv7h repo |
| n/a | 1 | `asdcontrol` (Apple display) |

Of 176 names that the armv7h index has (all lists), **174 resolve** and **2 do not**: `neovim` and `kdenlive`.

### Minimum versions that Omarchy states

Omarchy states very few. [VERIFIED, read]

| Package | What Omarchy needs | Where | ALARM armv7h | Result |
|---|---|---|---|---|
| hyprland | Lua config (≥ 0.55). `omarchy-hyprland-titlebars` pins `=0.56.2`. | `config/hypr/hyprland.lua`; `pkgbuilds/omarchy-hyprland-titlebars/PKGBUILD` | 0.56.2-4 | fine |
| quickshell | Omarchy builds `0.3.2-4` with `load_qtquick_611.patch`. The v4.0.4 shell does **not** use the patch (no `//@ pragma OmarchyLoadPatch` in `shell/shell.qml`). | `pkgbuilds/quickshell/PKGBUILD` | 0.3.2-1 (same as Arch x86_64 and ALARM aarch64) | fine; see section 4c |
| Qt 6 | No stated version. The v4.0.4 shell was written before Qt 6.12 (Arch got 6.12 on 2026-09-30; the tag is from 2026-09-14). | sync databases | 6.12.0 | **breaks the v4.0.4 shell colours**; see 4c |
| neovim | `omarchy-nvim` says `neovim>=0.9.0`. But its build uses the LazyVim starter `main`, and LazyVim (16.0.1) stops at start if Neovim < 0.11.2. | `pkgbuilds/omarchy-nvim/PKGBUILD:9`; LazyVim `lua/lazyvim/plugins/init.lua:1-9` | 0.9.1-1 | **too old and not installable** |
| omarchy-settings | `=4.0.4` (same build as `omarchy`) | `pkgbuilds/omarchy/PKGBUILD` | none | build ourselves |

### Missing or broken, with the action

| Package | Why | Action |
|---|---|---|
| `omarchy`, `omarchy-settings`, `omarchy-keyring` | Omarchy builds only x86_64 and aarch64 | **Build ourselves** |
| `neovim` (list name `nvim`) | 0.9.1-1 from 2023; needs `libtermkey`, not in any armv7h repo. Arch x86_64 and ALARM aarch64 have 0.12.6. Why the armv7h build stopped in 2023: not known. | **Build neovim ≥ 0.11.2 ourselves**, or drop the editor setup. `helix 25.07.1`, `vim 9.2`, `micro`, `nano` install. |
| `omarchy-nvim` | Needs a working neovim | Drop until then |
| `chromium` | ALARM builds it for aarch64 only (`buildarch=8`) | **Replace with `firefox 157.0-1`** (in `extra`, resolves, 272 MiB). 36 files in the repo name chromium; `omarchy-launch-webapp` uses Chromium `--app`; `mimeapps.list` points to `chromium.desktop`. |
| `ttf-jetbrains-mono-nerd-basic` | Omarchy package (`any`) | Use `ttf-jetbrains-mono-nerd 3.5.1-2` from `extra` (the test used it), or build |
| `yaru-icon-theme`, `ttf-ia-writer` | Omarchy packages (`any`) | Build (trivial) |
| `yay` | Not in ALARM | Build (Go), or drop |
| `mise-bin` | Omarchy/AUR: x86_64 and aarch64 only | Wrap the upstream `linux-armv7` binary [DOCUMENTED in research/04], or drop |
| `ufw-docker` | Omarchy package | Drop with docker |
| `hyprland-preview-share-picker` | Omarchy package (Rust) | Drop; remove its line in `config/hypr/xdph.conf` |
| `omacalc`, `omawrite`, `ttfx`, `tzupdate`, `tensaku` | Omarchy packages (Qt6 C++ or Rust) | Optional builds |
| `aether`, `cliamp`, `herdr`, `localsend`, `obsidian`, `obs-studio`, `pinta`, `dotnet-runtime`, `omacut`, `tobi-try`, `qemu-user-static-binfmt`, `asdcontrol` | No armv7h build, and no use on a photo frame | Drop |
| `kdenlive` | 23.08.5 from 2024; needs `kfilemetadata5` and `purpose5`, not in armv7h | Drop |
| `wvkbd`, `hyprgrass`, `kmscube` | Not in `core`, `extra`, `alarm` or `aur` | Build. Note: **`squeekboard 1.43.1-6` is in armv7h `extra`** (another on-screen keyboard). |

Nothing in the list pulls in an x86-only binary on armv7h without a clear failure: a missing package stops pacman.
Chromium is the only missing package that the Omarchy scripts need in many places.

### Corrections to `research/04` (index facts, [VERIFIED])

| research/04 said | The armv7h index says |
|---|---|
| Quickshell: no armv7h package, build it | `extra/quickshell 0.3.2-1`, built 2026-10-09 |
| plymouth: maybe not on armv7h | `extra/plymouth 26.134.222-3` |
| squeekboard: aarch64 only | `extra/squeekboard 1.43.1-6` |
| hyprlock, hypridle: no armv7h page | `extra/hyprlock 0.9.6-3`, `extra/hypridle 0.1.8-2` |
| xdg-terminal-exec: build from AUR | `extra/xdg-terminal-exec 0.14.3-2` |
| neovim: in ALARM (not checked) | In the index, but old and not installable |
| `bin/omarchy-hw-platform`, `omarchy-pkg-defaults`, aarch64 pacman files | **Not in tag v4.0.4.** They are in `quattro` HEAD only. At v4.0.4, `install/post-install/pacman.sh` copies the x86 `pacman.conf` with no architecture check at all. |

## 3. Install result

```
pacman -S --needed --noconfirm --disable-sandbox quickshell hyprland foot mesa
Packages (134) ...
Total Download Size:   165.20 MiB
Total Installed Size:  664.30 MiB
```

- Exit status 0. No dependency failure. No scriptlet error. Time: 1 min 37 s under QEMU. [VERIFIED]
- Largest packages: `llvm-libs` 158 MiB, `qt6-declarative` 113 MiB, `qt6-base` 65 MiB, `hyprland` 63 MiB, `mesa` 60 MiB.
- The base image is 579 MiB (137 packages). The full test image is 1836 MiB (it also has sway, PipeWire,
  a Nerd font, Python, ImageMagick and git for the test).
- Qt 6 packages that came in: `qt6-base`, `qt6-declarative`, `qt6-svg`, `qt6-wayland`, `qt6-translations` (all 6.12.0).

## 4. Run-time tests

Every command below ran as the user `frame` with `XDG_RUNTIME_DIR=/run/user/1000`.

### 4a. Versions

```
$ quickshell --version
Quickshell 0.3.2 (revision , distributed by Arch Linux)

$ Hyprland --version
Hyprland 0.56.2 built from branch v0.56.2 at commit efb50993780079460b0cbed1363e2166a2de1d9f clean
Libraries: Hyprgraphics 0.5.1, Hyprutils 0.14.2, Hyprcursor 0.1.13, Hyprlang 0.6.8, Aquamarine 0.15.1

$ file -b /usr/bin/quickshell
ELF 32-bit LSB pie executable, ARM, EABI5 version 1 (GNU/Linux), dynamically linked, interpreter /lib/ld-linux-armhf.so.3

$ foot --version
foot version: 1.28.0 (Sep 08 2026, branch 'makepkg') +pgo +ime +graphemes +toplevel-tag +blur -assertions

$ quickshell --private-check-compat     # the check that Omarchy's pacman hook runs after a Qt update
(exit status 0)
```

`Hyprland --version` aborts with `XDG_RUNTIME_DIR is not set!` if that variable is missing. Log: `logs/armv7l-versions.txt`.
foot also opens a window in the headless compositor (`logs/armv7l-foot.png`).

### 4b. Trivial QML

**Offscreen, no compositor** (`port/qml-trivial/shell.qml`: a `FloatingWindow`, a 1 s `Timer`, a `Process` that runs `uname -m`):

```
$ QT_QPA_PLATFORM=offscreen timeout 20 quickshell -p /port/qml-trivial/shell.qml
  INFO: Configuration Loaded
  WARN: This plugin does not support setting window masks
 DEBUG qml: uname -m = armv7l
 DEBUG qml: tick 1 now 1791806419775 big 9007199254740991 maxint 2147483648
 ... (one line each second) ...
exit status 124   (still running when the timeout stopped it)
```

**Layer-shell bar on a headless compositor** (`port/qml-trivial/panel.qml`: a `PanelWindow` with a clock):

```
$ WLR_BACKENDS=headless WLR_RENDERER=pixman sway &          # one 1280x800 output
$ QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 QSG_INFO=1 quickshell -n -p /port/qml-trivial/panel.qml
  INFO: Configuration Loaded
 DEBUG qt.rhi.general: OpenGL VENDOR: Mesa RENDERER: llvmpipe (LLVM 23.1.1, 128 bits) VERSION: 4.6 (Compatibility Profile) Mesa 26.2.4-arch1.1
 DEBUG qml: bar 1280x32 screen HEADLESS-1 api 3 gl 4.6 renderableType 1
# RESULT: quickshell still running after 33 s; stopping it with SIGTERM
```

The screenshot `logs/armv7l-trivial-panel.png` shows the bar with the clock. [VERIFIED]

Note: on llvmpipe, Qt asks for **desktop OpenGL** and gets 4.6. On the Mali-400 (lima) it will get
OpenGL 2.1 or OpenGL ES 2.0. That path is not tested here. See test c6 for a first look.

### 4c. The real Omarchy shell

Session pieces that the test has: a D-Bus session bus, an empty D-Bus system bus, PipeWire, WirePlumber,
headless sway (layer-shell, session-lock), the user config copied from `config/`, and the theme "Tokyo Night"
applied by Omarchy's own `omarchy-theme-set` (it runs on armv7h; one error: `/usr/bin/omarchy-theme-set-browser-policy` is not there, because Omarchy is not installed as a package).

Command (in `run-shell-test.sh`):

```
OMARCHY_PATH=<tree> PATH=<tree>/bin:$PATH QS_DISABLE_FILE_WATCHER=1 QS_NO_RELOAD_POPUP=1 \
  quickshell -n -p <tree>/shell        # the same line as bin/omarchy-launch-shell, without systemd-cat
```

| Run | Tree | Lines | "undefined" errors | Other WARN/ERROR | Result after 75 s |
|---|---|---|---|---|---|
| c1 | v4.0.4, not changed | 242 | **222** | 6 | still running |
| c2 | v4.0.4, `import QtQuick` → `import QtQuick 6.11` in 102 files | 20 | **0** | 6 | still running |
| c3 | `quattro` `defbf90e`, not changed, stock Quickshell | 87 | **0** | 10 + 62 × GlobalShortcut | still running |

**c1, the 222 errors.** All are of this form:

```
WARN scene: @plugins/bar/Bar.qml[81:-1]: TypeError: Cannot read property 'active' of undefined
WARN scene: @plugins/bar/Bar.qml[75:3]: Unable to assign [undefined] to QColor
```

Cause [VERIFIED]: Omarchy has a singleton `Color` (`shell/Commons/Color.qml`, module `qs.Commons`).
Qt 6.12 added its own singleton `QtQuick/Color 6.12` (`/usr/lib/qt6/qml/QtQuick/plugins.qmltypes`: `name: "QQuickColor"`, `exports: ["QtQuick/Color 6.12"]`).
In a file that imports both, `Color` is now the Qt one. `Color.bar` is then `undefined`.
A 12-line test shows it (`port/qml-trivial/colortest/`):

```
import QtQuick       -> Color = QQuickColor(0x43abfa08) | Color.background = undefined | verdict: SHADOWED by QtQuick.Color
import QtQuick 6.11  -> Color = Color_QMLTYPE_0(...)    | Color.background = #101315   | verdict: config singleton wins
```

Effect on screen: the wallpaper shows, the bar is a black strip with no widgets (`logs/armv7l-omarchy-v4.0.4-stock.jpg`).

**c2, the fix.** `port/make-pinned-tree.sh` makes the same text change that Omarchy's own Quickshell patch makes at load time
(`omarchy-pkgs/pkgbuilds/quickshell/load_qtquick_611.patch`, comment: "Qt 6.12 added a QtQuick Color singleton which shadows Omarchy's Color singleton").
Result: 0 errors. The bar shows workspaces 1–5, the clock, the weather icon and the network, audio and monitor icons (`logs/armv7l-omarchy-v4.0.4-qtquick611.jpg`).

**c3, upstream's fix.** `quattro` HEAD uses `Commons.Color` and has `//@ pragma OmarchyLoadPatch`.
The stock ALARM Quickshell prints `WARN: Unrecognized pragma "OmarchyLoadPatch"` and then loads the shell with 0 colour errors.
So Omarchy's patched Quickshell is **not** needed for the newer tree. [VERIFIED for load and idle]

**Errors that stay in c2, and their class:**

| Message | Class |
|---|---|
| `$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.` | No session: the compositor is sway, not Hyprland |
| `The active compositor does not support hyprland_global_shortcuts_v1` (c3 only, 31 times) | No session: same |
| `Failed to register with host portal ... org.freedesktop.portal.Desktop` | No session: no xdg-desktop-portal |
| `Failed to create DBusObjectManagerInterface for "org.bluez"` | No session: no BlueZ daemon |
| `quickshell.network: Network will not work. Could not find an available backend.` | No session: no NetworkManager |
| `polkit.listener: failed to create subject for listener: No session for pid N` | No session: no logind |
| `Could not start PowerProfilesDaemon` (c3 only) | No session: no power-profiles-daemon |
| `Binding loop detected for property "opened"` (power panel) and `"displayCutouts"` (c3) | Omarchy QML, also on 64-bit |

**Real on 32-bit:** none. No crash, no missing QML module, no integer-size error.
All Quickshell modules that the shell imports are in the ALARM build: `Quickshell`, `.Io`, `.Wayland`, `.Hyprland`,
`.Bluetooth`, `.Networking`, `.Services.Pipewire`, `.Services.UPower`, `.Services.Mpris`, `.Services.SystemTray`,
`.Services.Polkit`, `.Services.Pam`, `.Services.Notifications`. [VERIFIED: `ls /usr/lib/qt6/qml/Quickshell`, and no import error in the logs]

**More tests on the pinned v4.0.4 tree:**

| Run | What | Result |
|---|---|---|
| c4 | Wallpaper scaled to 1280×800 first | 0 errors; memory falls by 150–185 MiB (section 5) |
| c5 | c4 + `QT_QUICK_BACKEND=software` (no OpenGL in the shell) | 0 errors; bar and wallpaper draw; memory falls again. Effects (blur, shadows in `MultiEffect`) do not work in this backend [DOCUMENTED Qt behaviour, not looked at here] |
| c6 | c4 + `MESA_GL_VERSION_OVERRIDE=2.1 MESA_GLSL_VERSION_OVERRIDE=120` | Qt makes an OpenGL 2.1 context; 0 shader errors at idle; bar and wallpaper draw. llvmpipe still does the work, so this is **not** a Mali-400 test [UNCONFIRMED for the frame] |
| c7 | Open the menu through IPC (`omarchy-shell shell summon omarchy.menu '{"menu":"root"}'`) | The menu draws: Apps, Learn, Trigger, Style, Setup, Install, Remove, Update, About, System (`logs/armv7l-omarchy-v4.0.4-qtquick611-menu.menu.jpg`) |
| c8 | Open the 19 plugins that take a `summon` through IPC, one `notify-send`, then the lock | Each `summon` returns `ok` (2 return `unknown`: tailscale and dropbox have no bar widget). The notification draws (`logs/armv7l-omarchy-v4.0.4-qtquick611-ipc.notification.jpg`). No new QML error. Lock returns `missing-pam`: the lock needs the PAM file that `omarchy-apply-lock` installs as root. Lock screen **not tested**. |
| c8 | IPC timing | With the default 2 s limit, 4 of the 38 `summon` and `hide` calls print `omarchy-shell is not responding` under QEMU (in the last run: `hide` of monitor, speedtest, image-picker, dev-gallery). On the native 64-bit control none do. This is slowness, not a fault. The A33 is also slow, so set `OMARCHY_SHELL_IPC_TIMEOUT` higher on the frame. [UNCONFIRMED for the frame] |

### 4d. Control on 64-bit ARM

The same image recipe and the same tests ran with `--platform linux/arm64` (native on the Mac).
Package versions are the same (Quickshell 0.3.2-1, Qt 6.12.0, Mesa 26.2.4, Hyprland 0.56.2-4), except `wireplumber` (0.5.18 against 0.5.13).

| Test | armv7l (QEMU) | aarch64 (native) |
|---|---|---|
| Trivial QML, offscreen and layer-shell | runs | runs |
| `Color` hidden by Qt 6.12 | yes | yes |
| c1 errors | 222 | 222 |
| c2 errors | 0 | 0 |
| c3 errors | 0 | 0 |
| Log difference, runs c2, c3, c4, c5, c7 (addresses, PIDs, times removed) | — | **none** (0 lines) |
| Log difference, run c1 | — | 1 line: one more D-Bus warning on aarch64 (`name 'org.freedesktop.UPower' had owner ''`, a timing effect) |
| Log difference, run c6 | — | 3 lines: the shader cache path has the ABI name in it; one vsync debug line |
| Log difference, runs c8, c9 | 4 debug lines more: the idle monitor reached "idle" because the run is longer under QEMU | — |
| IPC `not responding` | 4 of 38 calls | none |
| Hyprland | stops: no allocator | stops: no allocator (same lines) |
| Image picker memory at v4.0.4 | +449 MiB kept | +473 MiB kept |

Conclusion: every QML error and every start failure in this test also happens on 64-bit. None is caused by 32-bit. [VERIFIED]
The two things that are different on armv7h are the IPC time-outs (emulation speed) and the two packages that do not install (section 2).

### 4e. Hyprland under llvmpipe (software-rendering control only)

**Hyprland did not start in the container. This is a null result for the container, not for armv7h.**
Script: `port/hyprland-try.sh`. Log: `logs/armv7l-hyprland-headless.log`.

```
$ ls /dev/dri
ls: cannot access '/dev/dri': No such file or directory
$ LIBGL_ALWAYS_SOFTWARE=1 HYPRLAND_TRACE=1 AQ_TRACE=1 Hyprland --config ~/.config/hypr.test/hyprland.lua
DEBUG ]: [cfg] Config is lua, loading lua mgr
ERR from aquamarine ]: libseat: failed to open a seat
ERR from aquamarine ]: DRM Backend failed
ERR from aquamarine ]: Wayland backend cannot start: wl_display_connect failed (is a wayland compositor running?)
CRIT from aquamarine ]: Cannot open backend: no allocator available
CRIT ]: m_pAqBackend couldn't start! This usually means aquamarine could not find a GPU ...
terminate called after throwing an instance of 'std::runtime_error'   what():  CBackend::create() failed!
```

- With `HYPRLAND_HEADLESS_ONLY=1`: the same lines.
- Nested in headless sway: `Wayland backend cannot start: Missing protocols`, then the same `no allocator available`.
- The 64-bit control gives the same lines.
- Cause: aquamarine makes its buffer allocator from a DRM device. The OrbStack VM kernel has no DRM device (`/dev/dri` is not there, also in a `--privileged` container). [VERIFIED]
- What this does show: the armv7h Hyprland 0.56.2 binary runs, reads a **Lua** config, and gets as far as the backend. [VERIFIED]

So there is **no Hyprland GL version line**. What I can give is Mesa's own answer on armv7h, with no Hyprland involved:

```
$ LIBGL_ALWAYS_SOFTWARE=1 eglinfo -B -p surfaceless
OpenGL ES profile renderer: llvmpipe (LLVM 23.1.1, 128 bits)
OpenGL ES profile version: OpenGL ES 3.2 Mesa 26.2.4-arch1.1
OpenGL ES profile shading language version: OpenGL ES GLSL ES 3.20
--- with MESA_GLES_VERSION_OVERRIDE=3.0
OpenGL ES profile version: OpenGL ES 3.0 Mesa 26.2.4-arch1.1      (GLSL ES 3.00)
--- with MESA_GLES_VERSION_OVERRIDE=2.0
OpenGL ES profile version: OpenGL ES 2.0 Mesa 26.2.4-arch1.1      (GLSL ES 1.0.16)
```

- llvmpipe on armv7h gives OpenGL ES 3.2, so Hyprland's request (3.2, then 3.0) can be met in software. [VERIFIED for Mesa; UNCONFIRMED for Hyprland, because Hyprland did not start]
- `MESA_GLES_VERSION_OVERRIDE` changes what Mesa reports, as expected. On llvmpipe `=3.0` only lowers a version that is already there.
  It says nothing about lima. **This is only the software-rendering control for the later GPU test.**
- Whether `MESA_GLES_VERSION_OVERRIDE=3.0` changes Hyprland's behaviour: **not tested.**

## 5. Memory

**All numbers are from QEMU user emulation (armv7l) or a native 64-bit run (aarch64), with Mesa llvmpipe, on a headless
1280×800 output, with no Hyprland. They are rough numbers for the 1 GB budget, not frame numbers.**

Method: `/proc/<pid>/smaps` of the Quickshell process, 8 s before the end of each run (`port/mem-from-smaps.py`).
Under QEMU, `/proc/<pid>` is the `qemu-arm` process. The 32-bit program lives below 4 GiB; QEMU's own memory
(128 MiB translated-code buffer and more) is above 4 GiB. I count only the part below 4 GiB as "program".

| Run (Quickshell process only) | armv7l program RSS | armv7l PSS | armv7l anonymous | armv7l libLLVM+gallium | QEMU part (not counted) | aarch64 native RSS | aarch64 anonymous |
|---|---|---|---|---|---|---|---|
| Trivial bar (b2) | **197** | 192 | 90 | 58 | 159 | 218 | 102 |
| c1: v4.0.4, not changed (222 errors) | **420** | 405 | 288 | 58 | 166 | 451 | 322 |
| c2: v4.0.4 pinned, default 6016×3384 wallpaper | **408** | 393 | 283 | 54 | 163 | 441 | 316 |
| c3: quattro `defbf90e`, default wallpaper | **294** | 279 | 164 | 56 | 155 | 354 | 204 |
| c4: v4.0.4 pinned, 1280×800 wallpaper | **260** | 245 | 135 | 54 | 163 | 305 | 167 |
| c6: c4 with OpenGL 2.1 reported | **271** | 258 | 139 | 58 | 166 | 319 | 176 |
| c5: c4 with Qt Quick software backend | **105** | 94 | 39 | 0 | 121 | 137 | 60 |
| c7: c4 after the menu and one panel opened and closed | **270** | 255 | 145 | 48 | 164 | 321 | 182 |
| c8: c4 after all 19 plugins opened and closed | **730** | 713 | 639 | 30 | 155 | 831 | 691 |

All values in MiB.

Memory by plugin at v4.0.4 (test c9, `logs/*-omarchy-v4.0.4-qtquick611-plugin-mem.hook.log`; anonymous memory of the whole process, so the armv7l values include QEMU):

| Step | armv7l (with QEMU) | aarch64 native |
|---|---|---|
| Idle before the test | 323 MiB | 168 MiB |
| Any panel or the menu, while open | +50 to +80 MiB | +30 to +90 MiB |
| The same, after it closes | back to the idle value ±40 MiB | back to the idle value ±40 MiB |
| `omarchy.image-picker`, while open | 506 MiB after 3 s, still loading | **1257 MiB** |
| `omarchy.image-picker`, after it closes | **805 MiB** (+449) | **710 MiB** (+473) |

Two runs of c4 gave 222 MiB and 260 MiB on armv7l. Read every value as ±20 %.

What the numbers say:

1. **The default wallpaper costs 150–185 MiB.** `0-winding-road.jpg` is 6016×3384. Decoded it is 81 MiB, and the
   process holds two anonymous mappings of about 80 MiB each (the image and the llvmpipe texture).
   `shell/plugins/background/Background.qml:221-227` has no `sourceSize`, so Qt decodes at full size. [VERIFIED]
   Fix for the frame: scale every wallpaper to 1280×800 at install time.
   Also: the Mali-400 has a maximum texture size of 4096 [UNCONFIRMED for lima on this board], so a 6016-wide texture cannot upload as it is.
2. **llvmpipe costs about 55–65 MiB of file pages** (`libLLVM.so` 161 MiB mapped, `libgallium`) plus JIT memory, in each process that draws with it.
3. **The v4.0.4 image picker is a memory trap.** Opening `omarchy.image-picker` once takes the shell's anonymous memory
   from about 240 MiB to about 1250 MiB on the 64-bit control, and about 470 MiB stays after it closes. The armv7l run keeps about 450 MiB.
   Other panels add 50–80 MiB while open and give it back.
   Cause: `shell/plugins/image-picker/ImagePicker.qml` at v4.0.4 has no `sourceSize`, so it decodes 6K images at full size. [VERIFIED: grep]
   On a 1 GB frame it will probably run out of memory. [UNCONFIRMED on the frame]
4. **Upstream fixed both after v4.0.4.** In `quattro` `defbf90e`, `Background.qml:433-434` and `ImagePicker.qml:800-801` set `sourceSize`. [VERIFIED: read]
   Measured: idle shell 294 MiB against 408 MiB with the same default wallpaper (c3 against c2).
   Image picker on `quattro`: +15 MiB kept after close on aarch64, +25 MiB on armv7l (against +473 and +449 at v4.0.4).
   Logs: `logs/*-omarchy-quattro-stock-plugin-mem.hook.log`.
5. **32-bit uses less than 64-bit**, as expected: about 7–25 % less for the same run.
6. The other session processes are small: PipeWire about 5–10 MiB, WirePlumber about 20–28 MiB (64-bit native PSS; the armv7l values include QEMU).

Not measured: Hyprland, Xwayland, the portals, SDDM, Firefox. The total for an idle session is still an estimate.

## 6. Verdict

### Proven to work on armv7h (in the QEMU container)

- `pacman` installs `quickshell`, `hyprland`, `foot`, `mesa` and Qt 6.12 with no dependency failure. [VERIFIED]
- Quickshell 0.3.2 loads QML, makes layer-shell windows, runs timers, child processes, IPC, D-Bus services and PipeWire. [VERIFIED]
- The Omarchy shell (bar, background, menu, notifications, OSD, panels) loads and draws, if the Qt 6.12 `Color` clash is fixed. [VERIFIED]
- Omarchy's Bash tools that the test used run: `omarchy-theme-set`, `omarchy-shell`, the bar helper scripts. [VERIFIED]
- foot starts and draws. Hyprland 0.56.2 starts, reads a Lua config, and reaches the backend. [VERIFIED]
- Mesa llvmpipe gives OpenGL ES 3.2 and desktop OpenGL 4.6 on armv7h. [VERIFIED]

### Fails, and why

| What | Why | 32-bit fault? |
|---|---|---|
| Omarchy v4.0.4 shell colours (222 errors) | Qt 6.12 `Color` singleton hides Omarchy's | No. Same on aarch64. |
| Hyprland start in the container | No DRM device, so aquamarine has no allocator | No. Same on aarch64. |
| `neovim` install | Package from 2023 needs `libtermkey`, which is gone | Yes: an ALARM armv7h packaging fault |
| `kdenlive` install | Package from 2024 needs KF5 libraries, which are gone | Yes: same class. Not needed. |
| Lock screen | Needs the PAM file from the installer (`omarchy-apply-lock`, root) | Not tested |
| Some IPC calls time out at 2 s | QEMU is slow | No. Timing. |

### What we must build or replace

| Need | Packages |
|---|---|
| **Must build** | `omarchy`, `omarchy-settings`, `omarchy-keyring` (from a tree newer than v4.0.4, or v4.0.4 with the QtQuick 6.11 pin) |
| **Must replace** | `chromium` → `firefox`; `ttf-jetbrains-mono-nerd-basic` → `ttf-jetbrains-mono-nerd` |
| **Build for touch** | `wvkbd` (or use `squeekboard` from `extra`), `hyprgrass` |
| **Build if wanted** | `neovim` ≥ 0.11.2 + `omarchy-nvim`, `yay`, `mise-bin`, `yaru-icon-theme`, `ttf-ia-writer`, `omacalc`, `omawrite`, `ttfx`, `tzupdate`, `kmscube` |
| **No build needed** (was on the build list in research/04) | `quickshell`, `xdg-terminal-exec`, `plymouth` |
| **Drop** | `aether`, `cliamp`, `herdr`, `localsend`, `obsidian`, `obs-studio`, `pinta`, `dotnet-runtime`, `omacut`, `kdenlive`, `tobi-try`, `tensaku`, `qemu-user-static-binfmt`, `asdcontrol`, `ufw-docker`, `hyprland-preview-share-picker` |

### Frame-specific changes that this test found

1. Scale wallpapers to 1280×800 when a theme is installed (needed at v4.0.4; still saves disk space on the newer tree).
2. At v4.0.4: turn off the image picker (`omarchy.image-picker`). On the newer tree it is fixed.
3. Raise `OMARCHY_SHELL_IPC_TIMEOUT` above the default 2 s.
4. Do not copy `default/pacman/pacman-stable.conf` over `/etc/pacman.conf` (v4.0.4 does that with no check).

## 7. Not tested

- Anything on the frame. Anything with the Mali-400 and lima. Quickshell on a real OpenGL ES 2.0 driver.
- A complete Hyprland session: Hyprland IPC, workspaces widget data, global shortcuts, `hyprctl`, the Lua config of Omarchy.
- The Hyprland GL version line and the effect of `MESA_GLES_VERSION_OVERRIDE=3.0` on Hyprland.
  Next step for this: a QEMU **system** VM (`qemu-system-arm -M virt` with `virtio-gpu`, ALARM `linux-armv7` kernel), or the frame itself.
- The lock screen (PAM), the polkit agent (needs logind), SDDM, uwsm, the portals.
- The network, Bluetooth, battery and power-profile widgets with real daemons.
- Blur, shadows and video backgrounds. Frame rate. Start time on a Cortex-A7.
- The Omarchy installer scripts (`omarchy-apply-system`, `omarchy-provision-user`). Only the package lists were read.
- Firefox. It is in the index and its dependencies resolve; I did not install or start it.
- A build of any missing package.

## 8. Files

| File | What |
|---|---|
| `port/smoke-test.md` | This report |
| `port/packages-armv7h.tsv` | One line per Omarchy package: required version, ALARM repo and version, build date, install check, status, action |
| `port/Dockerfile` | The test image, for `linux/arm/v7` and `linux/arm64` |
| `port/run-all.sh` | Host script: builds the image, runs every test, writes `port/logs/` |
| `port/run-shell-test.sh` | In-container script: one Quickshell run in a headless session, with memory sample and screenshot |
| `port/make-pinned-tree.sh` | Makes the Omarchy tree with `import QtQuick 6.11` |
| `port/hyprland-try.sh` | The three Hyprland start attempts and the llvmpipe version lines |
| `port/ipc-menu.sh`, `port/ipc-exercise.sh`, `port/ipc-mem-per-plugin.sh` | IPC hooks for tests c7, c8, c9 and c10 |
| `port/mem-from-smaps.py` | Splits a smaps dump into program part and QEMU part |
| `port/pkgtable.py` | Makes the TSV from the sync databases |
| `port/qml-trivial/` | The trivial QML configs and the `Color` test |
| `port/logs/` | Logs, memory samples and screenshots, prefix `armv7l-` (test) and `aarch64-` (control). I kept seven armv7l screenshots as JPEG and deleted the other large PNG files (1.9 MB left). A new run writes PNG files again. |
