# Measurements

## berr1.sr: BERR release on a plain STE (2026-11-26)

STE without the TF536, BERRTEST.PRG reading `$FFFA40`. Kingst LA2016 with
sigrok, 200 MHz (5 ns resolution), threshold 1.4 V, triggered on BERR falling,
10 ms. Open it with PulseView, or `sigrok-cli -i berr1.sr`.

| Channel | Signal |
|---|---|
| 0 | AS |
| 1 | BERR |
| 2 | DTACK |
| 3 | UDS |
| 4 | LDS |
| 5 | R/W |
| 6 | A1 |
| 7 | CLK8 |

487 bus errors, all word reads (R/W high, A1 low, UDS and LDS low).

- BERR held after AS rises: 70-80 ns, mean 74 ns.
- BERR low for 400-410 ns.
- CLK8 period 124.7 ns (8.02 MHz).
- AS rises 20-30 ns after a CLK8 falling edge.
- BERR rises 30-45 ns after a CLK8 rising edge, and falls 5-10 ns after one.

So GLUE releases BERR on the first CLK8 rising edge after it sees AS high,
about 35 ns after that edge. With a 68000, AS always rises at the same point
in the clock, half a clock before that edge, which gives the 70-80 ns. A 68030
negates AS at any point in the CLK8 cycle, so the release can come up to about
one CLK8 period plus 45 ns, about 170 ns, after AS. The full-speed variant
holds BR30 until BERR is high (section 16 of the specification).
