# TF536 Rev 2 firmware for the Atari ST/STE: clean-room specification

Version 1.0, 2026-11-25

## 1. Purpose and rules

This document specifies a replacement firmware for the CPLD on the TF536 Rev 2
accelerator (68030, 64 MB SDRAM, IDE), fitted in the 68000 socket of an Atari ST
or STE. It describes the hardware, what the firmware must do and how to check
it. It does not describe how any existing firmware is built internally.

### 1.1 Clean-room rules

- The implementer must not have read any existing TF530, TF534 or TF536 firmware
  source or constraint files, or testbenches from those projects, and must not
  consult them during the work.
- The implementer may use this document and public datasheets (section 14).
- Questions go in writing to the specification author. Answers may state
  hardware facts or required behaviour, never code or internal structure. Keep
  the questions and answers with this document.
- A reviewer who is not the implementer should check this document for
  protected expression before it is handed over, and compare the finished work
  with the original afterwards.
- Choose your own module names, state machines, encodings and counters. Where
  this document gives a formula or number, it is a hardware constraint or an
  interface that software depends on.

### 1.2 Requirement labels

| Label | Meaning |
|---|---|
| **HW** | Fact about the board, from its schematic |
| **STD** | From a component datasheet or bus standard; the datasheet wins if they differ |
| **REQ** | Required behaviour |
| **OBS** | Measured at the pins of the existing firmware in logic simulation (no chip delays). A reference, not a requirement, unless a REQ repeats it |
| **REC** | Recommended; not proven on hardware |

Numbers starting with `$` are hexadecimal. "Asserted" means driven to the active
level; signals marked (L) are active low. No variant of the existing firmware
described here has yet been run in an ST or STE, so nothing in this document is
proven in the target machine.

## 2. System overview

```
 68030 ──A0-31, D0-31, control──┬── CPLD ── control ── 68000 socket (ST/STE)
   │                            │
   │ D0-31 ──bus switches────── SDRAM 2 x 16Mx16  (64 MB, 32 bits wide)
   │ D16-31 ──buffers────────── 68000 socket D0-15
   │ D16-31 ──buffers────────── IDE connector
   └ A1-23, FC0-2, R/W, HALT, RESET, BERR ── 68000 socket directly
```

The CPLD is an XC95288XL-10TQ144: 288 macrocells, 1440 product terms, no RAM. It
must:

1. Generate the 68030 clock (section 5).
2. Turn 68030 cycles into 68000 cycles on the motherboard (section 6).
3. Emulate the 68000's 6800-style bus cycles, E clock and autovectors (section 7).
4. Pass bus arbitration to the 68030 (section 8).
5. Control the SDRAM (section 9).
6. Provide a ROM shadow with a control register (section 10).
7. Provide an IDE interface (section 11).

## 3. Board facts

### 3.1 CPLD pins (HW)

Direction is as seen from the CPLD.

