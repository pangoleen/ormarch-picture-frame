#!/bin/bash
# Build the Claude Code payload for the PF1007L (32-bit ARM) on the Mac.
#
# Anthropic ships Claude Code only as a Bun-compiled binary for x64 and arm64. Its JavaScript is the
# same for every platform. This script follows the method of Yumi-Lab/claude-code-smartpi (pinned copy
# in port/third_party/claude-code-smartpi, MIT): download the official binary, extract its JS, bundle
# it for Node with esbuild, and assemble the runtime tree. The esbuild step needs about 800 MB of
# memory, so it runs here and not on the 1 GB frame (project rule 5).
# Output: port/frame/claude/out/claude-code-<version>.tar.gz (git-ignored; never redistributed).
#
# Usage: port/frame/claude/build-on-mac.sh [version]   (default: MAX_VERSION of the pinned copy)
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
src=$root/port/third_party/claude-code-smartpi
ver=${1:-$(head -1 "$src/MAX_VERSION" | tr -d '[:space:]')}
out=$root/port/frame/claude/out
work=$out/work-$ver
mkdir -p "$out" "$work"
bin=$out/claude-$ver-linux-arm64-musl.bin
url=https://downloads.claude.ai/claude-code-releases/$ver/linux-arm64-musl/claude
if [ ! -s "$bin" ]; then
  echo "Downloading the official Claude Code $ver binary ..."
  curl -fSL -C - --progress-bar -o "$bin.part" "$url"
  mv "$bin.part" "$bin"
fi
echo "Extracting the JavaScript ..."
rm -rf "$work/extracted"
python3 -I "$src/shim/extract-bun-js.py" "$bin" -o "$work/extracted" --label "$ver" >/dev/null
cli=$work/extracted/claude-$ver.cli.js
manifest=$work/extracted/claude-$ver.manifest.json
[ -f "$cli" ] && [ -f "$manifest" ] || { echo "STOP: extraction gave no cli.js or manifest"; exit 1; }
echo "Bundling for Node with esbuild ..."
mkdir -p "$work/build"
( cd "$work/build"
  [ -f package.json ] || printf '{"name":"b","private":true}\n' > package.json
  npm install --no-audit --no-fund --silent esbuild ws undici js-yaml >/dev/null )
node "$src/shim/bundle-bunfs.mjs" --extracted "$work/extracted" --out "$work/bundle.cjs" \
  --esbuild-dir "$work/build" --target node20
echo "Assembling the tree ..."
lib=$work/claude-code
rm -rf "$lib"; mkdir -p "$lib/node_modules" "$lib/assets"
install -m 644 "$cli" "$lib/cli.js"
install -m 644 "$work/bundle.cjs" "$lib/bundle.cjs"
python3 -I - "$manifest" "$work/extracted" "$lib/assets" <<'PY'
import json, os, shutil, sys
manifest, src, dst = sys.argv[1:4]
for m in json.load(open(manifest))["modules"]:
    if m["kind"] != "asset" or m["name"].endswith(".node") or not m.get("path"):
        continue
    rel = m["name"][len("/$bunfs/root/"):] if m["name"].startswith("/$bunfs/root/") else m["name"].lstrip("/")
    os.makedirs(os.path.dirname(os.path.join(dst, rel)) or dst, exist_ok=True)
    shutil.copy2(os.path.join(src, m["path"]), os.path.join(dst, rel))
PY
for f in shim/claude.mjs shim/bun-shim.mjs shim/claude-daemon.mjs shim/claude-client.mjs shim/wire.mjs lib/claude-release.sh; do
  install -m 644 "$src/$f" "$lib/$(basename "$f")"
done
for m in ws undici js-yaml argparse; do
  [ -d "$work/build/node_modules/$m" ] && cp -R "$work/build/node_modules/$m" "$lib/node_modules/"
done
echo "$ver" > "$lib/VERSION"
tar -C "$work" -czf "$out/claude-code-$ver.tar.gz" claude-code
ls -la "$out/claude-code-$ver.tar.gz"
