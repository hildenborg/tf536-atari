#!/bin/bash
# Regression: ./run.sh [matrix|long|mutate|gate|all] [fs]
#   matrix  the design, all phases, with and without pin delays
#   long    the design, all phases, with the reset tests
#   mutate  deliberate faults; the bench must fail on each one
#   gate    the fitted netlists, from the fitter reports in ../firmware
# The exit status is 0 only if every run passed and every fault was detected.
# fs: the full-speed variant instead of the standard design.
# Logs are in ../build/sim. TMO is the time limit per run in seconds.
cd "$(dirname "$0")" || exit 1
B=../build/sim; mkdir -p $B
case ${2:-} in
"") FS=;    SRC=tf536atari.v;    FW=../firmware/tf536-atari_phase;;
fs) FS=-DFS; SRC=tf536atari_fs.v; FW=../firmware/tf536-atari-fs_phase; B=$B/fs; mkdir -p $B;;
*)  set -- help;;
esac
RTL=../rtl/${SRC:-}
R=$B/results; : > $R

# sim NAME SOURCE [-DMACRO] [PARAMETER=VALUE]...: prints the bench's result line
sim(){ local n=$1 src=$2 a=() x; shift 2
  for x in "$@"; do case $x in -D*) a+=("$x");; *) a+=(-P "tb.$x");; esac; done
  rm -f $B/$n.log $B/$n.vvp     # never report an earlier run's result
  iverilog -g2012 $FS "${a[@]}" -o $B/$n.vvp tb.v "$src" && timeout "${TMO:-1800}" vvp $B/$n.vvp > $B/$n.log
  tail -2 $B/$n.log 2>/dev/null | grep -E '^(PASSED|FAILED)' || echo "NO RESULT $n"; }
run(){ sim "$@" | tee -a $R; }

matrix(){ for d in 0 1; do for p in 0 1 2 3; do for t in 62.35 61.9; do for c in 3.0 5.0 8.0; do
  run m$d$p$t$c $RTL PHASE=$p DLY=$d TSK=$t TAS=$c LONG=0 & done; done; wait; done; done; }
long(){ for p in 0 1 2 3; do run l$p $RTL PHASE=$p LONG=1 & done; wait; }

# mut NAME LONG SED-EXPRESSION...: every expression must change the design
mut(){ local n=$1 lng=$2 e r; shift 2
  cp $RTL $B/mut_$n.v
  for e in "$@"; do
    sed "$e" $B/mut_$n.v > $B/mut_$n.tmp
    if cmp -s $B/mut_$n.tmp $B/mut_$n.v; then echo "$n: PATTERN DID NOT MATCH: $e" | tee -a $R; return; fi
    mv $B/mut_$n.tmp $B/mut_$n.v
  done
  r=$(sim x$n $B/mut_$n.v LONG=$lng)
  case $r in
  FAILED*) echo "$n: detected ($(grep -m1 FAIL $B/x$n.log))";;
  PASSED*) echo "$n: MISSED";;
  *)       echo "$n: $r";;
  esac | tee -a $R; }
