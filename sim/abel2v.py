# Fitter report (cpldfit -ofmt abel) to Verilog for gate-level runs:
# abel2v.py REPORT.rpt gate.v; bench: iverilog -DGATE. sim/run.sh gate does both.
import os,re,sys
if len(sys.argv)!=3: sys.exit('usage: abel2v.py REPORT.rpt OUTPUT.v')
t=open(sys.argv[1]).read()
hdr=t[:t.index('  Equations  ')]
init={m[1]:m[2] for m in re.finditer(r'^(\S+) +\d+ +\d+ +FB.*?(SET|RESET) *$',hdr,re.M)}
eq=t[t.index('  Equations  '):t.index('  Device Pin Out')]
eq=eq.split('Mapped Logic')[1]; eq=re.sub(r'//.*','',eq); eq=re.sub(r'\*{3,}.*','',eq)
sig={}
def idn(s):return re.sub(r'<(\d+)>',r'[\1]',s).replace('.EXP','_EXP').replace('.PIN','').replace('.FB','').replace('.LFBK','')
def expr(e):
    e=re.sub(r'D<(1[67])>(?!\.PIN|\d)',r'q_D_\1_',e)
    return idn(e).replace('#','|').replace('$','^')
for st in eq.split(';'):
    st=st.strip()
    if '=' not in st: continue
    l,e=st.split('=',1); l=l.strip().replace(':',''); neg=l.startswith('!'); l=l.lstrip('!')
    m=re.match(r'(.+?)\.(D|T|CLK|AR|AP|CE|OE|EXP)$',l)
    n,k=(m[1],m[2]) if m else (l,'C')
    e=' '.join(e.split()); e=expr(e)
    sig.setdefault(n,{})[k]='~(%s)'%e if neg else '(%s)'%e
# every register in the summary must have an equation, or this is not an ABEL-format report
lost=[n for n in init if not {'D','T'}&set(sig.get(n,{}))]
if lost or not init:
    sys.exit('abel2v.py: %s: no equations for %d of %d registers; build the report with cpldfit -ofmt abel'
             %(sys.argv[1],len(lost),len(init)))
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','rtl','tf536atari.v')).read()
ports=src[src.index(') ('):src.index(');',src.index(') ('))+2][2:]
o=['`timescale 1ns/10ps','module tf536atari '+ports]
port=set(re.findall(r'\b[A-Z][A-Z0-9_]+\b|\bA\b|\bD\b|\bE\b',ports))
buses={}
body=['wire Gnd=0, Vcc=1;']
for n,d in sig.items():
    v=idn(n); base=n.split('<')[0]
    q='q_'+re.sub(r'\W','_',n)
    if 'EXP' in d: body.append(f'wire {v}_EXP; assign {v}_EXP={d["EXP"]};')
    if 'D' in d or 'T' in d:
        assert n in init,n
        ar,ap=d.get('AR'),d.get('AP'); i='1' if init[n]=='SET' else '0'
        nx=d.get('D') or f'{q}^({d["T"]})'
        ce=d.get('CE')
        asy=' or posedge '+q+'_a' if ar or ap else ''
        a=ar or ap
        body.insert(0,f'reg {q}={i};')
        if a: body.append(f'wire {q}_a={a};')
        body.append(f'always @(posedge CLK100M{asy}) '+(f'if({q}_a) {q}<={0 if ar else 1}; else ' if a else '')+(f'if{ce} ' if ce else '')+f'{q}<={nx};')
        val=q
    elif 'C' in d: val=d['C']
    else: continue
    if base not in port:
        if '<' in n: buses.setdefault(base,set()).add(int(re.search(r'<(\d+)',n)[1]))
        else: buses[base]=None
    body.append(f'assign {v}='+(f'{d["OE"]}?{val}:1\'bz;' if 'OE' in d else f'{val};'))
for b,x in buses.items(): o.append(f'wire {b};' if x is None else f'wire [{max(x)}:0] {b};')
open(sys.argv[2],'w').write('\n'.join(o+body+['endmodule'])+'\n'); print(len(init),'regs',len(sig),'sigs')