| Signal | Pin(s) | Direction | Notes |
|---|---|---|---|
| A0–A31 | 101, 107, 139, 138, 137, 136, 135, 134, 133, 132, 131, 130, 128, 129, 126, 125, 124, 121, 120, 119, 118, 117, 116, 115, 113, 112, 111, 110, 106, 105, 103, 102 | in | CPU address, in order |
| D16–D31 | 39, 41, 44, 46, 49, 51, 53, 56, 54, 52, 50, 48, 45, 43, 40, 38 | bidir | CPU data, in order. D0–D15 do not reach the CPLD |
| SIZ0, SIZ1 | 79, 83 | in | CPU transfer size |
| FC0–FC2 | 98, 96, 95 | in | Function code |
| AS30 | 86 | in | CPU address strobe (L); 2.2 kΩ pull-up |
| DS30 | 82 | in | CPU data strobe (L); pull-up |
| RW30 | 80 | in | CPU read (1) / write (0); pull-up; also drives the socket R/W and the data buffers' direction |
| DSACK0 | 93 | out | (L) |
| DSACK1 | 92 | out | (L) |
| STERM | 91 | out | (L) synchronous termination |
| BERR | 87 | open drain | (L) shared by CPU and socket |
| AVEC | 30 | out | (L) autovector |
| CBREQ | 81 | in | (L) CPU burst request |
| CBACK | 85 | out | (L) burst acknowledge |
| CIIN | 78 | out | (L) cache inhibit in |
| CLKCPU | 94 | out | 68030 clock |
| CLK100M | 32 | in | 100 MHz oscillator; a global clock pin |
| CLK7M_RAW | 66 | in | Socket clock, 8 MHz on the ST; not a global clock pin |
| RESET | 74 | in | (L) shared by socket, CPU and IDE |
| AS | 77 | tristate out | (L) socket address strobe |
| UDS | 76 | tristate out | (L) |
| LDS | 75 | tristate out | (L) |
| DTACK | 60 | in | (L) |
| VPA | 68 | in | (L) |
| VMA | 70 | tristate out | (L) |
| E | 69 | out | E clock |
| BR | 71 | in | (L) socket bus request |
| BR30 | 97 | out | (L) bus request to CPU |
| BG30 | 100 | in | (L) bus grant from CPU; pull-up |
| BG | 61 | out | (L) bus grant to socket |
| BGACK | 64 | in | (L) from socket |
| BGACK30 | 104 | out | (L) to CPU |
| IPL0 | 143 | high-Z | see 7.4 |
| IPL1 | 142 | high-Z |  |
| IPL2 | 140 | high-Z |  |
| BUSEN | 88 | out | (L) enables the two CPU/socket data buffers |
| CLKRAM | 4 | out | SDRAM clock |
| CLKRAME | 5 | out | SDRAM CKE |
| RAMCS | 21 | out | (L) |
| RAS | 20 | out | (L) |
| CAS | 19 | out | (L) |
| RAMWE | 17 | out | (L) |
| RAMOE | 2 | out | (L) closes the 32-bit SDRAM bus switches |
| ARAM0–ARAM12 | 25, 26, 27, 28, 14, 13, 12, 11, 10, 9, 24, 7, 6 | out | SDRAM address, in order |
| BA0, BA1 | 23, 22 | out | SDRAM bank (crossed at the chips, which is harmless) |
| DQM0–DQM3 | 3, 15, 31, 16 | out | Byte masks, see 3.3 |
| IDECS0, IDECS1 | 33, 59 | out | (L) to IDE pins 37 (CS0) and 38 (CS1) |
| IOR | 57 | out | (L) IDE read strobe; also the IDE data buffers' direction |
| IOW | 58 | out | (L) IDE write strobe |
| IDEWAIT | 34 | in | IORDY; 1 kΩ pull-up to 3.3 V |
| IDEINT | 35 | in | Drive interrupt; 1 kΩ pull-down |

There are 117 signal pins, all used. JTAG is on 63 (TDI), 65 (TMS), 67 (TCK) and
122 (TDO). `BR`, `DTACK` and similar socket signals are 5 V levels; the CPLD's
inputs tolerate 5 V.

### 3.2 Direct connections between the 68030 and the socket (HW)

A1–A23, FC0–FC2, R/W, IPL0–IPL2, HALT, RESET and BERR connect directly. The
socket therefore sees the CPU's address, function code and R/W during **every**
CPU cycle, card-local ones included. Only AS, UDS, LDS and VMA tell the
motherboard that a cycle is meant for it.

A24–A31 have 2.2 kΩ pull-ups. The CPU cache and MMU have disable jumpers. The
CPU's cache-inhibit output is not connected.

### 3.3 Data paths (HW)

