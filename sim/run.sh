#!/bin/bash
# Regression: ./run.sh [matrix|long|mutate|all]
cd "$(dirname "$0")"; B=../build/sim; mkdir -p $B
run(){ n=$1; src=$2; shift 2; a=(); for x in "$@"; do a+=(-P "tb.$x"); done
  iverilog -g2012 "${a[@]}" -o $B/$n.vvp tb.v $src && timeout 590 vvp $B/$n.vvp > $B/$n.log; tail -2 $B/$n.log | grep -E 'PASSED|FAILED' || echo "NO RESULT $n"; }
matrix(){ for d in 0 1; do for p in 0 1 2 3; do for t in 62.35 61.9; do for c in 3.0 5.0 8.0; do
  run m$d$p$t$c ../rtl/tf536atari.v PHASE=$p DLY=$d TSK=$t TAS=$c LONG=0 & done; done; wait; done; done; }
long(){ for p in 0 1 2 3; do run l$p ../rtl/tf536atari.v PHASE=$p LONG=1 & done; wait; }
mut(){ sed "$2" ../rtl/tf536atari.v > $B/mut_$1.v; cmp -s $B/mut_$1.v ../rtl/tf536atari.v && { echo "$1: PATTERN DID NOT MATCH"; return; }
  echo "$1: $(run x$1 $B/mut_$1.v LONG=${3:-0}) | $(grep -m1 FAIL $B/x$1.log)"; }
mutate(){
 mut bank   's/bk <= A\[25:24\]/bk <= {A[24],A[24]}/' &
 mut key    "s/ & (D\[31:20\] == 12'he05);/;/" &
 mut hold   's/if (iend) iow <= 0;/if (0) iow <= 0;/' &
 mut tail   's/idt <= (ifin \& t_ide)/idt <= 1'"'"'b0 \& t_ide/' &
 mut busen  's/busen & ~(as2 & as3 & as4)/busen \& ~as2/' &
 mut noreset 's/if (rlong) begin/if (1'"'"'b0) begin/' 1 &
 mut early  's/rcnt\[13\] & rcnt\[12\]/rcnt[11] \& rcnt[10]/' 1 &
 mut prot   's/((p_ram & ~p_prot) | p_ovl)/(p_ram | p_ovl)/' &
 mut vecburst 's/ & ~p_vec;/;/' &
 mut winwr  's/(~A\[18\] | sh512) & RW30 & shen/(~A[18] | sh512) \& shen/' &
 mut lanes  's/~A\[1\] & (A\[0\] | ~byt)/~A[1]/' &
 mut refresh 's/reg \[8:0\] tc/reg [10:0] tc/;s/tc == 9.h1ff/tc == 11'"'"'h7ff/' &
 mut cke    's/ & run & rst2) | step;/ \& run \& rst2 \& 1'"'"'b0) | step;/' &
 mut iordy  's/imin & (iw2 | ito)/imin/' &
 mut vma    's/(ec == 2) & m_s4/(ec == 5) \& m_s4/' &
 mut ashigh 's/hicnt\[3\] & hicnt\[2\] & hicnt\[1\]/1/;s/mrise & arm/(mrise|mfall) \& arm/' &
 mut bgdrv  's/drv <= bgo & ba2;/drv <= bgo \& ba2 \& bg2;/' &
 mut avec   's/p_cpu & ~vp2) m_avec/~vp2) m_avec/' &
 mut wrearly 's/mrise & m_as & (RW30 | ~ds2)/m_as/' &
 mut coproc 's/| ~(A\[17\] & A\[16\])//;s/~(A\[17\] & A\[16\])/~A[17]/' &
 wait; }
case ${1:-all} in all) matrix; long; mutate;; *) $1;; esac
