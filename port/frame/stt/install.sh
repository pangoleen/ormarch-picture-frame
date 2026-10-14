#!/bin/bash
# PF1007L dictation: install the speech engine and a model, and the two user services.
# Run on the frame as user frame, from a clone of this repository. Nothing is compiled.
#
#   port/frame/stt/install.sh              Moonshine v2 tiny (30 MB download, the default model)
#   port/frame/stt/install.sh parakeet     also NVIDIA Parakeet 110M (104 MB download) and select it
#   port/frame/stt/install.sh moonshine1   also Moonshine v1 tiny (103 MB download) and select it
#   port/frame/stt/install.sh moonshine    select Moonshine v2 again
# Measured on the frame with 30 test sentences (docs/experiments.md E068): Moonshine v2 0.71 s of work
# for each second of speech, v1 0.87, Parakeet 1.07.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dir=$HOME/.local/share/pf-stt
url=https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models
moonshine=sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27
moonshine_sha=9ec31b342d8fa3240c3b81b8f82e1cf7e3ac467c93ca5a999b741d5887164f8d
moonshine1=sherpa-onnx-moonshine-tiny-en-int8
moonshine1_sha=d5fe6ec4334fef36255b2a4010412cad4c007e33103fec62fb5d17cad88086f2
parakeet=sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8
parakeet_sha=17f945007b52ccd8b7200ffc7c5652e9e8e961dfdf479cefcabd06cf5703630b

[[ $(id -un) == "frame" && $(uname -m) == "armv7l" ]] || { echo "STOP: run on the frame as user frame"; exit 1; }

fetch() {   # name sha256
  [[ -d $dir/$1 ]] && return
  curl -fL -o "$dir/$1.tar.bz2" "$url/$1.tar.bz2"
  echo "$2  $dir/$1.tar.bz2" | sha256sum -c -
  tar xjf "$dir/$1.tar.bz2" -C "$dir"
  rm "$dir/$1.tar.bz2"
}

sudo env ALL_PROXY="${ALL_PROXY:-}" pacman -S --noconfirm --needed python ydotool wtype libnotify
echo uinput | sudo tee /etc/modules-load.d/pf1007l-uinput.conf >/dev/null
sudo modprobe uinput
mkdir -p "$dir" "$HOME/.config/systemd/user"
[[ -x $dir/venv/bin/python ]] || python3 -m venv "$dir/venv"
"$dir/venv/bin/pip" install -q --only-binary=:all: sherpa-onnx==1.13.8
install -m 755 "$here/pf-dictate.py" "$here/pf-stt-bench.py" "$here/pf-stt-bench-offline.py" "$here/pf-stt-eval.py" "$dir/"

fetch "$moonshine" "$moonshine_sha"
choice=$moonshine
case "${1:-}" in
  parakeet) fetch "$parakeet" "$parakeet_sha"; choice=$parakeet ;;
  moonshine1) fetch "$moonshine1" "$moonshine1_sha"; choice=$moonshine1 ;;
  moonshine|"") ;;
  *) echo "Use: $0 [moonshine|moonshine1|parakeet]"; exit 1 ;;
esac
ln -sfn "$dir/$choice" "$dir/model"

mkdir -p "$HOME/.local/bin"
install -m 755 "$here/pf-dictate-model" "$HOME/.local/bin/pf-dictate-model"
install -m 644 "$here/pf-dictate.service" "$here/pf-ydotoold.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable pf-ydotoold.service pf-dictate.service
systemctl --user restart pf-ydotoold.service pf-dictate.service
echo "Model in use: $choice. Send audio from the Mac: python3 scripts/mac-dictate.py"
