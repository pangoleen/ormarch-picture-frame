#!/bin/sh
# Runs INSIDE the pf1007l-uboot-build container (it has cpp and dtc).
#   /dts  = image/dts            /kdts = kernel/dts (the board draft)
#   /inc  = kernel include tree  (.../arch/arm/boot/dts/allwinner and .../include)
#   /out  = output
set -eu
rc=0
for name in sun8i-a33-pf1007l-min sun8i-a33-pf1007l-pmic sun8i-a33-pf1007l-full; do
	cpp -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
		-I /inc/arch/arm/boot/dts/allwinner -I /inc/include -I /kdts -I /dts \
		"/dts/$name.dts" -o "/tmp/$name.pp.dts"
	if dtc -I dts -O dtb -W no-unit_address_vs_reg -o "/out/$name.dtb" "/tmp/$name.pp.dts" 2> "/out/$name.dtc.log"; then
		echo "dtc $name: OK, $(stat -c %s "/out/$name.dtb") bytes, $(grep -c Warning "/out/$name.dtc.log" || true) warning(s)"
	else
		echo "dtc $name: FAILED"; cat "/out/$name.dtc.log"; rc=1
	fi
done
exit $rc
