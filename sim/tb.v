// Self-checking bench for tf536atari: 68030, socket, SDRAM and IDE models.
// DLY=1 adds the CPLD's pin delays (taken from the timing report).
`timescale 1ns/10ps
module tb;
parameter PHASE=1, DLY=1; parameter real TAS=5.0, TSK=62.35;
parameter LONG=1;
localparam real OF = DLY?5.8:0.2, OS = DLY?10.3:0.2, OC=DLY?18.0:0.2,
                OA = DLY?14.5:0.2, IN = DLY?3.5:0.1, CR=DLY?10.0:4.0;
integer errs=0, test=0; reg quiet=0;
task fail(input [8*60-1:0] m); begin
  errs=errs+1; if(errs<25) $display("FAIL test %0d @%0t: %0s",test,$realtime,m); end endtask

reg osc=0; always #5 osc=~osc;
reg sck=0; always #(TSK) sck=~sck;
reg res=1;
// ---- CPU pins
reg [31:0] A=0; reg [2:0] FC=5; reg [1:0] SIZ=0; reg AS30=1,DS30=1,RW=1,CBREQ=1,BG30=1;
reg [31:0] cdo=0; reg cdoe=0;
wire [31:0] cd; assign cd = cdoe?cdo:32'hz;
wire dsk0,dsk1,sterm,avec,cback,ciin,cclk0,ds0o,ds1o,sto,avo,cbo,cio;
tri1 berr; reg xberr=0; assign berr = xberr?1'b0:1'bz;
wire aso,udso,ldso,vmao,eo,bgo_; tri1 as,uds,lds,vma;
wire br30,bgack30; reg br=1,bgack=1; wire bg;
wire buseno,crk,cke,csno,raso,caso,weo,oeo; wire [12:0] ao; wire [1:0] bao; wire [3:0] dmo;
wire i0,i1,ioro,iowo; wire cs0,cs1,ior,iow; reg iordy=1;
reg dtack=1,vpa=1;
tri [2:0] ipl; pulldown(ipl[0]); pullup(ipl[1]); pulldown(ipl[2]);
wire [31:0] A_; wire as_,ds_,rw_,cb_,sk_,dt_,vp_,bga_,bg_,rs_,iw_;
assign #(IN) as_=AS30; assign #(IN) ds_=DS30; assign #(IN) cb_=CBREQ; assign #(IN) sk_=sck;
assign #(IN) dt_=dtack; assign #(IN) vp_=vpa; assign #(IN) bg_=BG30;
assign #(IN) rs_=res; assign #(IN) iw_=iordy;
`ifdef GATE
tf536atari dut
`else
tf536atari #(.PHASE(PHASE)) dut
`endif
(.A(A),.D(cd[31:16]),.SIZ(SIZ),.FC(FC),.AS30(as_),.DS30(ds_),.RW30(RW),
 .DSACK0(ds0o),.DSACK1(ds1o),.STERM(sto),.BERR(berr),.AVEC(avo),.CBREQ(cb_),.CBACK(cbo),.CIIN(cio),
 .CLKCPU(cclk0),.CLK100M(osc),.CLK7M_RAW(sk_),.RESET(rs_),.AS(aso),.UDS(udso),.LDS(ldso),.DTACK(dt_),.VPA(vp_),
 .VMA(vmao),.E(eo),.BR(br),.BR30(br30),.BG30(bg_),.BG(bgo_),.BGACK(bgack),.BGACK30(bgack30),.IPL(ipl),
 .BUSEN(buseno),.CLKRAM(crk),.CLKRAME(cke),.RAMCS(csno),.RAS(raso),.CAS(caso),.RAMWE(weo),.RAMOE(oeo),
 .ARAM(ao),.BA(bao),.DQM(dmo),.IDECS0(i0),.IDECS1(i1),.IOR(ioro),.IOW(iowo),.IDEWAIT(iw_),.IDEINT(1'b0));
wire cclk,bsen,csn,ras,cas,we,roe; wire [12:0] ra; wire [1:0] rb; wire [3:0] dm; wire E;
assign #(OF) cclk=cclk0; assign #(OF) dsk0=ds0o; assign #(OF) dsk1=ds1o; assign #(OF) sterm=sto;
assign #(OS) avec=avo; assign #(OF) cback=cbo; assign #(OF) ciin=cio;
// rise/fall split: assert = clock path, negate = AS30 pad path less IN
assign #(OA-IN,OC) as=aso; assign #(OA-IN,OC) uds=udso; assign #(OA-IN,OC) lds=ldso;
assign #(OS) vma=vmao; assign #(OS) E=eo; assign #(OS) bg=bgo_;
assign #(OF) bsen=buseno; assign #(OF) csn=csno; assign #(OF) ras=raso; assign #(OF) cas=caso;
assign #(OF) we=weo; assign #(OF) roe=oeo; assign #(OF) ra=ao; assign #(OF) rb=bao; assign #(OF) dm=dmo;
assign #(OS) cs0=i0; assign #(OS) cs1=i1; assign #(OA-IN,OC) ior=ioro; assign #(OS) iow=iowo;
reg rk=0; always @(crk) rk <= #(CR) crk;

// ---- generic monitors
realtime tc=0; reg cm=0;
always @(cclk) begin if(cm && $realtime>100 && $realtime-tc<9.9) fail("short CPU clock phase"); tc=$realtime; cm=1; end
always @(ipl) if (ipl!==3'b010 && $time>0) fail("IPL driven");
wire sdrv; wire drv_bus = ~bsen&RW, drv_ram=sdrv&~roe, drv_ide=~ior;

`ifdef GATE
wire [2:0] nd=cdoe+drv_bus+drv_ram+drv_ide;
`else
wire [2:0] nd=cdoe+drv_bus+drv_ram+drv_ide+(dut.ctl_oe&~as_);
`endif
realtime tn; always @(nd) begin if(nd>1) tn=$realtime; end
always @(nd) if(nd>1) begin:cc #4 if(nd>1 && $realtime-tn>=3.9) fail("D bus contention"); end
always @(negedge dsk0) fail("DSACK0 asserted");
`ifndef GATE
always @(posedge dut.ctl_oe) if(A[31:16]!=16'h0500||!RW||FC==7) fail("D driven for non control");
`endif
always @(bsen) if(!bsen && !bgack) fail("BUSEN low under BGACK");
always @(as or uds or lds or bgack) if(!bgack && (aso!==1'bz||udso!==1'bz||ldso!==1'bz||vmao!==1'bz)) begin #1 if(!bgack&&aso!==1'bz) fail("strobes driven under BGACK"); end
reg nomb=0; always @(negedge as) if(nomb) fail("motherboard AS in card cycle");
// 68000 bus rules
realtime tA=0,tasr=-1000,tasf=0,tudf=0,tudr=-1000,tbs=0;
always @(A or RW or FC) begin tA=$realtime; if($realtime-tasr<29.5) fail("address hold after AS"); if(!as) fail("address changed under AS"); end
always @(negedge as) if($time>100) begin
  if($realtime-tA<30) fail("address setup"); if($realtime-tasr<150) fail("AS high time"); tasf=$realtime; end
always @(posedge as) begin tasr=$realtime; if(!AS30) fail("AS off before AS30"); end
wire anyds=uds&lds;
always @(negedge anyds) begin tudf=$realtime; if(!RW) begin
   if($realtime-tasf<100) fail("write strobe too early");
   if(!cdoe||bsen) fail("write data not on socket"); if($realtime-tbs<30) fail("write data setup"); end
  else if($realtime-tasf>5 && !as) fail("read strobe late"); end
always @(bsen) begin tbs=$realtime; if(bsen && $realtime-tudr<29.5 && !RW) fail("write data hold"); end
always @(cdoe) if(!cdoe && !bsen) if($realtime-tudr<29.5) fail("CPU write hold");
always @(posedge anyds) begin tudr=$realtime; end
// E
realtime te=0; always @(posedge E) begin if(te>0 && ($realtime-te>10*2*TSK+25||$realtime-te<10*2*TSK-25)) fail("E period"); te=$realtime; end
always @(negedge E) if(te>0 && ($realtime-te>8*TSK+25||$realtime-te<8*TSK-25)) fail("E high");
always @(negedge vma) if(FC==7) fail("VMA in CPU space");
realtime tv=0,tef=0; always @(negedge vma) tv=$realtime; always @(negedge E) tef=$realtime;
always @(posedge E) if(!vma && $realtime-tv<200) fail("VMA setup to E");
always @(posedge vma) if($time>100 && vmao!==1'bz && (E||$realtime-tef>400)) fail("VMA off before E fell");

// ---- socket slave
reg [15:0] mbm[0:65535]; wire [15:0] sdr; integer wr_cnt=0; reg nodt=0;
wire [15:0] swr = cd[31:16];
wire iack = (FC==7)&&(A[19:16]==15);
wire selv = iack ? (A[3:1]!=6) : (A[23:8]==16'hfffc);
assign sdr = iack ? 16'h0042 : mbm[A[16:1]];
assign cd[31:16] = (~bsen&RW) ? ((~as&~anyds) ? sdr : 16'hxxxx) : 16'hz;
integer sdel=0, sc=0;
always @(negedge sck) if(!as && !anyds && !selv && !(A[23:16]==8'hf7) && !nodt) begin if(sc>=sdel) #5 dtack = as; else sc=sc+1; end
always @(posedge as) begin sc=0; #10 dtack=1; end
always @(negedge as) if(selv) #60 if(!as) vpa=0;
always @(posedge as) #10 vpa=1;
reg u_=0,l_=0; always @(negedge uds) if(!RW)u_=1; always @(negedge lds) if(!RW) l_=1;
always @(posedge as) if($time>100 && (u_||l_)) begin
  if(A[23:16]!=8'hf7) begin if(u_) mbm[A[16:1]][15:8]=swr[15:8]; if(l_) mbm[A[16:1]][7:0]=swr[7:0]; wr_cnt=wr_cnt+1; end u_=0;l_=0; end
reg sawu,sawl,sawas,sawvma; always @(negedge uds) sawu=1; always @(negedge lds) sawl=1; always @(negedge as) sawas=1; always @(negedge vma) sawvma=1;

// ---- SDRAM
reg [31:0] mem[0:(1<<24)-1]; reg [12:0] row[0:3]; reg [3:0] open=0;
realtime tact[0:3], tpre[0:3], tref=0, tlmr=0, tup=0, twr=-1000, trefl=0; integer nref=0,k; reg inited=0; integer ini=0;
realtime lastchg=0; always @(ras or cas or we or ra or rb or dm or csn) lastchg=$realtime;
reg [31:0] dq=0; reg dqe=0; reg [23:0] rdadr;
assign sdrv=dqe; assign cd = (dqe&~roe)?dq:32'hz;
integer nrd=0,nwr=0,nact=0; realtime maxgap=0;
initial for(k=0;k<4;k=k+1) begin tact[k]=-1000; tpre[k]=-1000; end
reg ckp=1; wire ckd; assign #(OF) ckd=cke; reg [2:0] bl=0; realtime lc2=0; always @(ckd) lc2=$realtime;
always @(posedge rk) begin ckp<=ckd; if($realtime-lc2<1.5 && $time>100) fail("CKE setup"); end
always @(posedge rk) if(ckp) begin:sd
  if(bl!=0) begin dq<=#2.7 32'hx; dq<=#7.5 mem[rdadr]; dqe<=#2.7 1; rdadr[1:0]=rdadr[1:0]+1; bl=bl-1; end
  else dqe<=#6 0;
  if(!csn && {ras,cas,we}!=7 && $realtime-lastchg<1.5) fail("SDRAM setup");
  if(!csn) case({ras,cas,we})
  3'b011: begin nact=nact+1; if(open[rb]) fail("ACT on open bank"); if(!inited) fail("ACT before init");
     if($realtime-tpre[rb]<17.9) fail("tRP"); if($realtime-tref<59.9) fail("tRFC"); if($realtime-tact[rb]<59.9) fail("tRC");
     if($realtime-tlmr<19.9) fail("tMRD"); open[rb]=1; row[rb]=ra; tact[rb]=$realtime; end
  3'b101: begin nrd=nrd+1; if(!open[rb]) fail("READ closed"); if($realtime-tact[rb]<17.9) fail("tRCD"); if(ra[10]) fail("AP");
     if(dm!=0) fail("read DQM"); bl=4; rdadr={rb,row[rb],ra[8:0]}; end
  3'b100: begin nwr=nwr+1; if(!open[rb]) fail("WRITE closed"); if($realtime-tact[rb]<17.9) fail("tRCD w"); if(roe) fail("write, switches open");
     if(DS30) fail("write before DS30"); if(!cdoe||^cd===1'bx) fail("write data invalid"); if(dqe) fail("write vs read drive");
     twr=$realtime; for(k=0;k<4;k=k+1) if(!dm[k]) mem[{rb,row[rb],ra[8:0]}][8*k+:8]=cd[8*k+:8]; end
  3'b010: begin bl=0; if(!ra[10]) fail("single PRE"); for(k=0;k<4;k=k+1) if(open[k]) begin if($realtime-tact[k]<41.9) fail("tRAS"); tpre[k]=$realtime; end
     if($realtime-twr<12) fail("tWR"); open=0; if(!inited) begin if($realtime-tup<100000) fail("init wait"); ini=1; end end
  3'b001: begin if(open) fail("REF open"); for(k=0;k<4;k=k+1) if($realtime-tpre[k]<17.9) fail("tRP ref"); if($realtime-tref<59.9) fail("tRFC ref");
     nref=nref+1; if($realtime-trefl>maxgap) maxgap=$realtime-trefl; trefl=$realtime; tref=$realtime; if(ini==1||ini==2) ini=ini+1; end
  3'b000: begin if(ini!=3) fail("LMR order"); if(ra!=13'h222||rb!=0) fail("LMR value"); if(open) fail("LMR open"); tlmr=$realtime; inited=1; ini=0; end
  endcase
end
always @(negedge res) begin inited=0; ini=0; end
always @(negedge bgack) nodt=0;
always @(posedge res) tup=$realtime;
initial tup=0;

// ---- IDE
reg [15:0] idr[0:15]; realtime tiowr=0;
wire ior_d,iow_d,cs0_d,cs1_d;
assign #(8.0) ior_d=ior; assign #(8.0) iow_d=iow; assign #(2) cs0_d=cs0; assign #(2) cs1_d=cs1;
wire [2:0] da=A[4:2]; wire strobe=ior_d&iow_d; realtime tst=-5000,tda=0;
reg [1:0] iom=0; // 0 ready 1 short 2 1us 3 stuck
integer niow=0,nior=0;
always @(cs0_d or cs1_d or da) tda=$realtime;
always @(negedge strobe) if($time>100) begin
  if($realtime-tda<70) fail("IDE addr setup"); if($realtime-tst<600) fail("IDE cycle time"); tst=$realtime;
  if(cs0_d==cs1_d) fail("IDE CS");
  if(iom) begin iordy=0; case(iom) 1: #250 iordy=1; 2: #1000 iordy=1; endcase end end
reg idat; always @(negedge strobe) idat=(!cs0&&da==0);
always @(da or cs0_d or cs1_d) if(!strobe) fail("IDE address moved under strobe");
always @(posedge strobe) tiup=$realtime; realtime tiup=-100;
always @(da) if($realtime-tiup<20) fail("IDE address hold");
always @(posedge strobe) if($time>100) begin if($realtime-tst<(idat?165:290)) fail("IDE strobe width"); if(iom==3) iordy=1; end
always @(negedge dsk1) begin if(!ior && $realtime-(tst)<((!cs0&&da==0)?165:290)-0.1) fail("IDE read dsack early");
  if(!iow) fail("DSACK under IOW"); if(iom!=0 && iom!=3 && !iordy) fail("IORDY ignored"); end
assign cd[31:16]=(!ior)?(!ior_d?idr[{cs0,da}]:16'hxxxx):16'hz;
reg [15:0] wl;
always @(posedge iow_d) if($time>100) begin wl=cd[31:16]; if(!cdoe) fail("IDE write data gone"); else idr[{cs0,da}]=wl; tiowr=$realtime; niow=niow+1; end
always @(cdoe) if(!cdoe && $realtime-tiowr<30) fail("IDE write hold");
always @(negedge ior) begin nior=nior+1; if(!bsen||!roe||cdoe) fail("IOR with other driver"); end

// ---- 68030
wire dsk1_d,st_d,berr_d,av_d,cbk_d,cii_d; assign #0.1 dsk1_d=dsk1; assign #0.1 st_d=sterm; assign #0.1 berr_d=berr; assign #0.1 av_d=avec; assign #0.1 cbk_d=cback; assign #0.1 cii_d=ciin;
always @(posedge cclk) if(AS30 && cdoe) begin #3 cdoe=0; end
reg [31:0] q[0:3]; integer nq, term; reg cii; integer ncb; realtime tcyc,tend; integer lim;
task cyc(input [31:0] a,input [2:0] fc,input rw,input [1:0] siz,input [31:0] wd,input bu);
 reg done,sy,first; begin
  sawu=0;sawl=0;sawas=0;sawvma=0;nq=0;term=0;done=0;first=1;lim=0;ncb=0;
  @(posedge cclk); #3 A=a; FC=fc; SIZ=siz; RW=rw;
  @(negedge cclk); #(TAS) AS30=0; tcyc=$realtime; if(rw) DS30=0; if(bu) CBREQ=0;
  while(!done) begin
   @(posedge cclk); lim=lim+1; sy=(st_d===0);
   if(sy && !cbk_d && bu) ncb=ncb+1;
   cii=cii_d;
   begin:x reg cont; cont=(bu && !cbk_d && nq<3);
   if(!rw && first) begin #4 cdo=wd; cdoe=1; end
   @(negedge cclk);
   if(sy) begin q[nq]=cd; nq=nq+1; term=2; if(!cont) done=1; else if(nq==3) begin #4 CBREQ=1; end end
   else if(berr_d===0) begin term=3; done=1; @(negedge cclk); end
   else if(dsk1_d===0 && av_d===0) fail("AVEC and DSACK");
   else if(dsk1_d===0 || av_d===0) begin term=(av_d===0)?4:1; if(cbk_d===0) fail("CBACK on async"); @(negedge cclk); q[0]=cd; nq=1; cii=cii_d; done=1; end
   end
   if(!rw && first) begin #4 DS30=0; end first=0;
   if(lim>30000) begin fail("cycle hung"); done=1; end
  end
  #(TAS) AS30=1; DS30=1; CBREQ=1; tend=$realtime;
 end endtask
function [31:0] rep(input [31:0] v,input [1:0] a,input [1:0] s); // 68030 operand placement (long regs)
  case(s) 1: rep={4{v[7:0]}}; 2: rep = a[0]?{v[15:8],v[15:8],v[7:0],v[15:8]}:{2{v[15:0]}};
          3: case(a) 0: rep={v[23:0],v[7:0]}; 1: rep={v[23:16],v[23:0]}; 2: rep={2{v[23:8]}}; 3: rep={4{v[23:16]}}; endcase
          default: case(a) 0: rep=v; 1: rep={v[31:24],v[31:8]}; 2: rep={2{v[31:16]}}; 3: rep={4{v[31:24]}}; endcase endcase
endfunction
task rd(input [31:0] a); cyc(a,5,1,2,0,0); endtask
task wr(input [31:0] a,input [15:0] d); cyc(a,5,0,2,{d,d},0); endtask
task rl(input [31:0] a); cyc(a,5,1,0,0,0); endtask
task wl32(input [31:0] a,input [31:0] d); cyc(a,5,0,0,d,0); endtask
task exp(input integer t); if(term!=t) begin $display("  term %0d want %0d A=%h",term,t,A); fail("wrong termination"); end endtask
task expw(input [15:0] v); if(q[0][31:16]!==v) begin $display("  got %h want %h A=%h",q[0][31:16],v,A); fail("data"); end endtask
task expl(input [31:0] v); if(q[0]!==v) begin $display("  got %h want %h A=%h",q[0],v,A); fail("data32"); end endtask
task idle(input integer n); repeat(n) @(posedge cclk); endtask
task reset(input real ns); begin idle(3); res=0; #(ns) res=1; #1000; end endtask
task ctl(input [15:0] v); begin wr(32'h05000000,v); exp(1); end endtask
function [23:0] ix(input [31:0] a); ix=a[25:2]; endfunction

integer i,j,s0,n0; reg [31:0] v,w,a; realtime t0;
initial begin
 for(i=0;i<65536;i=i+1) mbm[i]=i*3+7; for(i=0;i<16;i=i+1) idr[i]=16'h5a00+i;
 res=0; #2000 res=1; tup=$realtime; #500;
 // 1,2 motherboard
 test=1;
 for(i=0;i<60;i=i+1) begin
   #(($random&127)); rd(32'h00012000+2*i); exp(1); expw(mbm[(32'h12000+2*i)>>1]); if(cii!==0) fail("CIIN"); if(!sawu||!sawl) fail("word strobes");
   wr(32'h06013000+2*i,16'h1234+i); exp(1);
   rd(32'h00013000+2*i); expw(16'h1234+i);
   if(i==10) sdel=3; if(i==20) sdel=0; end
 // speed, back to back
 rd(32'h100); t0=tcyc; for(i=0;i<20;i=i+1) rd(32'h100); $display("  motherboard read: %0.0f ns/cycle",(tcyc-t0)/20);
 test=2;
 cyc(32'h12000,5,1,1,0,0); if(!sawu||sawl) fail("even byte"); cyc(32'h12001,5,1,1,0,0); if(sawu||!sawl) fail("odd byte");
 cyc(32'h12001,5,0,1,32'h77777777,0); if(sawu||!sawl) fail("odd byte w"); cyc(32'h12001,5,0,2,32'h77777777,0); if(sawu||!sawl) fail("odd word w"); rd(32'h12000);
 cyc(32'h12000,5,1,0,0,0); if(!sawu||!sawl) fail("long"); cyc(32'h12000,5,1,3,0,0); if(!sawu||!sawl) fail("3byte");
 test=3;
 fork rd(32'h00f70000); begin #5000 if(AS30) fail("ended without DTACK"); xberr=1; wait(AS30); #20 xberr=0; end join exp(3);
 rd(32'h12010); exp(1); expw(mbm[16'h9008]);
 test=4;
 for(i=0;i<25;i=i+1) begin #($random&1023);
  rd(32'hfffffc00); exp(1); if(!sawvma) fail("no VMA"); expw(mbm[16'hfe00]);
  if($realtime-tef>90 && !E) fail("not in step with E"); 
  if(E && $realtime-te<400) fail("latched early in E");
  if(i[0]) wr(32'h00fffc02,16'h99aa); if(i[0]) begin exp(1); #200; if(mbm[16'hfe01]!==16'h99aa) fail("VPA write"); end end
 test=5;
 cyc({28'hfffffff,3'd4,1'b1},7,1,1,0,0); exp(4); if(!sawas||sawvma) fail("iack vpa");
 cyc({28'hfffffff,3'd6,1'b1},7,1,1,0,0); exp(1); if(q[0][23:16]!==8'h42||!sawl||sawu) fail("iack vector");
 cyc({28'hfffffff,3'd2,1'b1},7,1,1,0,0); exp(4); 
 test=6; nomb=1;
 cyc(32'h00022000,7,1,2,0,0); exp(3); cyc(32'h00022000,7,0,2,0,0); exp(3); cyc(32'h00000000,7,1,2,0,0); exp(3); cyc(32'h00010000,7,1,2,0,0); exp(3);
 cyc(32'h05020000,7,1,2,0,0); exp(3); nomb=0; rd(32'h12010); exp(1);
 // SDRAM
 test=8; nomb=1; rl(32'h01000000); exp(2); if(cii!==1) fail("CIIN low on RAM");
 for(i=2;i<26;i=i+1) wl32(32'h01000000+(1<<i),32'ha5000000+i);
 wl32(32'h01000000,32'hdeadbeef); wl32(32'h04fffffc,32'h0badf00d); wl32(32'h04f00000,32'h11112222);
 for(i=2;i<26;i=i+1) begin rl(32'h01000000+(1<<i)); expl(32'ha5000000+i); exp(2); end
 rl(32'h01000000); expl(32'hdeadbeef); rl(32'h04fffffc); expl(32'h0badf00d); rl(32'h04f00000); expl(32'h11112222);
 rl(32'h01000000); t0=tcyc; for(i=0;i<20;i=i+1) rl(32'h01000000+4*i); $display("  SDRAM read: %0.0f ns/cycle, AS30 width %0.0f",(tcyc-t0)/20,tend-tcyc);
 test=9;
 for(i=0;i<16;i=i+1) begin wl32(32'h02000010,32'h00112233); wl32(32'h02000014,32'h44556677);
   v=32'hcafed00d; s0=i[3:2]; cyc(32'h02000010+i[1:0],5,0,i[3:2],rep(v,i[1:0],i[3:2]),0); exp(2);
   n0=(s0==0)?4:s0; // bytes
   w=32'h00112233; for(j=0;j<n0;j=j+1) if(i[1:0]+j<4) w[8*(3-(i[1:0]+j))+:8]=v>>(8*(n0-1-j));
   rl(32'h02000010); expl(w); rl(32'h02000014); expl(32'h44556677); end
 test=10;
 for(i=0;i<8;i=i+1) wl32(32'h03000000+4*i,32'h1000*i+32'h9);
 cyc(32'h03000000,5,1,0,0,1); if(nq!=4) fail("burst length"); for(i=0;i<4;i=i+1) if(q[i]!==32'h1000*i+9) fail("burst data");
 $display("  burst: %0.0f ns",tend-tcyc);
 cyc(32'h03000010,5,1,0,0,1); if(nq!=4||q[3]!==32'h7009) fail("burst2");
 for(i=1;i<4;i=i+1) begin cyc(32'h03000000+4*i,5,1,0,0,1); if(nq!=1||ncb!=0) fail("unaligned burst"); expl(32'h1000*i+9); end
 cyc(32'h03000000,5,0,0,32'h9,1); if(ncb!=0) fail("write burst");
 fork cyc(32'h03000000,5,1,0,0,1); begin:ab @(negedge sterm); @(posedge sterm); #2 CBREQ=1; end join // withdrawn
 rl(32'h03000004); expl(32'h1009); rl(32'h03000008); expl(32'h2009);
 test=11; n0=nref; t0=$realtime; maxgap=0;
 for(i=0;i<3000;i=i+1) begin a=32'h01000000+(($random&32'h3fff)<<2); v=$random;
   if(i%3==0) begin wl32(a,v); rl(a); expl(v); end else if(i%3==1) begin rl(a); if(q[0]!==mem[ix(a)]) fail("rd"); end
   else begin cyc({a[31:4],4'd0},5,1,0,0,1); if(nq!=4||q[2]!==mem[ix({a[31:4],4'd8})]) fail("bst"); end
   if(i%7==0) #($random&63); end
 $display("  refresh interval %0.0f ns avg, %0.0f max", ($realtime-t0)/(nref-n0),maxgap);
 if(($realtime-t0)/(nref-n0)>7800||maxgap>7800*2) fail("refresh rate"); idle(5); n0=nref; #100000 if(nref-n0<13) fail("idle refresh");
 // control register
 test=12; rd(32'h05000000); exp(1); expw(16'he050); if(cii!==0) fail("CIIN ctl"); rd(32'h0500fffe); expw(16'he050);
 ctl(16'he053); rd(32'h05000000); expw(16'he053); ctl(16'h0000); rd(32'h05000000); expw(16'he053); ctl(16'he152); ctl(16'hf050); ctl(16'he040); rd(32'h05001234); expw(16'he053);
 wr(32'h05008000,16'he05d); rd(32'h05000000); expw(16'he051); ctl(16'he052); rd(32'h05000000); expw(16'he052);
 wl32(32'h05000000,32'he0500000); rd(32'h05000000); expw(16'he050); rl(32'h04fffff0); 
 nomb=0; cyc(32'h05000000,7,0,2,32'he053e053,0); exp(3); cyc(32'h05050000,7,0,2,32'he053e053,0); exp(1); rd(32'h05000000); expw(16'he050);
 rd(32'h05010000); exp(1); if(!sawas) fail("ctl window too big"); rd(32'h05000000); ctl(16'he051); rl(32'h02000010); rd(32'h05000002); expw(16'he051); ctl(16'he050); rl(32'h02000014); expl(32'h44556677);
 // shadow
 test=13; for(i=0;i<32'h80000;i=i+4) mem[ix(32'h04f80000+i)]=32'h70000000+i; mem[ix(32'h04f7fffc)]=32'h12121212;
 rd(32'h00e00000); exp(1); rl(32'h04f80000); expl(32'h70000000); exp(2);
 ctl(16'he051);
 for(j=0;j<2;j=j+1) begin v=j?32'hff000000:0;
  rl(v+32'he00000); exp(2); expl(32'h70000000); if(cii!==1) fail("win cacheable"); if(sawas) fail("AS");
  rl(v+32'he3fffc); exp(2); expl(32'h7003fffc); rd(v+32'he40000); exp(1); rd(v+32'he7fffe); exp(1); rd(v+32'hdffffe); exp(1); rd(v+32'he80000); exp(1); end
 rd(32'h01e00000); exp(2); rd(32'h06e00000); exp(1); cyc(32'he00010,5,1,0,0,1); if(nq!=4||q[3]!==32'h7000001c) fail("win burst");
 for(i=2;i<18;i=i+1) begin rl(32'he00000+(1<<i)); expl(32'h70000000+(1<<i)); end
 ctl(16'he053); for(j=0;j<2;j=j+1) begin v=j?32'hff000000:0;
  rl(v+32'he40000); exp(2); expl(32'h70040000); rl(v+32'he7fffc); exp(2); expl(32'h7007fffc); rd(v+32'he80000); exp(1); rl(v+32'he00000); exp(2); end
 cyc(32'h00e00000,7,1,2,0,0); exp(3); cyc(32'h00ed0000,7,1,2,0,0); exp(1);
 test=14; rl(0); exp(2); expl(32'h70000000); rl(4); exp(2); expl(32'h70000004); cyc(0,5,1,0,0,1); if(nq!=1||ncb!=0) fail("vector burst"); 
 cyc(4,5,1,0,0,1); if(nq!=1) fail("vec burst4"); rd(8); exp(1); rd(32'h10); exp(1); rd(32'hff000000); exp(1); cyc(7,5,1,1,0,0); exp(2);
 test=15; s0=wr_cnt; wr(0,16'hbeef); exp(1); wr(6,16'hbeef); exp(1); wr(32'he00000,16'hbeef); exp(1); wr(32'hffe7fffe,16'hbeef); exp(1); idle(3); if(wr_cnt-s0!=4) fail("writes to mb");
 if(mem[ix(32'h04f80000)]!==32'h70000000||mem[ix(32'h04f80004)]!==32'h70000004||mem[ix(32'h04fffffc)]!==32'h7007fffc) fail("copy changed");
 test=16; nomb=1; rl(32'h04f80000); exp(3); rl(32'h04fffffc); exp(3); s0=nwr; n0=nact; wl32(32'h04f80000,1); exp(3); wl32(32'h04fffffc,1); exp(3); if(nwr!=s0||nact!=n0) fail("SDRAM access"); rl(32'h04f7fffc); exp(2); expl(32'h12121212); wl32(32'h04f7fffc,5); exp(2); 
 ctl(16'he050); rl(32'h04f80000); exp(2); expl(32'h70000000); ctl(16'he053); nomb=0;
 // IDE
 test=18; nomb=1;
 for(j=0;j<2;j=j+1) begin v=j?32'hff000000:0;
  for(i=0;i<16;i=i+1) begin rd(v+32'hf00000+4*i); exp(1); expw(idr[{i[3],i[2:0]}]); if(cii!==0) fail("CIIN ide"); end
  for(i=0;i<16;i=i+1) begin wr(v+32'hf00000+4*i,16'h7100+i); exp(1); rd(v+32'hf00000+4*i); expw(16'h7100+i); end
  for(i=0;i<8;i=i+1) begin rd(v+32'hf00000); rd(v+32'hf00002); wr(v+32'hf00000,16'h55aa+i); wr(v+32'hf00002,16'haa55+i); rl(32'h01000000); rd(v+32'hf0001c); wl32(32'h02000000,i); end end
 rd(32'hf00000); t0=tst; rd(32'hf00000); $display("  IDE data cycle %0.0f ns",tst-t0);
 test=19; for(j=1;j<4;j=j+1) begin iom=j; rd(32'hf00000); exp(1); expw(idr[0]); if(j>1 && tend-tst<1000) fail("IORDY not honoured"); if(tend-tst>1800) fail("IORDY stuck"); wr(32'hf0001c,16'h1111); exp(1); if(tend-tst>1900) fail("IORDY stuck w"); rd(32'hf00038); exp(1); end iom=0; nomb=0;
 rd(32'hf00040); exp(1); if(!sawas) fail("IDE window too big"); rd(32'hefffc0); if(!sawas) fail("IDE low"); cyc(32'h00f00000,7,0,2,0,0); exp(3);
 // arbitration
 test=7;
 for(i=0;i<40;i=i+1) begin
  br=0; #1 if(br30!==0) fail("BR30");
  fork begin if(i&1) rl(32'h01000000+4*i); else if(i&2) wr(32'h13000,i); else rd(32'hf00000); end
   begin if(i) wait(!AS30); if(i) #(i*9%60) BG30=0; else begin wait(AS30===0); wait(AS30); BG30=0; end wait(bg===0); if(!AS30) fail("BG under AS30"); if(as!==1||uds!==1||lds!==1||!bsen||!AS30) fail("BG before strobes off"); end join
  #40 bgack=0; br=1; #2 if(aso!==1'bz||vmao!==1'bz) fail("AS driven"); if(bgack30!==0) fail("BGACK30");
  #50 BG30=1; t0=tc; n0=nref; #(i==5?60000:1500); if(i==5&&nref==n0) fail("no refresh under BGACK"); 
  @(posedge cclk) t0=$realtime; @(posedge cclk) if($realtime-t0<100) fail("CPU not slow"); bgack=1; #200; rd(32'h12010); exp(1); expw(mbm[16'h9008]); end
 // resets
 if(LONG) begin
 test=17; mem[ix(32'h01234560)]=32'hfeedface; ctl(16'he053);
 reset(64000); rl(32'h01234560); expl(32'hfeedface); rd(32'h05000000); expw(16'he053); rl(0); expl(32'h70000000);
 reset(15.0e6); rd(32'h05000000); expw(16'he053); rl(32'h01234560); expl(32'hfeedface); t0=tcyc;
 reset(17.0e6); rd(32'h05000000); expw(16'he050); rd(0); exp(1); 
 // reset in the middle of a burst, then retained data
 fork begin cyc(32'h01234560,5,1,0,0,0); end begin #31 res=0; #3000 res=1; end join rl(32'h01234560); expl(32'hfeedface);
 ctl(16'he051); reset(64000); rl(4); expl(32'h70000004);
 end
 $display("%0s PHASE=%0d DLY=%0d TSK=%0.2f TAS=%0.1f errors=%0d",errs?"FAILED":"PASSED",PHASE,DLY,TSK,TAS,errs);
 $finish; end
initial #200000000 begin $display("FAILED timeout test %0d",test); $finish; end
endmodule
