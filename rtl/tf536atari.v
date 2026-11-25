// CPLD firmware for a TF536 Rev 2 in an Atari ST/STE (XC95288XL-10).
// Written from FIRMWARE_SPEC.md; "spec n.n" refers to its sections.
//
// All registers run on the 100 MHz oscillator. Registers that drive the bus
// are in addition cleared asynchronously when AS30 goes high, so that nothing
// from one CPU cycle can leak into the next, however short AS30's high time.

module tf536atari #(
    parameter PHASE   = 1,      // recovered clock delay, 0..3, 10 ns steps
    parameter IDE_SET = 40,     // address to strobe, 10 ns units
    parameter IDE_DAT = 62,     // end of data strobe   (strobe = (n-IDE_SET)*10 ns)
    parameter IDE_REG = 74      // end of register strobe; keep below 192
) (
    input  [31:0] A,
    inout  [31:16] D,
    input  [1:0]  SIZ,
    input  [2:0]  FC,
    input  AS30, DS30, RW30,
    output DSACK0, DSACK1, STERM,
    inout  BERR,
    output AVEC,
    input  CBREQ,
    output CBACK, CIIN,
    output CLKCPU,
    input  CLK100M, CLK7M_RAW, RESET,
    output AS, UDS, LDS,
    input  DTACK, VPA,
    output VMA, E,
    input  BR,
    output BR30,
    input  BG30,
    output BG,
    input  BGACK,
    output BGACK30,
    input  [2:0] IPL,        // never driven
    output BUSEN,
    output CLKRAM, CLKRAME, RAMCS, RAS, CAS, RAMWE, RAMOE,
    output [12:0] ARAM,
    output [1:0]  BA,
    output [3:0]  DQM,
    output IDECS0, IDECS1, IOR, IOW,
    input  IDEWAIT, IDEINT
);

wire clk = CLK100M;

// ------------------------------------------------------------ synchronisers
reg as1 = 1, as2 = 1, as3 = 1, as4 = 1;      // AS30; as3 high + as2 low = new cycle
reg ds1 = 1, ds2 = 1;
reg rst1 = 0, rst2 = 0;
reg dt1 = 1, dt2 = 1, vp1 = 1, vp2 = 1;
reg ba1 = 1, ba2 = 1;
reg bg1 = 1, bg2 = 1, bg3 = 1;
reg cq1 = 1, cq2 = 1;
reg iw1 = 1, iw2 = 1;
always @(posedge clk) begin
    as1 <= AS30;    as2 <= as1;   as3 <= as2;   as4 <= as3;
    ds1 <= DS30;    ds2 <= ds1;
    rst1 <= RESET;  rst2 <= rst1;
    dt1 <= DTACK;   dt2 <= dt1;
    vp1 <= VPA;     vp2 <= vp1;
    ba1 <= BGACK;   ba2 <= ba1;
    bg1 <= BG30;    bg2 <= bg1;   bg3 <= bg2;
    cq1 <= CBREQ;   cq2 <= cq1;
    iw1 <= IDEWAIT; iw2 <= iw1;
end
wire run = ~as1 & ~as2;             // inside a CPU cycle, not at its tail

// ------------------------------------------------- socket clock recovery 5.2
// A level is accepted after two equal samples, then changes are ignored for
// 30 ns. The result is late by 30-40 ns plus PHASE, about half a socket clock
// in total, and is therefore used inverted: an accepted fall marks the rise.
reg c1 = 0, c2 = 0, c3 = 0, cf = 0;
reg [1:0] lock = 0;
reg [3:1] cd = 0;
wire take = (lock == 0) & (c2 == c3) & (c2 != cf);
always @(posedge clk) begin
    c1 <= CLK7M_RAW; c2 <= c1; c3 <= c2;
    if (take) cf <= c2;
    if (take) lock <= 3; else if (lock != 0) lock <= lock - 2'd1;
    cd <= {cd[2:1], cf};
