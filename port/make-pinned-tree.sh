#!/bin/bash
# Make a copy of an Omarchy tree in which every bare "import QtQuick" in shell/ is pinned to 6.11.
# This is the same text change that Omarchy's own Quickshell patch (load_qtquick_611.patch in
# omacom/omarchy-pkgs) applies at load time. It stops Qt 6.12's new QtQuick "Color" singleton from
# hiding Omarchy's own "Color" singleton (shell/Commons/Color.qml).
#
#   make-pinned-tree.sh <omarchy source tree> <destination>
set -eu
src=$1
dst=$2
rm -rf "$dst"
mkdir -p "$dst"
for entry in "$src"/*; do
  name=$(basename "$entry")
  [[ $name == shell ]] && continue
  ln -s "$entry" "$dst/$name"
done
cp -r "$src/shell" "$dst/shell"
n=$(grep -rlE '^[ \t]*import[ \t]+QtQuick[ \t]*$' "$dst/shell" --include='*.qml' | wc -l)
find "$dst/shell" -name '*.qml' -exec sed -i -E 's/^([ \t]*import[ \t]+QtQuick)[ \t]*$/\1 6.11/' {} +
echo "pinned 'import QtQuick' to 6.11 in $n QML files under $dst/shell"