| Path | Parts | Control |
|---|---|---|
| CPU D24–D31 ↔ socket D8–D15; CPU D16–D23 ↔ socket D0–D7 | 2 × 74VHC245 | Enabled by BUSEN low. Direction from R/W: read = socket to CPU |
| CPU D0–D31 ↔ SDRAM | 4 × SN74CB3T3245 switches | Closed by RAMOE low; bidirectional |
| CPU D16–D31 ↔ IDE data | 2 × 74VHC245 | **Always enabled.** IOR low = drive to CPU; IOR high = CPU to drive |
| IDE strobes, chip selects, A2–A4 → IDE | 74VHC245 | Always enabled, one direction |

Consequences (REQ):

- IOR must be low only during an IDE read, because it makes the buffers drive
  D16–D31. Never assert IOR with any other driver of D16–D31 active.
- BUSEN must be low only during a motherboard cycle run by the CPU, so that
  socket and card data never meet. It must be high while another master owns
  the bus.
- RAMOE must be low only during an SDRAM access.
- The CPLD may drive D16–D31 only for a read of the control register (10.2).

SDRAM byte masks: DQM3 masks D24–D31, DQM2 D16–D23, DQM1 D8–D15, DQM0 D0–D7.

### 3.4 IDE connector (HW)

| Drive signal | CPU signal |
|---|---|
| D0–D7 | D24–D31 (D0 = D24 … D7 = D31) |
| D8–D15 | D16–D23 (D8 = D16 … D15 = D23) |
| DA0, DA1, DA2 | A2, A3, A4 |
| CS0, CS1 | IDECS0, IDECS1 |

The drive's low byte is on the **even** byte lane, the reverse of an Atari
Falcon. The schematic's IDE data net names are not drive bit numbers.

### 3.5 SDRAM (HW, STD)

Two MT48LC16M16A2P-6A: 4 banks, 8192 rows, 512 columns, 16 bits each, forming one
32-bit, 64 MB memory. Both share all control and address lines.

### 3.6 Sockets and power

The STE's 68000 is a soldered PLCC, so an adapter is needed. JTAG1: 1 TMS, 2 TDI,
3 TDO, 4 TCK, 5 GND, 6 3.3 V.

## 4. Address map (REQ)

All comparisons use all 32 address bits unless stated. "CPU space" (FC = 7) is
never memory: it must not select any window below.

| CPU address | Cycle | Target |
|---|---|---|
| `$01000000–$04FFFFFF` | any | SDRAM, 32-bit port. With the shadow on, see `$04F80000` |
| `$04F80000–$04FFFFFF` | any, shadow on | Bus error, no access |
| `$05000000–$0500FFFF` | any | Control register, 16-bit port |
| `$00E00000–$00E3FFFF`, `$FFE00000–$FFE3FFFF` | read, shadow on | SDRAM at `$04F80000` + offset |
| `$00E40000–$00E7FFFF`, `$FFE40000–$FFE7FFFF` | read, shadow on, 512 KB | SDRAM at `$04FC0000` + offset |
| `$00000000–$00000007` | read, shadow on | SDRAM at `$04F80000–$04F80007` |
| `$00F00000–$00F0003F`, `$FFF00000–$FFF0003F` | any | IDE, 16-bit port |
| CPU space type 2 (coprocessor) | any | Bus error |
| CPU space type 15 (interrupt acknowledge) | read | Motherboard, section 7 |
| everything else | any | Motherboard, 16-bit port |

- Motherboard cycles use A1–A23, so an address such as `$06000000` reaches the
  motherboard as `$000000`. Software relies on the `$FFxxxxxx` I/O area
  working this way (STD: the 68030 sign-extends short absolute addresses).
- The CPU-space type is A16–A19 (STD). The CPU puts ones on A20–A31 for an
  interrupt acknowledge; check FC before any address window.
- REC: also bus error CPU space types 0 and 1 (breakpoint, access level). The
  existing firmware runs them on the motherboard.

## 5. Clocks and reset

### 5.1 CPU clock (REQ)

