import re,sys
# replay an iMPACT XC9500XL program SVF, retrying each pulse+check block
src=re.sub(r'//[^\n]*','',open(sys.argv[1]).read())
out=['''
proc chk {r mask want} { return [expr {("0x[string range $r end-1 end]" & $mask) == $want}] }
set retries 0
proc block {scans tck n v line} {
  global retries
  for {set t 0} {$t < 12} {incr t} {
    foreach s $scans { drscan xc.tap [lindex $s 0] [lindex $s 1] -endstate RUN/IDLE }
    runtest $tck
    set r [drscan xc.tap $n $v -endstate RUN/IDLE]
    if {[chk $r 3 1]} { if {$t} {echo "block $line ok after $t retries"}; return }
    incr retries
  }
  echo "BLOCK FAILED $line last=$r"; error "block $line failed"
}
''']
scans=[]; pend=None; k=0; nblk=0
for st in src.split(';'):
    t=' '.join(st.split())
    if not t: continue
    k+=1
    op=t.split()[0]
    if op=='SIR':
        v=re.search(r'TDI \((\w+)\)',t).group(1)
        assert re.match(r'SIR 8 ',t) and pend is None
        for s in scans: out.append(f'drscan xc.tap {s[0]} 0x{s[1]} -endstate RUN/IDLE')
        scans=[]
        out.append(f'irscan xc.tap 0x{v} -endstate RUN/IDLE')
    elif op=='SDR':
        n=int(t.split()[1]); v=re.search(r'TDI \((\w+)\)',t).group(1); m=re.search(r'TDO \((\w+)\)',t)
        if m and n==32: out.append('if {[expr {"0x[drscan xc.tap 32 0]" & 0x0fffffff}] != 0x09616093} { error badid }')
        elif m:
            assert pend and scans, t
            assert int(m.group(1),16)==1 and int(re.search(r' MASK \((\w+)\)',t).group(1),16)==3
            out.append('block {'+' '.join('{%d 0x%s}'%s for s in scans)+'} %d %d 0x%s %d'%(pend,n,v,k))
            nblk+=1; scans=[(n,v)]; pend=None
        else: assert pend is None; scans.append((n,v))
    elif op=='RUNTEST':
        c=int(t.split()[1])*24
        if scans: pend=c
        else: out.append(f'runtest {c}')
    else: assert op in('TRST','ENDIR','ENDDR','STATE','FREQUENCY','TIR','HIR','TDR','HDR'),t
for s in scans: out.append(f'drscan xc.tap {s[0]} 0x{s[1]} -endstate RUN/IDLE')
out.append('echo "REPLAY DONE retries=$retries"')
open(sys.argv[2],'w').write('\n'.join(out)+'\n'); print('blocks',nblk)
