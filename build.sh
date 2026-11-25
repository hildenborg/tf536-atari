#!/bin/sh
# Build with Xilinx ISE 10.1 in podman. Usage: ./build.sh [PHASE 0..3] [fs]
# fs builds the full-speed variant, rtl/tf536atari_fs.v.
set -e
cd "$(dirname "$0")"
PHASE=${1:-1}
case $PHASE in 0|1|2|3) ;; *) echo "Usage: ./build.sh [PHASE 0..3] [fs]" >&2; exit 2 ;; esac
case ${2:-} in
"") SRC=tf536atari.v;    OUT=build/phase$PHASE;    FW=tf536-atari_phase$PHASE ;;
fs) SRC=tf536atari_fs.v; OUT=build/fs-phase$PHASE; FW=tf536-atari-fs_phase$PHASE ;;
*)  echo "Usage: ./build.sh [PHASE 0..3] [fs]" >&2; exit 2 ;;
esac
# terriblefire78/xilinx:v1, by digest so that the tools cannot change unnoticed
IMG=${IMG:-docker.io/terriblefire78/xilinx@sha256:d609f62b3216f5034489fb798661472ab23f28f492cefc818a02e1bcda49a44a}
rm -rf "$OUT"; mkdir -p "$OUT/tmp"
echo "verilog work \"$SRC\"" > "$OUT/tf536atari.prj"
cat > "$OUT/tf536atari.xst" <<X
set -tmpdir tmp
set -xsthdpdir xst
run -ifn tf536atari.prj -ifmt mixed -ofn tf536atari -ofmt NGC -p xc9500xl -top tf536atari
-generics { PHASE=$PHASE } -opt_mode Speed -opt_level 2 -iobuf YES
-fsm_extract NO -keep_hierarchy NO -pld_mp YES -pld_xp YES
X
cp "rtl/$SRC" rtl/tf536atari.ucf "$OUT"
# -ofmt abel: sim/abel2v.py reads the report's equations for the gate-level run
podman run --rm --network none --entrypoint /bin/sh -v "$PWD/$OUT:/w:Z" -w /w "$IMG" -c '
set -e
for d in /opt/Xilinx/10.1/ISE; do export XILINX=$d PATH=$d/bin/lin64:$PATH LD_LIBRARY_PATH=$d/lib/lin64; done
mkdir -p xst
xst -ifn tf536atari.xst -ofn tf536atari.syr
ngdbuild -aul -uc tf536atari.ucf -p xc9500xl tf536atari.ngc tf536atari.ngd
cpldfit -p xc95288xl-10-TQ144 -ofmt abel -optimize speed -loc on -slew fast -init low -inputs 54 -pterms ${PT:-15} -unused float -power std -terminate float tf536atari.ngd
taengine -f tf536atari -detail -l tf536atari.tim
hprep6 -s IEEE1149 -n tf536atari -i tf536atari
' > "$OUT/build.log" 2>&1 || { tail -30 "$OUT/build.log"; exit 1; }
grep -A12 -i 'resource summary' "$OUT/tf536atari.rpt" | head -20

# Spec 12: no register-to-register path may be longer than the 10 ns clock.
worst=$(awk '/^ *\* .* \* *$/ { cyc = /tCYC/ }
             cyc && /^ *To:/  { v = $NF; gsub(/[^0-9.]/, "", v); if (v + 0 > m) m = v + 0 }
             END              { printf "%.1f\n", m }' "$OUT/tf536atari.tim")
awk -v w="$worst" 'BEGIN { exit !(w > 0 && w <= 10.0) }' ||
    { echo "build.sh: worst register-to-register path is $worst ns, limit 10.0" >&2; exit 1; }
echo "Worst register-to-register path: $worst ns"

# Spec 7.4: IPL2, IPL1 and IPL0 (pins 140, 142, 143) must be left floating.
for pin in 140 142 143; do
    sed -n '/Device Pin Out/,/^Legend/p' "$OUT/tf536atari.rpt" |
        grep -Eq "(^|[^0-9])$pin TIE( |\$)" ||
        { echo "build.sh: the fitter did not leave pin $pin (IPL) floating" >&2; exit 1; }
done

for x in jed rpt tim; do cp "$OUT/tf536atari.$x" "firmware/$FW.$x"; done
(cd "$OUT"; sha256sum "$SRC" tf536atari.ucf
 cd ../../firmware; sha256sum "$FW.jed") > "firmware/$FW.sha256"
tools/jtag/cpld.sh svf "firmware/$FW.jed"
