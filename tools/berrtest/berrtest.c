/*
 * BERRTEST - make bus errors on purpose, for measuring with a logic analyzer
 * how long the machine holds BERR after AS. See README.md for the probes.
 *
 * It tries a few I/O addresses that nothing answers on a plain ST or STE,
 * reports which give a bus error, then reads the first such address over and
 * over (word reads) until a key is pressed. An address can be given instead
 * on the command line in hex (rename to BERRTEST.TTP), e.g. FFFA40.
 *
 * Works on a 68000 and on a 68030 (reads VBR when _CPU says 68010+).
 */

#include <stdio.h>
#include <stdlib.h>
#ifdef __M68K_ATARI_ELF__
#include <tos.h>
typedef int sup_ret_t;
#else
#include <osbind.h>
typedef long sup_ret_t;
#endif

#define MOVEC_VBR_D0 ".word 0x4e7a,0x0801"   /* movec vbr,d0 */
#define P_COOKIES (*(volatile unsigned long **)0x5A0UL)
#define BURST 1000L

/* Unused on a plain ST/STE: 68881 interface (Mega ST), SCC and VME/SCU
 * (Mega STE and TT). $F00000 is not on the list: the TF536 firmware puts
 * its IDE port there. */
static const unsigned long candidates[] = { 0xFFFA40UL, 0xFF8C80UL, 0xFF8E00UL };

static volatile unsigned long g_addr;
static volatile long g_count, g_errors;
static volatile int g_use_vbr;
static volatile unsigned long g_cpu;

static sup_ret_t sup_cpu(void)
{
    volatile unsigned long *jar = P_COOKIES;

    g_cpu = 0;
    if (jar != NULL)
        for (; jar[0] != 0; jar += 2)
            if (jar[0] == 0x5F435055UL) {   /* _CPU */
                g_cpu = jar[1];
                break;
            }
    return 0;
}

/* g_count word reads of g_addr; g_errors gets the number of bus errors. */
static sup_ret_t sup_burst(void)
{
    unsigned long vbase = 0;
    long errors;

    if (g_use_vbr)
        __asm__ volatile (MOVEC_VBR_D0 "\n\tmove.l %%d0,%0"
                          : "=g" (vbase) : : "d0");

    __asm__ volatile (
        "move.l  %1,%%a1\n\t"
        "move.l  8(%%a1),%%d1\n\t"      /* save the bus error vector */
        "lea     2f(%%pc),%%a0\n\t"
        "move.l  %%a0,8(%%a1)\n\t"
        "move.l  %2,%%a0\n\t"
        "move.l  %3,%%d2\n\t"
        "moveq   #0,%0\n"
        "1:\n\t"
        "move.l  %%sp,%%a2\n\t"
        "move.w  (%%a0),%%d0\n\t"       /* the probe */
        "nop\n\t"
        "bra.s   3f\n"
        "2:\n\t"
        "move.l  %%a2,%%sp\n\t"         /* drop the exception frame */
        "addq.l  #1,%0\n"
        "3:\n\t"
        "subq.l  #1,%%d2\n\t"
        "bne.s   1b\n\t"
        "move.l  %%d1,8(%%a1)\n\t"      /* restore the bus error vector */
        : "=&d" (errors)
        : "r" (vbase), "r" (g_addr), "r" (g_count)
        : "d0", "d1", "d2", "a0", "a1", "a2", "cc", "memory");

    g_errors = errors;
    return 0;
}

static long probe(unsigned long addr, long n)
{
    g_addr = addr;
    g_count = n;
    Supexec(sup_burst);
    return g_errors;
}

int main(int argc, char **argv)
{
    unsigned long addr = 0;
    unsigned long total = 0, missed = 0;
    unsigned int i;

    printf("BERRTEST: bus errors for a logic analyzer\r\n");
    Supexec(sup_cpu);
    g_use_vbr = g_cpu >= 10;
    printf("CPU 680%02lu\r\n", g_cpu);

    if (argc > 1) {
        addr = strtoul(argv[1], NULL, 16) & 0xFFFFFEUL;
    } else {
        for (i = 0; i < sizeof candidates / sizeof candidates[0]; i++) {
            int e = probe(candidates[i], 1) == 1;
            printf("$%06lX: %s\r\n", candidates[i], e ? "bus error" : "answers");
            if (e && !addr)
                addr = candidates[i];
        }
        if (!addr) {
            printf("No candidate gives a bus error; give an address in hex.\r\n");
            Cnecin();
            return 1;
        }
    }

    printf("Reading $%06lX over and over. Any key stops.\r\n", addr);
    while (!Cconis()) {
        long e = probe(addr, BURST);
        total += BURST;
        missed += BURST - e;
    }
    Cnecin();
    printf("%lu reads, %lu bus errors, %lu answered.\r\n", total, total - missed, missed);
    printf("Press a key.\r\n");
    Cnecin();
    return 0;
}