mutate(){
 mut bank     0 's/bk <= A\[25:24\]/bk <= {A[24],A[24]}/' &
 mut key      0 "s/ & (D\[31:20\] == 12'he05);/;/" &
 mut hold     0 's/if (iend) iow <= 0;/if (0) iow <= 0;/' &
 mut noreset  1 's/if (rlong) begin/if (1'"'"'b0) begin/' &
 mut early    1 's/rcnt\[13\] & rcnt\[12\]/rcnt[11] \& rcnt[10]/' &
 mut prot     0 's/((p_ram & ~p_prot) | p_ovl)/(p_ram | p_ovl)/' &
 mut vecburst 0 's/ & ~p_vec;/;/' &
 mut winwr    0 's/(~A\[18\] | sh512) & RW30 & shen/(~A[18] | sh512) \& shen/' &
 mut lanes    0 's/~A\[1\] & (A\[0\] | ~byt)/~A[1]/' &
 mut refresh  0 's/reg \[8:0\] tc/reg [10:0] tc/' 's/tc == 9.h1ff/tc == 11'"'"'h7ff/' &
 mut cke      0 's/ & run & rst2) | step;/ \& run \& rst2 \& 1'"'"'b0) | step;/' &
 mut iordy    0 's/imin & (iw2 | ito)/imin/' &
 mut vma      0 's/(ec == 2) & m_s4/(ec == 5) \& m_s4/' &
 mut bgdrv    0 's/drv <= bgo & ba2;/drv <= bgo \& ba2 \& bg2;/' &
 mut wrearly  0 's/mrise & m_as & (RW30 | ~ds2)/m_as/' &
 mut coproc   0 's/~(A\[17\] & A\[16\])/~A[17]/' &
 if [ -n "$FS" ]; then
  mut slowrst  1 's/slow <= ~rst2 | /slow <= /' &
  mut berrhold 0 's/slow <= ~rst2 | ~be1 | m_as/slow <= ~rst2/' &
  mut berrslow 0 's/ | ~be1 | m_as/ | ~be1/' &
  mut clkmax   0 's/tgl  <= ~slow | ~tgl/tgl <= (~slow \& ~t_mb) | (tc[2:0] == 0)/' &
  mut nolatch  0 's/else if (~cap & ~iend) dl/else dl/' &
  mut early030 0 's/(o1 & ~m_av)) dsk/(m_ack \& ~m_av)) dsk/' &
  mut vmatail  0 's/(m_ack & mfall & ~vma) | x3/m_ack \& mfall/' &
  mut latedoe  0 's/(o2 & RW30 & ~m_av)/(o4 \& RW30 \& ~m_av)/' &
  mut earlydoe 0 's/(o2 & RW30 & ~m_av)/(m_ack \& RW30 \& ~m_av)/' &
  mut bgackhi  0 's/BGACK & ~bgk/BGACK/' &
  mut wrhold   0 's/busen & ~RW30 & ~o4/busen \& ~RW30 \& ~o0/' &
  mut ashigh   0 's/hicnt\[3\] & hicnt\[2\] & hicnt\[1\]/1/' 's/mrise & arm/(mrise|mfall) \& arm/' &
  mut iderd    0 's/ide_oe   = t_ide & run & RW30 & (hc == 5)/ide_oe = 0/' &
 else
  mut tail     0 's/idt <= (ifin \& t_ide)/idt <= 1'"'"'b0 \& t_ide/' &
  mut busen    0 's/busen & ~(as2 & as3 & as4)/busen \& ~as2/' &
  mut ashigh   0 's/hicnt\[3\] & hicnt\[2\] & hicnt\[1\]/1/' 's/mrise & arm/(mrise|mfall) \& arm/' &
  mut avec     0 's/p_cpu & ~vp2) m_avec/~vp2) m_avec/' &
 fi
 wait; }

# fresh PHASE: was that phase's firmware built from the design as it is now?
fresh(){ local s=$FW$1.sha256 e=" ($SRC|tf536atari.ucf)\$"
  [ "$(grep -cE "$e" $s 2>/dev/null)" = 2 ] && (cd ../rtl && grep -E "$e" $s | sha256sum -c --quiet) > /dev/null 2>&1; }
gate1(){ local p=$1
  if ! fresh $p; then echo "NO RESULT g$p: firmware/ was not built from this rtl/, run build.sh $p ${FS:+fs}" | tee -a $R; return; fi
  python3 -I abel2v.py $FW$p.rpt $B/gate$p.v > /dev/null || { echo "NO RESULT g$p" | tee -a $R; return; }
  run g$p $B/gate$p.v -DGATE PHASE=$p LONG=1; }
gate(){ for p in 0 1 2 3; do gate1 $p & done; wait; }

case ${1:-all} in
all) matrix; long; mutate; gate;;
matrix|long|mutate|gate) $1;;
*) sed -n '2,9s/^# \{0,1\}//p' "$(basename "$0")" >&2; exit 2;;
esac

pass=$(grep -c '^PASSED ' $R); det=$(grep -c ': detected ' $R)
bad=$(grep -vcE '^PASSED |: detected ' $R)
echo "$pass runs passed, $det faults detected, $bad problems"
[ "$bad" -eq 0 ] && [ $((pass + det)) -gt 0 ] && exit 0
grep -vE '^PASSED |: detected ' $R | sed 's/^/  /'
exit 1
