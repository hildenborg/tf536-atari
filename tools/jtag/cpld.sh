#!/bin/bash
# Program/verify the TF536-ATARI firmware on the TF536 CPLD (XC95288XL) with a USB-Blaster and OpenOCD.
#
#   cpld.sh id                read the JTAG ID (writes nothing)
#   cpld.sh svf     FILE.jed  generate FILE.svf for programming (no hardware)
#   cpld.sh verify  FILE.jed  read back and compare (writes nothing)
#   cpld.sh program FILE.jed  erase, program, then verify (asks first; -y skips)
#   cpld.sh restore FILE.jed  the same for any other .jed, such as the board's
#                             original firmware; nothing is checked against rtl/
#
# program also needs FILE.svf and FILE.sha256 next to FILE.jed. The checksums,
# written by build.sh, tie both files to the sources in rtl/. restore needs
# only the .jed and makes its own SVF. The SVF is replayed through
# svf2tcl.py, which repeats a program pulse until its check passes; OpenOCD's
# own svf command would stop at the first failed check.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$here/../..
# terriblefire78/xilinx:v1, by digest so that the tools cannot change unnoticed
image=${IMG:-docker.io/terriblefire78/xilinx@sha256:d609f62b3216f5034489fb798661472ab23f28f492cefc818a02e1bcda49a44a}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

die() { echo "cpld.sh: $*" >&2; exit 1; }
usage() { sed -n '4,9s/^#   //p' "$0" >&2; exit 2; }

ocd() {
    timeout 280 openocd -f interface/altera-usb-blaster.cfg \
        -c "transport select jtag; jtag newtap xc tap -irlen 8 -expected-id 0x09616093 -ignore-version" \
        -c "$1" > "$tmp/ocd.log" 2>&1
}

# sum_ok FILE: does FILE match its entry in $sums?
sum_ok() {
    local want got
    want=$(awk -v n="$(basename "$1")" '$2 == n { print $1 }' "$sums")
    got=$(sha256sum < "$1")
    [ -n "$want" ] && [ "$want" = "${got%% *}" ]
}

check_id() {
    ocd "init; scan_chain; shutdown" || { cat "$tmp/ocd.log" >&2; die "can't access the CPLD"; }
    grep -qE "tap/device found: 0x.9616093" "$tmp/ocd.log" ||
        { cat "$tmp/ocd.log" >&2; die "not an XC95288XL"; }
    grep "tap/device found" "$tmp/ocd.log"
}

# impact_svf FILE.jed NAME COMMAND: let iMPACT write $tmp/NAME
impact_svf() {
    cp "$1" "$tmp/a.jed"
    rm -f "$tmp/$2"
    printf '%s\n' 'setmode -bscan' "setcable -p svf -file $2" \
        'addDevice -p 1 -file a.jed' "$3" 'quit' > "$tmp/i.cmd"
    podman run --rm --network none --platform linux/amd64 -v "$tmp":/w:Z -w /w "$image" \
        /opt/Xilinx/10.1/ISE/bin/lin64/impact -batch i.cmd > "$tmp/impact.log" 2>&1 ||
        { tail "$tmp/impact.log" >&2; die "iMPACT failed"; }
    [ -s "$tmp/$2" ] || { tail "$tmp/impact.log" >&2; die "iMPACT wrote no $2"; }
}

make_verify() {
    impact_svf "$1" verify.svf 'verify -p 1'
    [ "$(grep -c '^SDR 146 .*TDO' "$tmp/verify.svf")" = 1620 ] ||
        die "unexpected verify file from iMPACT"
}

# gen_svf FILE.jed: write $tmp/prog.svf and its replay script $tmp/prog.tcl
gen_svf() {
    impact_svf "$1" prog.svf 'program -e -p 1'
    python3 -I "$here/svf2tcl.py" "$tmp/prog.svf" "$tmp/prog.tcl"   # must convert
}

make_svf() {
    gen_svf "$1"
    cp "$tmp/prog.svf" "${1%.jed}.svf"
    if [ -f "$sums" ]; then     # replace only the SVF's entry
        local name got
        name=$(basename "${1%.jed}.svf")
        got=$(sha256sum < "$tmp/prog.svf")
        awk -v n="$name" '$2 != n' "$sums" > "$tmp/sums"
        echo "${got%% *}  $name" >> "$tmp/sums"
        cp "$tmp/sums" "$sums"
    fi
    echo "Wrote ${1%.jed}.svf"
}

do_verify() {
    ocd "init; svf -tap xc.tap -quiet $tmp/verify.svf; shutdown" ||
        { grep -m5 -E "tdo check|READ|WANT" "$tmp/ocd.log" >&2 || tail "$tmp/ocd.log" >&2
          die "VERIFY FAILED"; }
    echo "Verify OK (1620 words)"
}

cmd=${1:-}; jed=${2:-}
case $cmd in
id) check_id; exit ;;
svf|verify|program|restore) ;;
*) usage ;;
esac

[[ $jed == *.jed && -f $jed ]] || usage
sums=${jed%.jed}.sha256

if [ "$cmd" = svf ]; then
    [ ! -f "$sums" ] || sum_ok "$jed" || die "$jed does not match $sums; rebuild"
    make_svf "$jed"
    exit
fi

# Generate everything before touching the chip
if [ "$cmd" = program ]; then
    svf=${jed%.jed}.svf
    [ -f "$sums" ] || die "missing $sums, which build.sh writes; for a .jed from elsewhere use: cpld.sh restore $jed"
    [ -f "$svf" ] || die "missing $svf; run: cpld.sh svf $jed"
    for src in "$root/rtl/tf536atari.v" "$root/rtl/tf536atari.ucf"; do
        [ -f "$src" ] || die "missing $src"
        sum_ok "$src" || die "$jed was not built from this $src; rebuild"
    done
    sum_ok "$jed" || die "$jed does not match $sums; rebuild"
    sum_ok "$svf" || die "$svf does not match $sums; run: cpld.sh svf $jed"
    python3 -I "$here/svf2tcl.py" "$svf" "$tmp/prog.tcl"
elif [ "$cmd" = restore ]; then
    gen_svf "$jed"
fi
make_verify "$jed"
check_id

if [ "$cmd" = program ] || [ "$cmd" = restore ]; then
    if [ "${3:-}" != -y ]; then
        [ "$cmd" = program ] || echo "$(basename "$jed") is not checked against rtl/."
        read -r -p "Erase and program with $(basename "$jed")? [y/N] " a
        [ "$a" = y ] || die "cancelled"
    fi
    ocd "init; source $tmp/prog.tcl; shutdown" ||
        { grep -E "ok after|FAILED|Error" "$tmp/ocd.log" >&2 || true
          die "PROGRAMMING FAILED (the CPLD may be blank or partly programmed; it is safe to retry)"; }
    grep -E "ok after|REPLAY DONE" "$tmp/ocd.log"
fi
do_verify
