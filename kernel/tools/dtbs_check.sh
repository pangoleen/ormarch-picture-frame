#!/usr/bin/env bash
# dt-schema check (the kernel's `make dtbs_check`) of the two board DTBs against
# the binding schemas of Linux v7.2.10. Run kernel/build.sh first.
#
#   kernel/tools/dtbs_check.sh
#
# Control: the upstream board sun8i-a33-ga10h-v1.1 (same .dtsi base as our board),
# compiled by kernel/build.sh and byte-equal to the DTB of the stock kernel package.
# Its messages are the baseline of the upstream A33 tablet files. The script prints
# the messages of OUR DTBs that are NOT in the baseline.
#
# Needs: docker. The bindings tree must be in refs/kernel/linux-7.2.10/Documentation/
# devicetree/bindings (from linux-7.2.10.tar.xz, SHA-256 2feaa704...cff2ebf3; build.sh
# does not fetch it, because the build does not use it: see the end of this file).
# Writes only to refs/kernel/dtschema/, refs/kernel/pipcache/ and kernel/logs/.
set -euo pipefail

# python:3.12-slim, linux/arm64 (runs natively on an Apple silicon Mac)
IMAGE="python@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de"
DTSCHEMA="2026.9"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/refs/kernel/linux-7.2.10"
WORK="$ROOT/refs/kernel/dtschema"
LOGS="$ROOT/kernel/logs"
B="Documentation/devicetree/bindings"

[ -d "$SRC/$B/display" ] || {
	echo "bindings tree not found. Get it:" >&2
	echo "  curl -LO https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.10.tar.xz" >&2
	echo "  tar -xJf linux-7.2.10.tar.xz -C refs/kernel linux-7.2.10/$B" >&2
	exit 1
}
[ -f "$ROOT/kernel/out/sun8i-a33-pf1007l.dtb" ] && [ -f "$ROOT/refs/kernel/build/dtb/control-ga10h.dtb" ] ||
	{ echo "run kernel/build.sh first" >&2; exit 1; }
mkdir -p "$WORK" "$ROOT/refs/kernel/pipcache" "$LOGS"
cp "$ROOT/refs/kernel/build/dtb/control-ga10h.dtb" "$WORK/control-sun8i-a33-ga10h-v1.1.dtb"
cp "$ROOT/kernel/out/sun8i-a33-pf1007l.dtb" "$ROOT/kernel/out/sun8i-a33-pf1007l-uart0-sd.dtb" "$WORK/"

docker run --rm \
	-v "$ROOT/refs/kernel/pipcache:/root/.cache/pip" -v "$SRC:/linux:ro" -v "$WORK:/work" \
	-e DTSCHEMA="$DTSCHEMA" -e B="$B" \
	"$IMAGE" bash -euo pipefail -c '
		export PIP_ROOT_USER_ACTION=ignore PIP_DISABLE_PIP_VERSION_CHECK=1
		# pylibfdt has no ready wheel for this platform: build it one time (pip keeps it in its cache).
		if ! pip install -q "dtschema==$DTSCHEMA" >/dev/null 2>&1; then
			apt-get update -qq >/dev/null
			apt-get install -y -qq --no-install-recommends gcc libc6-dev swig >/dev/null 2>&1
			pip install -q "dtschema==$DTSCHEMA"
		fi
		pip freeze > /work/pip-freeze.txt
		cd /linux
		dt-mk-schema -j "$B" > /work/processed-schema.json 2> /work/mk-schema.err
		echo "schemas: $(grep -c "\"\\\$id\"" /work/processed-schema.json || true) ids, dt-mk-schema messages: $(wc -l < /work/mk-schema.err)"
		for d in control-sun8i-a33-ga10h-v1.1 sun8i-a33-pf1007l sun8i-a33-pf1007l-uart0-sd; do
			# -m: also report compatible strings that no schema matches (the kernel default)
			dt-validate -m -u "$B" -p /work/processed-schema.json "/work/$d.dtb" > "/work/$d.dtschema.txt" 2>&1 || true
		done
	'

# Join each message with its "from schema" line, remove the file name, sort.
norm() {
	python3 -I - "$1" <<'EOF'
import re, sys
out, cur = [], None
for line in open(sys.argv[1], errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("\t") or line.startswith("  "):
        if cur is not None:
            cur += " | " + line.strip()
        continue
    if cur is not None:
        out.append(cur)
    cur = re.sub(r"^\S+\.dtb: ", "", line)
if cur is not None:
    out.append(cur)
print("\n".join(sorted(set(out))))
EOF
}
C="$WORK/control-sun8i-a33-ga10h-v1.1"
norm "$C.dtschema.txt" > "$C.norm.txt"
{
	echo "dt-schema check, dtschema $DTSCHEMA, bindings of Linux v7.2.10"
	echo "control (upstream sun8i-a33-ga10h-v1.1, = stock DTB): $(wc -l < "$C.norm.txt" | tr -d ' ') messages"
	for d in sun8i-a33-pf1007l sun8i-a33-pf1007l-uart0-sd; do
		norm "$WORK/$d.dtschema.txt" > "$WORK/$d.norm.txt"
		echo
		echo "== $d.dtb: $(wc -l < "$WORK/$d.norm.txt" | tr -d ' ') messages in total"
		echo "-- messages that are NOT in the control (ours):"
		comm -23 "$WORK/$d.norm.txt" "$C.norm.txt" | sed 's/^/   /'
		echo "-- messages of the control that our DTB does not have:"
		comm -13 "$WORK/$d.norm.txt" "$C.norm.txt" | sed 's/^/   /'
	done
	echo
	echo "== messages that the control and sun8i-a33-pf1007l.dtb share (upstream A33 baseline):"
	comm -12 "$WORK/sun8i-a33-pf1007l.norm.txt" "$C.norm.txt" | sed 's/^/   /'
} | tee "$LOGS/dtbs-check.log"
# This check does not stop on findings: the upstream base files have findings too.