- **Card-local cycles and idle:** 50 MHz, half of CLK100M, 50% duty.
- **Motherboard cycles:** the CPU clock must run at the socket clock's 8 MHz
  with a fixed phase to it, so that the 68030's asynchronous cycle fits the
  68000's bus states.
- **While another master holds the bus (BGACK low) or RESET is low:** the socket
  clock rate. RESET matters because the 68030's RESET instruction lasts 512 CPU
  clocks: 64 µs at 8 MHz, but only 10 µs at 50 MHz.
- **Switching** must be free of glitches: no high or low phase shorter than the
  68030's minimum for the fitted part, whatever the phase of the 8 MHz clock
  at that moment. 
- Interrupt acknowledge and all other CPU-space cycles use the slow clock.
- Control-register and bus-error cycles may use either (OBS: slow).

OBS: CPU clock edges in slow mode are opposite in phase to the socket clock
(CPU falls about 7 ns after the socket clock rises) with the default
phase setting.

### 5.2 Socket clock recovery (REQ)

The 8 MHz socket clock is asynchronous to 100 MHz and arrives on an ordinary
pin. Sample it with CLK100M and reject glitches and edge
ringing; the method must tolerate a 62.5 ns half period with margin.

Provide a build-time **phase** option, in 10 ns steps, that shifts the recovered
clock relative to the socket clock. The recovered clock should line up
with the real one at the socket. Input and output delays (about 5–10 ns) count
towards the alignment. The best value is unknown until measured on a machine, so
expect to try at least three neighbouring values.

### 5.3 SDRAM clock

CLKRAM is CLK100M passed through (REQ: 100 MHz, any latency budget worked out
from the real delays, section 12).

### 5.4 Reset (REQ)

- RESET is an input only; never drive it.
- During RESET low the SDRAM controller goes to its initial state.
- SDRAM contents must survive resets up to the limit in 10.5, so initialisation
  afterwards must not destroy data (it doesn't in SDRAM; avoid anything that
  writes).
- Power-up state: shadow off, all strobes inactive, D16–D31 and IPL undriven.

## 6. Motherboard cycles

### 6.1 Generation (REQ)

A CPU cycle not claimed by the card (section 4) becomes one 68000 cycle:

- Address, FC and R/W are already on the socket; the CPLD times the strobes to
  the 68000's bus states (STD: MC68000 user manual).
- **Read:** AS with UDS and/or LDS during S2, with setup time from address.
- **Write:** AS during S2, UDS/LDS during S4. Data must be valid first; BUSEN
  must therefore be low in time.
- **Byte lanes:** UDS asserted when A0 = 0. LDS asserted unless it is a byte
  access (SIZ1 SIZ0 = 01) to an even address. (STD: 16-bit port rules.)
- **Termination:** sample DTACK at the 68000's points, then assert DSACK1 alone
  (16-bit port). DSACK0 is never asserted.
- DSACK must be negated after AS30 negates and before the CPU's next cycle
  samples it.
- AS, UDS, LDS must go inactive after AS30 goes inactive, meeting 68000 hold
  times. BUSEN must follow AS.
- AS, UDS, LDS and VMA are tristate outputs: undriven while another master owns
  the bus (BGACK low), and not asserted in card-local cycles (OBS: undriven
  there too).
- A cycle that begins right after a 50 MHz cycle must not start AS too early
  relative to the socket clock, and must leave the 68000's minimum AS-high
  time between cycles.
- There is no card timeout: the ST's own logic asserts BERR, which reaches
  the CPU directly.
- All motherboard cycles must assert CIIN (low). The 68030's caches would
  otherwise hold stale data after DMA, and registers must not be cached.
- TAS (read-modify-write) must work as two cycles; the existing firmware makes
  no special provision.

### 6.2 Observed timing (OBS)

8.06 MHz clock, DTACK answered at the first clock fall after UDS/LDS. Times in
ns from the rise of the socket clock that begins the strobe, phase option at its
default:

