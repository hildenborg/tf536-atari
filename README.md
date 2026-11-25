# TF536-ATARI: TF536 Rev 2 firmware for the Atari ST/STE

Replacement CPLD firmware for the TF536 Rev 2 accelerator (68030, 64 MB SDRAM,
IDE) fitted in the 68000 socket of an Atari ST or STE. Written from
[FIRMWARE_SPEC.md](FIRMWARE_SPEC.md). **Not yet run on hardware.**

| Path | Contents |
|---|---|
| `rtl/tf536atari.v`, `rtl/tf536atari.ucf` | Design and pins |
| `build.sh [phase]` | ISE 10.1 build in podman (output in `build/phaseN`) |
| `firmware/` | `.jed`, `.svf`, checksums and fitter report per phase; builds add a timing report (`.tim`, not in git) |
| `sim/tb.v`, `sim/run.sh` | Bench; `run.sh matrix`, `long`, `mutate`, `gate` or `all`. Needs Icarus Verilog and Python 3 |
| `sim/abel2v.py` | Converts a fitter report to a gate model for `run.sh gate` |
| `tools/jtag/` | Programming scripts |
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

## Timing (fitter report, worst case)

- Every register-to-register path is at most 10.0 ns: zero margin at 100 MHz
  by the speed file, but nothing exceeds it. `build.sh` fails if one does.
- SDRAM: outputs 5.8 ns, CLKRAM 10.0 ns. Commands are set up 4.2 ns and held
  5.8 ns around the clock edge (worst-case numbers; both scale together).
- Read data: CL 2, valid by 27.5 ns after the READ edge; CPU latches at 35.8 ns
  or later. The data are then held by clock suspend (CKE).
- 68000 strobes: 18.0 ns to assert, 14.5 ns from AS30 to negate.

## Choices worth knowing

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
delays. `sim/run.sh` repeats all of this and fails if any of it does. The models
are the author's reading of the datasheets.

Not verified: anything on a board; signal integrity; the 68030's behaviour if
CBREQ is withdrawn exactly as STERM is given; socket-side masters other than a
simple BR/BG/BGACK sequence.

## License

MIT, see [LICENSE](LICENSE).
