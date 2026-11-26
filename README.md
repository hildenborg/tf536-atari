# TF536-ATARI: TF536 Rev 2 firmware for the Atari ST/STE

Replacement CPLD firmware for the TF536 Rev 2 accelerator (68030, 64 MB SDRAM,
IDE) fitted in the 68000 socket of an Atari ST or STE. Written from
[FIRMWARE_SPEC.md](FIRMWARE_SPEC.md). **Not yet run on hardware.**

The clean-room specification was written by Claude (Anthropic's AI model) by
analyzing the TF536 schematics, component datasheets and the simulated pin
behaviour of the existing firmware. It has been reviewed by Mikael Hildenborg.

| Path | Contents |
|---|---|
| `rtl/tf536atari.v`, `rtl/tf536atari.ucf` | Design and pins |
| `rtl/tf536atari_fs.v` | Full-speed variant, see below |
| `build.sh [phase] [fs]` | ISE 10.1 build in podman (output in `build/phaseN`, `build/fs-phaseN`) |
| `firmware/` | `.jed`, `.svf`, checksums and fitter report per phase; builds add a timing report (`.tim`, not in git) |
| `sim/tb.v`, `sim/run.sh` | Bench; `run.sh matrix`, `long`, `mutate`, `gate` or `all`; add `fs` for the variant. Needs Icarus Verilog and Python 3 |
| `sim/abel2v.py` | Converts a fitter report to a gate model for `run.sh gate` |
| `tools/jtag/` | Programming scripts |
| `tools/berrtest/` | BERRTEST.PRG, which makes bus errors for measuring BERR timing; see its README |
| `tools/tosload/` | TOSLOAD.PRG, which loads a TOS image into the ROM shadow and registers the Alt-RAM. Usage is at the top of `tosload.c`; `make` builds it with an Atari cross-compiler |

## Programming

    tools/jtag/cpld.sh id                                        # reads only
    tools/jtag/cpld.sh program firmware/tf536-atari_phase1.jed   # asks, then verifies
    tools/jtag/cpld.sh restore original.jed                      # any other .jed

This needs a USB-Blaster, OpenOCD and podman. `program` also uses the `.svf` and
`.sha256` next to the `.jed`; `build.sh` makes all three, and
`cpld.sh svf FILE.jed` remakes the `.svf`. Firmware whose checksums do not match
`rtl/` is refused. `restore` programs any other `.jed`, such as the board's
original firmware, without that check.

Start with `tf536-atari_phase1.jed`; by the pin delays it puts AS about 12-22 ns after
the socket clock rise. Phase 0 is 10 ns earlier, 2 and 3 are later.
Follow section 13.2 of the specification and leave IDE empty until the end.

## Full-speed variant

The standard firmware slows the CPU to 8 MHz for motherboard cycles, and to
12.5 MHz at the end of an IDE cycle. Both are below the 68030's minimum clock
(25 MHz for a 50 MHz part). The variant, `firmware/tf536-atari-fs_phaseN.jed`,
stays at 25-50 MHz and is made for a 50 MHz 68030. It is described in section 16
of the specification. A motherboard read still takes 4 clocks (499 ns); an IDE
data cycle takes 800 ns instead of 900.

Start with phase 1, as above. A plain STE holds BERR 70-80 ns after AS
(`measurements/`), and with the 68030's AS not in step with CLK8 it can be about
170 ns. The 68030 allows 15 ns. The variant therefore holds BR30 while BERR is
low, so the CPU starts no cycle until it is gone; simulation passes with BERR
held 0-400 ns. Test software that probes for missing hardware, because this
relies on how the 68030 answers BR. A 33 MHz or slower part is out of
specification at 50 MHz with either firmware.

## Timing (fitter report, worst case)

- Every register-to-register path is at most 10.0 ns: zero margin at 100 MHz
  by the speed file, but nothing exceeds it. `build.sh` fails if one does.
- SDRAM: outputs 5.8 ns, CLKRAM 10.0 ns. Commands are set up 4.2 ns and held
  5.8 ns around the clock edge (worst-case numbers; both scale together).
- Read data: CL 2, valid by 27.5 ns after the READ edge; CPU latches at 35.8 ns
  or later. The data are then held by clock suspend (CKE).
- 68000 strobes: 18.0 ns to assert, 14.5 ns from AS30 to negate (the variant
  negates them from the clock, 18.0 ns).

## Choices worth knowing (standard firmware)

- The slow CPU clock is *in phase* with the socket clock, 10 ns late (the OBS in
  5.1 describes the opposite phase). The CPU then samples DTACK and
  latches data where a 68000 does, and a read takes 4 clocks (499 ns).
- Every register-based clock phase is at least 10 ns, whatever the mode switch.
- **Deviation:** the end of an IDE cycle runs the CPU clock at 12.5 MHz, where
  5.1 asks for 50 MHz. At 50 MHz A2-A4 would change before IOR rises at the
  drive, breaking ATA t9 (20 ns).
- Breakpoint and access-level CPU-space cycles are bus errored (REC in section 4).
- SDRAM: one refresh every 5.12 us. Ready 143 us after reset.

## Verified and not verified

Simulated: tests 1-21 of section 13.1, with and without pin delays, all phases,
8.02 and 8.08 MHz, AS30 delays of 3, 5 and 8 ns; 20 deliberate faults, all
detected. The fitted netlists of all four phases also pass the bench with pin
delays. `sim/run.sh` repeats all of this and fails if any of it does. The
full-speed variant passes the same runs (`sim/run.sh all fs`), with 29 faults. The models
are the author's reading of the datasheets.

Not verified: anything on a board; signal integrity; the 68030's behaviour if
CBREQ is withdrawn exactly as STERM is given; socket-side masters other than a
simple BR/BG/BGACK sequence.

## License

MIT, see [LICENSE](LICENSE).
