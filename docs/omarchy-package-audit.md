# Omarchy package audit — 2026-10-12

This compares the live frame's Pacman database with the pinned Omarchy tree at
`defbf90e893e741067e48f4a27d2ec694c71358e`.

The frame is `armv7h`. Omarchy provides default package profiles for `x86_64`
and `aarch64`, but none for `armv7`; its `omarchy-pkg-defaults` command refuses
this architecture. Therefore this is a comparison against
`install/omarchy-base.packages`, not a claim that every missing package is
available or sensible on the frame. In particular, Chromium is absent from the
configured armv7 repository. Do not run Omarchy's upstream bulk reinstall
command on this device.

## Result

- Omarchy base-manifest entries: **161**
- Already present on the live frame: **49**
- Not installed from that manifest: **112**

This lists direct package names only. Pacman also installs their dependencies,
so it is not an inventory of every installed package on the system.

## Base-manifest packages already installed

```text
avahi
bluez
bluez-tools
bluez-utils
brightnessctl
btop
dosfstools
fastfetch
ffmpeg
fontconfig
foot
git
grim
gum
hyprland
hyprland-guiutils
hyprsunset
imagemagick
imv
inotify-tools
jq
less
libsecret
libyaml
mpv
nautilus
networkmanager
noto-fonts
noto-fonts-emoji
power-profiles-daemon
python-gobject
qt6-base
qt6-declarative
qt6-imageformats
qt6-multimedia
qt6-svg
qt6-wayland
quickshell
ripgrep
socat
udiskie
uwsm
wireless-regdb
wireplumber
wl-clipboard
wtype
xdg-desktop-portal-gtk
xdg-desktop-portal-hyprland
xdg-terminal-exec
```

## Base-manifest packages not installed

```text
aether
alsa-utils
asdcontrol
base-devel
bash-completion
bat
bolt
chromium
cliamp
cups
cups-filters
cups-pk-helper
ddcutil
disktree-bin
docker
docker-buildx
docker-compose
dotnet-runtime
evince
exfatprogs
expac
eza
fakeroot
fcitx5
fcitx5-chewing
fcitx5-chinese-addons
fcitx5-gtk
fcitx5-hangul
fcitx5-mozc
fcitx5-qt
fd
ffmpegthumbnailer
fzf
gliff
gnome-disk-utility
gnome-keyring
gnome-themes-extra
gpu-screen-recorder
gvfs-mtp
gvfs-nfs
gvfs-smb
herdr
hype
hyprland-preview-share-picker
hyprpicker
inetutils
inxi
kernel-modules-hook
lazygit
libreoffice-fresh
libvips
localsend
lua51
luarocks
man-db
mariadb-libs
mise-bin
monologue
moonlight-qt
mpv-mpris
nautilus-python
noto-fonts-cjk
nss-mdns
nvim
obsidian
omacalc
omacut
omarchy-hyprland-titlebars
omarchy-nvim
omasnap
omawrite
owe
owe-lockfeed
pacman-contrib
pamixer
pinta
plocate
plymouth
postgresql-libs
python-poetry-core
qemu-user-static-binfmt
qrencode
ruby
sddm
signed
slurp
starship
superwhisper-bin
sushi
system-config-printer
tesseract
tesseract-data-eng
tldr
tmux
tobi-try
tree-sitter-cli
ttf-ia-writer
ttf-jetbrains-mono-nerd-basic
ttfx
tzupdate
ufw
ufw-docker
unzip
usage
vi
whois
woff2-font-awesome
yaru-icon-theme
yay
yt-dlp
zbar
zoxide
```

## Frame-specific additions outside the base manifest

These are deliberate additions or replacements for the custom touch/armv7
environment:

```text
adwaita-icon-theme
firefox
squeekboard
xdg-user-dirs
```

`bluez-tools`, Firefox, Nautilus, MPV, imv, Fastfetch, btop, ripgrep, and the
Noto fonts are now installed. Most appear in the base-manifest section because
they are also Omarchy defaults; Firefox replaces the unavailable Chromium.
