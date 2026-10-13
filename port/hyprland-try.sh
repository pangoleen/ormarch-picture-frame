#!/bin/bash
# Try to start Hyprland with no display hardware, three ways. Run inside the test container as "frame".
# Expected in a container: all three fail, because aquamarine needs a DRM device for its buffer allocator.
# Also prints what Mesa llvmpipe gives for OpenGL ES, with and without MESA_GLES_VERSION_OVERRIDE.
export XDG_RUNTIME_DIR=/run/user/$(id -u) NO_COLOR=1 LIBGL_ALWAYS_SOFTWARE=1
cd "$HOME"
mkdir -p ~/.config/hypr.test
echo 'hl.config({ debug = { enable_stdout_logs = true, disable_logs = false } })' > ~/.config/hypr.test/hyprland.lua
filter() { sed -E 's/\x1b\[[0-9;]*m//g' | grep -v -E 'Creating the|^ +[a-zA-Z]+( +[a-zA-Z]+)? *$|^$' | tail -n 30; }

echo "### uname -m: $(uname -m); /dev/dri: $(ls /dev/dri 2>&1)"

echo; echo "### 1. Hyprland, no parent compositor (DRM backend, then fallbacks)"
HYPRLAND_TRACE=1 AQ_TRACE=1 timeout 30 Hyprland --config ~/.config/hypr.test/hyprland.lua 2>&1 | filter
echo "# exit status: ${PIPESTATUS[0]}"

echo; echo "### 2. Hyprland with HYPRLAND_HEADLESS_ONLY=1"
HYPRLAND_HEADLESS_ONLY=1 HYPRLAND_TRACE=1 AQ_TRACE=1 timeout 30 Hyprland --config ~/.config/hypr.test/hyprland.lua 2>&1 | filter
echo "# exit status: ${PIPESTATUS[0]}"

echo; echo "### 3. Hyprland nested in headless sway (aquamarine Wayland backend)"
pkill -u "$(id -u)" -x sway 2>/dev/null; rm -f "$XDG_RUNTIME_DIR"/wayland-*
mkdir -p ~/.config/sway; echo 'output HEADLESS-1 resolution 1280x800' > ~/.config/sway/config
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway >/dev/null 2>&1 &
for _ in $(seq 1 40); do [[ -S $XDG_RUNTIME_DIR/wayland-1 ]] && break; sleep 0.5; done
WAYLAND_DISPLAY=wayland-1 HYPRLAND_TRACE=1 AQ_TRACE=1 timeout 30 Hyprland --config ~/.config/hypr.test/hyprland.lua 2>&1 | filter
echo "# exit status: ${PIPESTATUS[0]}"
pkill -u "$(id -u)" -x sway 2>/dev/null

echo; echo "### 4. Mesa llvmpipe, EGL surfaceless platform: OpenGL ES version (no Hyprland involved)"
eglinfo -B -p surfaceless 2>&1 | grep -E 'OpenGL ES profile (vendor|renderer|version|shading)' | sort -u
echo "--- with MESA_GLES_VERSION_OVERRIDE=3.0"
MESA_GLES_VERSION_OVERRIDE=3.0 eglinfo -B -p surfaceless 2>&1 | grep -E 'OpenGL ES profile (version|shading)' | sort -u
echo "--- with MESA_GLES_VERSION_OVERRIDE=2.0"
MESA_GLES_VERSION_OVERRIDE=2.0 eglinfo -B -p surfaceless 2>&1 | grep -E 'OpenGL ES profile (version|shading)' | sort -u