| Event | Read | Write |
|---|---|---|
| Socket clock rises | 0 | 0 |
| AS low | +7 | +7 |
| UDS/LDS low | +7 | +127 (one clock later) |
| BUSEN low | +17 | +17 |
| DTACK low (stimulus) | +62 | +186 |
| DSACK1 low | +127 | +187 |

The wait from AS30 low to AS low depends on the phase of the socket clock: 105 to
135 ns in the samples measured when the CPU had been running at 50 MHz.

## 7. Interrupts, VPA cycles, E clock

### 7.1 E clock (REQ, STD)

E is the socket clock divided by 10: low for 6 clocks and high for 4. It
runs continuously, also across resets.

### 7.2 VPA cycles (REQ, STD)

If the motherboard answers with VPA instead of DTACK, complete the cycle in step
with E: assert VMA (low) a suitable time before E rises, keep it until after E
falls, and terminate with DSACK1 so that the CPU latches data near the end
of E high. The ST's keyboard and MIDI ACIAs use this.

OBS: with VPA low 60 ns after AS, VMA fell about 50 ns later and DSACK1 620 ns
after VMA. This depends on the phase of E.

VMA must not be asserted for CPU space. VMA returns high when VPA does.

### 7.3 Interrupt acknowledge (REQ)

Interrupt acknowledge runs on the motherboard as a normal cycle: the ST's MFP
returns a vector with DTACK, while HBL and VBL answer with VPA. When VPA is
asserted during an interrupt acknowledge, assert AVEC (low) to the CPU until
the cycle ends. A vectored acknowledge ends with DSACK1.

### 7.4 IPL (REQ)

Never drive IPL0–IPL2. They belong to the ST's chipset, and level 2 is its
horizontal blank interrupt, so a card interrupt there would break the machine.
IDE is polled; IDEINT is unused.

### 7.5 Coprocessor space (REQ)

There is no FPU. A CPU space type 2 cycle must assert BERR until AS30 negates, so
that software detects "no FPU" (a line-F exception follows). No motherboard AS.

## 8. Bus arbitration (REQ)

- Socket BR passes to BR30 and socket BGACK to BGACK30.
- BG30 passes to BG, but hold BG inactive while a motherboard cycle boundary
  is being synchronised, so that a master never sees a grant before the
  previous cycle's strobes are off.
- While BGACK is low the card drives nothing on the socket except E and BG,
  and BUSEN stays high. AS30 is pulled up, so no card cycle starts.
- The ST's DMA and blitter then access ST RAM without the card's involvement;
  there is no snooping, which is why ST RAM is not cached (6.1).
- Card SDRAM is not reachable by other bus masters.
- The CPU may keep running from its caches while it does not own the bus, and
  refresh continues.

## 9. SDRAM

### 9.1 Required operation

- Initialise per the datasheet after reset: at least 100 µs of NOP/INHIBIT,
  precharge all, two auto refreshes, mode register load. OBS: first access
  completes about 143 µs after RESET rises. Accesses started earlier must simply
  wait; there is no timeout.
- **Refresh: 8192 auto refreshes in 64 ms, so one at least every 7.8 µs on average.**
  The existing firmware does one every 20.48 µs, which breaks the
  datasheet limit by 2.6 times. Do not copy this.
- Any row/column/bank arrangement of the 64 MB is allowed, as it is
  invisible to software. Meet tRCD, tRP, tRAS, tRC, tRFC, tWR for a -6A part at
  100 MHz, including when refresh, write and access follow each other closely.
- Never open a bank that is already open; a reset may arrive mid-access, so
  precharge all banks during initialisation.
- Read, write and refresh must never be lost or repeated when a refresh request
  coincides with an access.

### 9.2 CPU interface (REQ)

- 32-bit port terminated with STERM (synchronous), so all sizes and alignments
  follow the 68030's 32-bit synchronous port rules. DSACK stays inactive.