end
wire [3:0] tap = {cd, cf};
wire q0 = tap[PHASE];
reg  q1 = 0;
always @(posedge clk) q1 <= q0;
wire mrise = ~q0 &  q1;             // one 100 MHz cycle before the socket edge
wire mfall =  q0 & ~q1;

// --------------------------------------------------------------- cycle decode
// p_*: plain decode, valid with as2. t_*: type of the cycle in progress.
reg shen = 0, sh512 = 0;            // shadow on, 512 KB
reg p_cpu = 0, p_cperr = 0, p_ram = 0, p_prot = 0, p_ovl = 0, p_vec = 0;
reg p_ctl = 0, p_ide = 0;
wire hi00 = A[31:24] == 8'h00;
wire hiff = A[31:24] == 8'hff;
wire vec  = (A[31:3] == 0) & RW30 & shen;
always @(posedge clk) begin
    p_cpu   <= FC == 3'd7;
    p_cperr <= (FC == 3'd7) & ~A[19] & ~A[18] & ~(A[17] & A[16]); // types 0-2
    p_ram   <= (A[31:27] == 0) & (A[26] ? ~A[25] & ~A[24] : A[25] | A[24]);
    p_prot  <= shen & (A[31:19] == 13'b0000_0100_1111_1);
    p_vec   <= vec;
    p_ovl   <= vec | ((hi00 | hiff) & (A[23:19] == 5'b11100) &
                      (~A[18] | sh512) & RW30 & shen);
    p_ctl   <= A[31:16] == 16'h0500;
    p_ide   <= (hi00 | hiff) & (A[23:6] == {8'hf0, 10'd0});
end
reg t_ram = 0, t_err = 0, t_ctl = 0, t_ide = 0, t_mb = 0;
always @(posedge clk)
    if (as2) begin
        t_ram <= 0; t_err <= 0; t_ctl <= 0; t_ide <= 0; t_mb <= 0;
    end else if (as3) begin
        t_ram <= ~p_cpu & ((p_ram & ~p_prot) | p_ovl);
        t_err <= p_cperr | (~p_cpu & p_prot);
        t_ctl <= ~p_cpu & p_ctl;
        t_ide <= ~p_cpu & p_ide;
        t_mb  <= p_cpu ? ~p_cperr : ~(p_ram | p_ovl | p_ctl | p_ide);
    end

// ------------------------------------------------------------- CPU clock 5.1
// Slow mode follows the recovered clock 10 ns late, in phase with it, so the
// CPU samples DSACK and latches data just after the 68000 would have done.
// Slow mode ends 40-50 ns after AS30 rises: the CPU keeps its address and
// data until its next clock edge, which gives the 68000 hold times.
//
// An IDE cycle also ends with a slower clock (80 ns, held low once AS30 is
// high): at 50 MHz the CPU would move A2-A4 before IOR has risen at the drive.
reg mbt = 0, cck = 0, idt = 0, ifin = 0;
reg [8:0] tc = 0;                   // free running, 5.12 us
wire fast = ~mbt & ba2 & rst2;
always @(posedge clk) begin
    mbt <= t_mb | (mbt & ~(as2 & as3));
    idt <= (ifin & t_ide) | (idt & ~(as2 & as3));
    cck <= ~fast ? ~q1 : idt ? tc[2] & ~as1 : ~cck;
end
assign CLKCPU = cck;

// ------------------------------------------------------- motherboard cycles 6
// hicnt guards the 68000's AS high time (150 ns). It starts when m_as clears,
// about 10 ns after the pin, and with the pin delays 140 ns here is >150 there.
reg [3:0] hicnt = 0;
reg arm = 0, m_as = 0, m_s4 = 0, m_uds = 0, m_lds = 0, m_avec = 0;
reg busen = 0;
reg p_u = 0, p_l = 0;               // byte lanes
wire m_start = mrise & arm & hicnt[3] & hicnt[2] & hicnt[1];
wire m_dstb  = mrise & m_as & (RW30 | ~ds2);    // one clock after AS
always @(posedge clk) begin
    p_u <= ~A[0];
    p_l <= A[0] | SIZ[1] | ~SIZ[0];
    if (m_as) hicnt <= 0; else if (hicnt != 15) hicnt <= hicnt + 4'd1;
    busen <= m_as | (busen & ~(as2 & as3 & as4));   // 30 ns write hold
end
always @(posedge clk or posedge AS30)
    if (AS30) begin
        arm <= 0; m_as <= 0; m_s4 <= 0; m_uds <= 0; m_lds <= 0; m_avec <= 0;
    end else begin
        if (t_mb & run) arm <= 1;               // address is >40 ns old
        if (m_start) m_as <= 1;
        if (m_dstb)  m_s4 <= 1;
        if ((m_start & RW30) | (m_dstb & ~RW30)) begin
            m_uds <= p_u;
            m_lds <= p_l;
        end
        if (mfall & m_s4 & p_cpu & ~vp2) m_avec <= 1;
    end

// ---------------------------------------------------------- E and VPA cycles 7
// The E pin is 30 ns behind the counter: the CPU latches 10 ns after the
// counter step, so ACIA data are still held, and is off the bus 40 ns after E.
reg [3:0] ec = 0;
reg e0 = 0, e1 = 0, e2 = 0, vma = 0;
always @(posedge clk) begin
    if (mfall) ec <= (ec == 9) ? 4'd0 : ec + 4'd1;
    e0 <= ec[3] | (ec[2] & ec[1]);  // 6..9
    e1 <= e0;
    e2 <= e1;
    if (vp2) vma <= 0;
    else if (mfall & (ec == 2) & m_s4 & ~p_cpu) vma <= 1;
end
assign E    = e2;
assign AVEC = ~m_avec;
wire m_done = mfall & m_s4 & (~dt2 | (vma & (ec == 8)));

// --------------------------------------------------------------- arbitration 8
reg bgo = 1, drv = 0;
always @(posedge clk) begin
    bgo <= ~(~bg3 & ~bg2 & as2 & as3 & ~mbt & ~busen);
    drv <= bgo & ba2;
end
assign BR30    = BR;
assign BGACK30 = BGACK;
assign BG      = bgo;
wire own = drv & BGACK;
assign AS    = own ? ~(m_as & ~AS30) : 1'bz;
assign UDS   = own ? ~(m_uds & ~AS30) : 1'bz;
assign LDS   = own ? ~(m_lds & ~AS30) : 1'bz;
assign VMA   = own ? ~vma   : 1'bz;
assign BUSEN = ~busen;

// ---------------------------------------------------------- reset length 10.5
// 13056 E periods (16.3 ms at 8.02 MHz) clear the shadow.
reg [13:0] rcnt = 0;
reg rlong = 0;
always @(posedge clk) begin
    rlong <= rcnt[13] & rcnt[12] & rcnt[9] & rcnt[8];
    if (rst2) rcnt <= 0;
    else if (mfall & (ec == 9) & ~rlong) rcnt <= rcnt + 14'd1;
end

// ------------------------------------------------------- control register 10.2
// wcap is a single pulse, one clock after the data are known to be valid.
reg  ctl_rdy = 0, wcap = 0;
wire ctl_go = ctl_rdy & t_ctl & run;
reg  ctl_oe = 0, dsk = 0;
always @(posedge clk) begin
    ctl_rdy <= t_ctl & run & (RW30 | ~ds2);
    wcap    <= t_ctl & run & ~RW30 & ~ds2 & ~ctl_rdy & (D[31:20] == 12'he05);
    if (rlong) begin
        shen <= 0; sh512 <= 0;
    end else if (wcap) begin
        sh512 <= D[17]; shen <= D[16];
    end
end
assign D = (ctl_oe & ~AS30) ? {14'b1110_0000_0101_00, sh512, shen} : 16'hzzzz;

// ------------------------------------------------------------------- IDE 11
reg [7:0] ic = 0;
reg [2:0] hc = 0;                   // write data hold, 60 ns
reg ics0 = 0, ics1 = 0, imin = 0, ior = 0, iow = 0, iend = 0;
wire idata = ~A[5] & ~A[4] & ~A[3] & ~A[2];
wire ito   = ic[7] & ic[6];         // 1520 ns of strobe: give up on IORDY
always @(posedge clk) begin
    if (~t_ide) begin
        ic <= 0; hc <= 0; imin <= 0; iend <= 0;
    end else begin
        if (~ito) ic <= ic + 8'd1;
        if (ic == IDE_DAT - 2 && idata || ic == IDE_REG - 2) imin <= 1;
        if (imin & (iw2 | ito)) iend <= 1;
        if (iend & (hc != 6)) hc <= hc + 3'd1;
    end
    ics0 <= t_ide & ~A[5];
    ics1 <= t_ide &  A[5];
end
always @(posedge clk or posedge AS30)
    if (AS30) begin
        ior <= 0; iow <= 0;
    end else begin
        if (t_ide & run &  RW30 & (ic == IDE_SET)) ior <= 1;
        if (iend) iow <= 0;
        else if (t_ide & run & ~RW30 & (ic == IDE_SET)) iow <= 1;
    end
assign IDECS0 = ~ics0;
assign IDECS1 = ~ics1;
assign IOR = ~(ior & ~AS30);
assign IOW = ~iow;
always @(posedge clk) ifin <= t_ide & iend & (RW30 | (hc == 6));
wire ide_done = ifin & t_ide & run;

// ------------------------------------------------- asynchronous termination
reg berr = 0;
always @(posedge clk or posedge AS30)
    if (AS30) begin
        dsk <= 0; ctl_oe <= 0; berr <= 0;
    end else begin
        if (ctl_go | ide_done | m_done) dsk <= 1;
        if (ctl_go & RW30) ctl_oe <= 1;
        if (t_err & run) berr <= 1;
    end
assign DSACK0 = 1'b1;
assign DSACK1 = ~dsk;
assign BERR   = (berr & ~AS30) ? 1'b0 : 1'bz;
assign CIIN   = t_ram;

// ------------------------------------------------------------------- SDRAM 9
// Burst length 4 (single writes), CL 2. CKE low suspends the SDRAM with its data
// on the bus until the CPU has latched them; in a burst, one clock of CKE high
// steps to the next longword. The row is closed with PRECHARGE ALL when AS30 is
// high. Address: bank 25:24, row 23:11, column 10:2.
reg [4:0] inum = 0;                 // initialisation step, 28 = ready
reg tick = 0, rq = 0;
reg z_idle = 1, z_act = 0, z_rcd = 0, z_xfer = 0, z_pre = 0, z_wait = 0;
reg [2:0] wc = 0;
reg xold = 0, wdone = 0, st = 0, fin = 0, gap = 0, cb = 0, oe = 0;
reg [1:0] b = 0;
reg ras = 1, cas = 1, we = 1;
reg rasi = 1, cke = 1;
wire step = st & ~cck & cb;          // CPU is about to latch; next one wanted
reg ready = 0, i_ras = 0, i_cas = 0, i_we = 0, tick2 = 0;
wire slot  = fast & cck;            // CLKCPU falls at the coming edge
wire go    = z_idle & ~rq & ready & t_ram;
wire svc   = z_idle & rq;
wire close = z_xfer & xold & ~t_ram;
wire wr_go = z_xfer & t_ram & ~RW30 & ~ds2 & ~wdone;
wire rd_go = z_rcd & RW30;
// A later burst STERM waits an extra CPU clock if CBREQ has been withdrawn, so
// that the end of an abandoned burst is seen before STERM is given again.
wire first  = (b == 0);
wire launch = slot & z_xfer & t_ram & run & ~fin & ~st & wdone &
              (first | ~cq2 | gap);

always @(posedge clk) begin
    tc   <= tc + 9'd1;
    tick <= tc == 9'h1ff;
    tick2 <= tick;                  // step decoded before it is served
    ready <= inum[4] & inum[3] & inum[2];
    i_ras <= inum[4] & inum[3];
    i_cas <= inum[4] & inum[3] & (inum[2] | inum[1] | inum[0]);
    i_we  <= inum[4] & inum[3] & ~inum[2] & (inum[1] ~^ inum[0]);
    rasi <= ~rst2;
    if (~rst2) begin
        inum <= 0; rq <= 0; wc <= 0;
        z_idle <= 1; z_act <= 0; z_rcd <= 0; z_xfer <= 0; z_pre <= 0; z_wait <= 0;
        ras <= 1; cas <= 1; we <= 1;
    end else begin
        if (tick & ~(inum[4] & inum[3] & inum[2])) inum <= inum + 5'd1;
        if (tick2) rq <= 1; else if (svc) rq <= 0;
        z_idle <= (z_idle & ~svc & ~go) | z_pre | (z_wait & (wc == 7));
        z_act  <= go;
        z_rcd  <= z_act;
        z_xfer <= z_rcd | (z_xfer & ~close);
        z_pre  <= close;
        z_wait <= svc | (z_wait & (wc != 7));
        wc     <= z_wait ? wc + 3'd1 : 3'd0;
        ras <= ~(go | close | (svc & i_ras));
        cas <= ~(rd_go | wr_go | (svc & i_cas));
        we  <= ~(close | wr_go | (svc & i_we));
    end
    xold <= z_xfer;
    cke  <= ~(z_xfer & RW30 & t_ram & run & rst2) | step;
    if (~z_xfer) begin
        wdone <= 0; fin <= 0; gap <= 0; b <= 0; st <= 0;
    end else begin
        if (wr_go | RW30) wdone <= 1;
        st  <= launch | (st & ~cck);
        gap <= ~st & ~first & (gap | slot);
        if (st & ~cck) begin        // the CPU is sampling STERM
            if ((first & ~cb) | (b == 3)) fin <= 1; else b <= b + 2'd1;
        end
    end
end
always @(posedge clk or posedge AS30)
    if (AS30) begin
        cb <= 0; oe <= 0;
    end else begin
        if (z_act & run) oe <= 1;
        if (~st) cb <= t_ram & run & RW30 & ~cq2 & ~A[3] & ~A[2] & ~p_vec;
    end
assign STERM = ~st;
assign CBACK = ~cb;
assign RAMOE = ~oe;

reg [12:0] ar = 0;
reg [1:0]  bk = 0;
reg [3:0]  dm = 4'hf;
reg  col = 0;
wire [12:0] row = A[23:11] | {{5{p_ovl}}, 8'd0};
wire byt = ~SIZ[1] & SIZ[0], wrd = SIZ[1] & ~SIZ[0], lng = ~SIZ[1] & ~SIZ[0];
wire [3:0] ln;
assign ln[3] = ~A[1] & ~A[0];
assign ln[2] = ~A[1] & (A[0] | ~byt);
assign ln[1] = (A[1] & ~A[0]) | (~A[1] & A[0] & ~byt) | (~A[1] & ~A[0] & ~byt & ~wrd);
assign ln[0] = (A[1] & A[0]) | (A[1] & ~byt) | (A[0] & ~byt & ~wrd) | lng;
always @(posedge clk) begin
    col <= z_act | z_rcd | z_xfer;
    if (~ready) begin
        ar <= 13'h0222;             // mode register: CL 2, read burst 4
        ar[10] <= ~inum[1];         // precharge all
    end else if (col) begin
        ar <= {4'b0000, A[10:2]};
        ar[10] <= close;
    end else
        ar <= row;
    bk <= A[25:24] & {2{ready & ~p_ovl}};
    dm <= ~({4{col & RW30}} | ({4{col}} & ln));
end
assign ARAM = ar;
assign BA   = bk;
assign DQM  = dm;
assign {RAS, CAS, RAMWE} = {ras, cas, we};
assign RAMCS   = rasi;              // inhibited during reset
assign CLKRAME = cke;
assign CLKRAM  = CLK100M;

endmodule
