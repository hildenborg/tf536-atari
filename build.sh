#!/bin/sh
# Build with Xilinx ISE 10.1 in podman. Usage: ./build.sh [PHASE 0..3]
set -e
cd "$(dirname "$0")"
PHASE=${1:-1}
IMG=${IMG:-docker.io/terriblefire78/xilinx:v1}
OUT=build/phase$PHASE
rm -rf "$OUT"; mkdir -p "$OUT/tmp"
echo 'verilog work "tf536atari.v"' > "$OUT/tf536atari.prj"
cat > "$OUT/tf536atari.xst" <<X
set -tmpdir tmp
set -xsthdpdir xst
run -ifn tf536atari.prj -ifmt mixed -ofn tf536atari -ofmt NGC -p xc9500xl -top tf536atari
-generics { PHASE=$PHASE } -opt_mode Speed -opt_level 2 -iobuf YES
-fsm_extract NO -keep_hierarchy NO -pld_mp YES -pld_xp YES
X
cp rtl/tf536atari.v rtl/tf536atari.ucf "$OUT"
podman run --rm --network none --entrypoint /bin/sh -v "$PWD/$OUT:/w:Z" -w /w "$IMG" -c '
set -e
for d in /opt/Xilinx/10.1/ISE; do export XILINX=$d PATH=$d/bin/lin64:$PATH LD_LIBRARY_PATH=$d/lib/lin64; done
mkdir -p xst
xst -ifn tf536atari.xst -ofn tf536atari.syr
ngdbuild -aul -uc tf536atari.ucf -p xc9500xl tf536atari.ngc tf536atari.ngd
cpldfit -p xc95288xl-10-TQ144 -ofmt verilog -optimize speed -loc on -slew fast -init low -inputs 54 -pterms ${PT:-15} -unused float -power std -terminate float tf536atari.ngd
taengine -f tf536atari -w --format html1 -l tf536atari.htm || true
taengine -f tf536atari -detail -l tf536atari.tim || true
hprep6 -s IEEE1149 -n tf536atari -i tf536atari
' > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; exit 1; }
grep -A12 -i 'resource summary' "$OUT/tf536atari.rpt" | head -20
for x in jed rpt tim; do cp "$OUT/tf536atari.$x" "firmware/tf536-atari_phase$PHASE.$x"; done
(cd "$OUT"; sha256sum tf536atari.v tf536atari.ucf
 cd ../../firmware; sha256sum "tf536-atari_phase$PHASE.jed") > "firmware/tf536-atari_phase$PHASE.sha256"
tools/jtag/cpld.sh svf "firmware/tf536-atari_phase$PHASE.jed"