- CIIN inactive (high) for SDRAM: cacheable. OBS: CIIN is high and RAMOE low
  from the first 100 MHz edges after AS30 falls; both return when AS30 rises.
- Writes enable only the addressed byte lanes:

| SIZ1 SIZ0 | A1 A0 = 00 | 01 | 10 | 11 |
|---|---|---|---|---|
| 01 byte | 3 | 2 | 1 | 0 |
| 10 word | 3, 2 | 2, 1 | 1, 0 | 0 |
| 11 three bytes | 3, 2, 1 | 2, 1, 0 | 1, 0 | 0 |
| 00 long | 3, 2, 1, 0 | 2, 1, 0 | 1, 0 | 0 |

  Entries are DQM numbers to unmask (STD). Reads enable all lanes.
- A write must not use data before DS30 falls.

### 9.3 Burst reads (REQ)

- If CBREQ is low on a read whose A3–A2 = 00, deliver a four-longword line
  with CBACK low and one STERM per longword, in ascending address order (the
  68030 wraps within the line, STD).
- CPU bursts not starting at A3–A2 = 00 may be refused (CBACK high, one longword).
- No write bursts. If the CPU withdraws CBREQ, deassert CBACK.

### 9.4 Observed speed (OBS)

At 50 MHz, from AS30 low: STERM falls about 45 ns later for a read and for a
write; burst longwords follow every 40 ns (four in about 165 ns). Any equal or
faster timing is welcome if it meets section 12. Slower is acceptable.

## 10. ROM shadow

### 10.1 Purpose

The card has no ROM. Software copies a 256 or 512 KB TOS image into SDRAM at
`$04F80000` and then enables the shadow. The machine's ROM window then reads
from fast SDRAM, and a software reset starts the loaded image. The ST's own
ROM returns after a long reset or a power cycle.

### 10.2 Control register (REQ: software interface)

Address `$05000000`, 16-bit port, repeated throughout `$0500xxxx`.

| Bits | Read | Write |
|---|---|---|
| 15–4 | `$E05` | Must be `$E05`, or the write is ignored |
| 3–2 | 0 | Ignored |
| 1 | 512 KB window | 0 = 256 KB, 1 = 512 KB |
| 0 | Enabled | 0 = off, 1 = on |

Bits 15–0 are CPU D31–D16. Both bits change together, on completion of one word
write. Only word accesses are defined. Writes are terminated with DSACK1 like
reads. The register works with the shadow on or off; it must be unreachable from
CPU space. The register is not cacheable (CIIN low).

A card without this firmware does not return `$E05x`, so software detects the
feature by reading the register.

### 10.3 While enabled (REQ)

1. Reads in the windows of section 4 return the SDRAM copy, with the 64 MB address
   `$04F80000` + (address mod 512 KB). In 256 KB mode the upper half
   (`$E40000–$E7FFFF`) goes to the motherboard.
2. Reads of `$0–$7` return the copy's first eight bytes: the reset stack pointer
   and program counter.
3. **Writes** to the windows, and to `$0–$7`, go to the motherboard (a bus
   error there, as with ROM). They must never change the copy.
4. **No burst at `$0–$7`**: bytes `$8–$F` are RAM and must not be read from
   the copy. Refuse the burst (CBACK high). Bursts in the window are allowed.
5. `$04F80000–$04FFFFFF` is bus-errored for reads and writes, without any
   SDRAM access, so that the OS does not find the copy as free RAM.
   Alt-RAM is then `$01000000–$04F7FFFF`.
6. The window hits are cacheable, like other SDRAM.
7. CPU space never matches.

### 10.4 While disabled (REQ)

The windows and vectors go to the motherboard, and the whole
`$01000000–$04FFFFFF` is plain RAM, so software can write the copy.

### 10.5 Resets (REQ)

- A reset of up to 15 ms keeps the enable bits. The RESET instruction (64 µs)
  must always keep them.
