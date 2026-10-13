# pf1007l shell library. POSIX sh. Works in busybox ash (initramfs) and in bash.
# Boot-stage markers on the FAT partition of the SD card, so that a Mac can read
# them with no tools:  <FAT>/pf/stages.log  and  <FAT>/pf/stage/<NN-name>
#
# PF_BOOT = mount point of the FAT partition (/boot in the real system).

PF_BOOT=${PF_BOOT:-/boot}
PF_DIR=$PF_BOOT/pf
PF_RUN=${PF_RUN:-/run/pf1007l}

pf_uptime() { cut -d' ' -f1 /proc/uptime 2>/dev/null; }

# The start counter that U-Boot wrote (a hex string). "x" when it is not readable.
pf_bootnum() {
	n=$(sed -n 's/^pf_boots=//p' "$PF_DIR/uboot.env" 2>/dev/null | tr -d '\r' | head -n 1)
	echo "${n:-x}"
}

# The real system mounts /boot from /etc/fstab. If that did not happen (the device
# came late), try it again here. Not in the initramfs (it mounts the partition itself).
pf_try_mount() {
	[ -z "${PF_INITRAMFS:-}" ] && [ "$PF_BOOT" = /boot ] || return 0
	grep -q " /boot vfat " /proc/mounts 2>/dev/null && return 0
	mount /boot 2>/dev/null
}

# True when the FAT partition is mounted read-write.
pf_fat_ok() {
	pf_try_mount
	[ -d "$PF_DIR" ] || return 1
	grep -q " $PF_BOOT vfat rw" /proc/mounts 2>/dev/null
}

# New start (the counter changed): keep the old logs as "prev", clear the markers.
pf_begin() {
	n=$(pf_bootnum)
	[ "$(cat "$PF_DIR/stage/.boot" 2>/dev/null)" = "$n" ] && return 0
	rm -rf "$PF_DIR/prev" 2>/dev/null
	[ -d "$PF_DIR/last" ] && mv "$PF_DIR/last" "$PF_DIR/prev" 2>/dev/null
	rm -rf "$PF_DIR/stage" 2>/dev/null
	mkdir -p "$PF_DIR/stage" "$PF_DIR/last"
	echo "$n" > "$PF_DIR/stage/.boot"
	# Keep stages.log small: the last 400 lines.
	if [ -f "$PF_DIR/stages.log" ] && [ "$(wc -l < "$PF_DIR/stages.log")" -gt 800 ]; then
		tail -n 400 "$PF_DIR/stages.log" > "$PF_DIR/stages.tmp" && mv "$PF_DIR/stages.tmp" "$PF_DIR/stages.log"
	fi
	echo "---- start $n ----" >> "$PF_DIR/stages.log"
}

# pf_stage <NN-name> [text...]   One line in stages.log + one empty marker file.
pf_stage() {
	name=$1; shift
	line="up=$(pf_uptime) stage=$name $*"
	echo "pf1007l: $line" > /dev/kmsg 2>/dev/null
	mkdir -p "$PF_RUN" 2>/dev/null
	if pf_fat_ok; then
		pf_begin
		if [ -s "$PF_RUN/pending.log" ]; then
			cat "$PF_RUN/pending.log" >> "$PF_DIR/stages.log" && : > "$PF_RUN/pending.log"
			for m in "$PF_RUN"/pending-stage/*; do
				[ -e "$m" ] && : > "$PF_DIR/stage/$(basename "$m")"
			done
			rm -rf "$PF_RUN/pending-stage"
		fi
		echo "start=$(pf_bootnum) $line" >> "$PF_DIR/stages.log"
		: > "$PF_DIR/stage/$name"
		sync
	else
		# The FAT partition is not there yet: keep the line, write it later.
		mkdir -p "$PF_RUN/pending-stage" 2>/dev/null
		echo "start=? $line (written late)" >> "$PF_RUN/pending.log" 2>/dev/null
		: > "$PF_RUN/pending-stage/$name" 2>/dev/null
	fi
	return 0
}

# Linux tells U-Boot "this start was good": copy the counter into linux-ok.env.
pf_confirm() {
	pf_fat_ok || return 1
	printf 'pf_ok=%s\n' "$(pf_bootnum)" > "$PF_DIR/linux-ok.env" && sync
}
