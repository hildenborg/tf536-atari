# BERRTEST.PRG

Makes bus errors on purpose so that a logic analyzer can show how long the
machine holds BERR after AS. The full-speed firmware variant needs this to be
under about 50 ns (section 16 of the specification).

It tries `$FFFA40`, `$FF8C80` and `$FF8E00`, which nothing answers on a plain ST or
STE, and prints which give a bus error. Then it reads the first such address in a
loop until a key is pressed, and prints the counts. Renamed to `BERRTEST.TTP`, it
takes an address in hex instead.

Build with `make`, using the same toolchain as TOSLOAD. Runs on a 68000 or 68030.
Tested only in Hatari (STE, 68000 and 68030), which does not model BERR timing.

## Measuring BERR release (plain STE, no TF536)

Kingst LA2016 at 200 MHz, threshold 1.5 V, at least two ground leads close by.

| Channel | Signal |
|---|---|
| 0 | AS |
| 1 | BERR (trigger: falling edge) |
| 2 | DTACK |
| 3 | UDS |
| 4 | LDS |
| 5 | R/W |
| 6 | A1 |
| 7 | CLK8, the 68000 clock |

Use about 20 us of pre-trigger, start BERRTEST, and capture several times.
Export each capture as CSV or VCD into `measurements/`. What matters is the time
from AS rising to BERR rising, and the longest one seen.