- A reset of 17 ms or more clears both bits. The nominal threshold is 16.4 ms.
- Time the reset from the socket clock, since it is what the machine provides in reset.
- The threshold must stay well below the 64 ms refresh period, because refresh
  stops during reset and the copy must survive a reset that keeps the shadow on.
- A power cycle clears the bits.

## 11. IDE

### 11.1 Addressing (REQ)

`$F00000–$F0003F`, plus the same offset at `$FFF00000`. A5 = 0 selects CS0, A5 = 1
selects CS1. A2–A4 select the drive register. A0 and A1 are ignored.

| Offset | Register (CS0) | | Offset | Register (CS1) |
|---|---|---|---|---|
| `$00` | Data (16 bits) | | `$38` | Alternate status / device control |
| `$04` | Error / features | | | |
| `$08` | Sector count | | | |
| `$0C` | Sector number / LBA 0–7 | | | |
| `$10` | Cylinder low / LBA 8–15 | | | |
| `$14` | Cylinder high / LBA 16–23 | | | |
| `$18` | Drive/head | | | |
| `$1C` | Status / command | | | |

Because of 3.4, 8-bit registers appear on the even byte (`$F0001C` for status),
and data words have their bytes exchanged relative to a Falcon. Leave this as
it is: EmuTOS detects it as a "twisted cable" by probing the even addresses, and
corrects it in software.

The port is 16 bits wide (DSACK1). The motherboard must not see the cycle (no
AS). CIIN low. A 32-bit CPU access becomes two 16-bit cycles at offsets
`$00` and `$02`, both of which select the data register.

### 11.2 Strobe timing (REQ, PIO mode 0, STD)

| | Minimum | OBS |
|---|---|---|
| Address and CS valid before strobe | 70 ns | about 425 ns |
| Data strobe (CS0 register 0) | 165 ns | 200 ns at the CPLD |
| Register strobe (all others) | 290 ns | 320 ns |
| Cycle time, strobe start to strobe start | 600 ns | 680 ns |
| Write data hold after IOW rises | 30 ns | 60 ns at the CPLD, before DSACK1 |

- Honour **IORDY** (IDEWAIT): extend the strobe while it is low, after
  synchronising it. Drives may hold it up to 1250 ns. End the cycle normally after
  about 1500 ns even if it stays low, so a bad drive cannot hang the machine.
- The minimums must hold **at the drive**. Allow for the strobe reaching the
  drive up to 26 ns later than DSACK reaches the CPU (up to 18 ns CPLD output,
  8 ns buffer).
- Reads: keep IOR low until AS30 rises, so the CPU latches stable data.
  DSACK1 only after the full strobe time.
- Writes: raise IOW first, then assert DSACK1, so the CPU holds data.
- If the timings are configurable, build with mode 0 by default.

### 11.3 No drive

The IDEWAIT pull-up makes an empty connector ready. All cycles must still end
normally, with undefined data.

## 12. Timing budget

- Device: XC95288XL-10. Logic on the 100 MHz clock has 10 ns from register to
  register. REQ: run the vendor's timing analysis and report every path over 10 ns;
  justify each one (multi-cycle) or remove it. The existing firmware has some up to
  12.6 ns.
- Clock-to-output of the existing build is 10–26 ns (slow slew). Include CLKRAM's
  own output delay when calculating SDRAM setup and hold: what matters is the
  difference between outputs.
- Synchronise every asynchronous input (socket clock, DTACK, VPA, BR/BGACK
  where used in clocked logic, RESET release, IORDY).
- The CPU drives AS30, DS30 and address from CLKCPU, so know the relation between
  CLKCPU's output delay and what the CPLD sees.
- Never clock logic from a decoded or gated signal unless glitch-free.

## 13. Acceptance tests

### 13.1 Simulation

Write new testbenches with a 68030 bus model, a socket model (DTACK and VPA
responders), an SDRAM model that rejects protocol errors, and an IDE model.

| # | Test | Pass condition |
|---|---|---|
| 1 | Word read and write to the motherboard, all phases of the 8 MHz clock | AS/UDS/LDS timing per 68000; DSACK1 only; CPU clock has no short phases |
| 2 | Byte accesses, even and odd | Only the right strobe |
| 3 | DTACK never arrives | Cycle waits; external BERR ends it |
| 4 | VPA read | VMA and DSACK1 in step with E; E is 4/6 |
| 5 | Interrupt acknowledge, VPA and DTACK | AVEC; vector read with DSACK1 |
| 6 | Coprocessor cycle | BERR, no AS |
| 7 | BR/BGACK during motherboard and SDRAM cycles | No drive conflict; strobes off before BG is usable |
| 8 | SDRAM: every address line, all four banks | Distinct locations |
| 9 | SDRAM: all sizes and alignments | Only addressed bytes change |
| 10 | SDRAM burst, and burst from a non-aligned start | Four correct longwords; one longword |
| 11 | SDRAM with refresh colliding, long run | No error; average refresh at most 7.8 µs |
| 12 | Control register: key, bits, aliases, CPU space | Per 10.2 |
| 13 | Shadow 256 KB and 512 KB: first, last and neighbouring addresses | Per 10.3 and section 4 |
| 14 | Shadow vectors at `$0–$7`, `$8` | Copy; motherboard; no burst |
| 15 | Writes to window and vectors | Motherboard; copy unchanged |
| 16 | Protected copy, read and write, first and last | BERR; no motherboard AS; memory unchanged |
| 17 | Reset of 64 µs, 15 ms, 17 ms | On, on, off; SDRAM data kept for the first two |
| 18 | IDE data and register timing, back to back | 11.2, with the strobe 26 ns late |
| 19 | IORDY: short, 1 µs, stuck low | Extended, extended, ends |
| 20 | Whole run | IPL never driven; D16–D31 only driven for the control register |
| 21 | Phase options | All of the above at every phase offered |

Then break the design on purpose (wrong bank, missing key check, no hold time,
no reset limit) and confirm that a test fails for each.

### 13.2 Hardware

Use a board that can be reprogrammed, keep the original programming file, and
do these in order, leaving IDE empty until the last step.

1. Plain boot of the machine's TOS: keyboard, mouse, floppy, blitter. Try
   neighbouring phases if unstable.
2. Detection: read `$05000000`, expect `$E050`.
3. SDRAM: full-size pattern test with caches off and on, then leave it idle and
   recheck.
4. Copy the TOS ROM to `$04F80000`, enable the shadow, compare the window.
5. Boot EmuTOS from the copy; warm reset stays in it, reset button returns to TOS
   (reset button length is unverified on the STE).
6. IDE with a disk that may be wiped: read status at `$F0001C` and `$F0001D`;
   the real status should be at the even address. Then let EmuTOS detect,
   read and write it.

## 14. References and open questions

Public references: MC68030 and MC68000 user's manuals, MT48LC16M16A2 datasheet,
XC95288XL datasheet, ATA/ATAPI PIO timing (ATA-4 or later), 74VHC245 and
SN74CB3T3245 datasheets, EmuTOS source (GPL; behaviour only).

| Question | Status |
|---|---|
| Best clock phase at 8 MHz | Calculated, not measured |
| Any behaviour on a real ST/STE | Not tested |
| STE reset button length over 17 ms | Not measured |
| IDE detection by EmuTOS | Read from its source, not tested |
| SDRAM timing margins on the real board | Not measured |
| DMA and arbitration | Specified from wiring and datasheets, never simulated |

This specification covers the CPLD only. The loader program that copies the ROM
image relies only on sections 4 and 10.

## 15. Tool constraints

The available tools are Xilinx ISE 10.1 (XST), which accepts Verilog-2001 and
VHDL, with cpldfit. Any other legal flow for the XC9500XL is fine. Reference
resource use of the existing build, as a size check only: 177 macrocells,
691 product terms, 124 registers.
