/*
 * TOSLOAD - run EmuTOS, or the machine's own TOS, from SDRAM using the TF536 ST ROM shadow.
 *
 * Requires the Atari ST CPLD firmware with the ROM shadow (control register
 * at $05000000) and a 68030. See sections 4 and 10 of FIRMWARE_SPEC.md for
 * the hardware side.
 *
 * Two modes, picked automatically:
 *
 *  1. Shadow off (running the real TOS):
 *     Loads an EmuTOS ROM image (default \EMUTOS.IMG) into the top 512KB of
 *     the TF536 SDRAM ($04F80000), enables the shadow so that $E00000 and the
 *     reset vectors at $0-$7 read from that copy, verifies it through the
 *     shadow window, and jumps through the reset vector into EmuTOS.
 *     If \EMUTOS.IMG doesn't exist, the running TOS ROM is copied instead
 *     and the shadow is enabled in place: the contents are identical, so no
 *     reboot is needed. Alt-RAM is then registered as in mode 2. This needs
 *     a ROM at $E00000 (STE TOS 1.06+, 2.06); TOS 1.0x at $FC0000 is outside
 *     the shadow window and is left alone. An image named on the command
 *     line must exist; there is no fallback for it.
 *     Hold Shift while it starts to skip this and keep the real TOS.
 *
 *  2. Shadow on (running the shadowed OS, e.g. after a warm reset):
 *     Registers $01000000-$04F7FFFF (63.5MB) as Alt-RAM with Maddalt(),
 *     unless the OS already found Alt-RAM, and installs an _FRB cookie with
 *     a 64KB ST-RAM DMA bounce buffer if there isn't one.
 *
 * Putting TOSLOAD.PRG in \AUTO and an EmuTOS 256KB or 512KB image (e.g.
 * etos256uk.img, renamed) as \EMUTOS.IMG gives: power on -> real TOS ->
 * TOSLOAD loads EmuTOS and reboots into it -> EmuTOS runs TOSLOAD again
 * from \AUTO -> Alt-RAM registered. Software resets (Ctrl-Alt-Del) stay in
 * EmuTOS. The reset button or a power cycle returns to the real TOS.
 *
 * Only image files linked for $E00000 work (256KB or 512KB). The 192KB images
 * are linked for $FC0000 and are rejected.
 *
 * Build: run make. It uses m68k-atari-mint-gcc + MiNTLib if that is on
 * PATH, otherwise m68k-atari-elf-gcc + libtos from ~/toolchain/m68k-atari-elf
 * (override with TOOLCHAIN=mint|elf).
 */

#include <stdio.h>
#include <string.h>
#ifdef __M68K_ATARI_ELF__
#include <tos.h>
/* m68k-atari-elf: crti.o keeps the basepage in _BasePage, and Supexec()
 * callbacks return int (same width as long on m68k). */
#define _base _BasePage
typedef int sup_ret_t;
#else
#include <osbind.h>
#include <mint/basepage.h>
typedef long sup_ret_t;
#endif

/* ---- hardware ---------------------------------------------------------- */

#define SHADOW_REG      ((volatile unsigned short *)0x05000000UL)
#define SHADOW_KEY      0xE050U     /* upper 12 bits must read back as E05 */
#define SHADOW_KEY_MASK 0xFFF0U
#define SHADOW_EN       0x0001U
#define SHADOW_512K     0x0002U

#define SHADOW_ALIAS    0x04F80000UL /* SDRAM copy, bus errors when enabled */
#define SHADOW_MAX      0x00080000UL /* 512KB */
#define SHADOW_WINDOW   0x00E00000UL /* where the ST sees the ROM */

#define ALTRAM_BASE     0x01000000UL
#define ALTRAM_SIZE     (SHADOW_ALIAS - ALTRAM_BASE) /* 63.5MB */

/* ---- system variables (supervisor only) -------------------------------- */

#define MEMVALID   (*(volatile unsigned long *)0x420UL)
#define PHYSTOP    (*(volatile unsigned long *)0x42EUL)
#define MEMVAL2    (*(volatile unsigned long *)0x43AUL)
#define MEMVAL3    (*(volatile unsigned long *)0x51AUL)
#define P_COOKIES  (*(volatile unsigned long **)0x5A0UL)

#define COOKIE(a, b, c, d) \
    (((unsigned long)(a) << 24) | ((unsigned long)(b) << 16) | \
     ((unsigned long)(c) << 8) | (unsigned long)(d))

/* Set once we have registered Alt-RAM; the jar is rebuilt at every boot. */
#define COOKIE_ALTRAM   COOKIE('T', 'F', '5', '3')

#define OS_MAGIC_ETOS   COOKIE('E', 'T', 'O', 'S')
#define RAMVALID_MAGIC  0x1357BD13UL

#define CHUNK      32768L
#define FRB_SIZE   65536L
#define EINVFN     (-32L)
#define EFILNF     (-33L)
#define ROM_SIZE   0x40000L     /* TOS ROMs at $E00000 are 256KB */

extern BASEPAGE *_base;

/* Supexec() functions take no arguments, so parameters go through these. */
static volatile unsigned long g_addr;
static volatile unsigned long g_cookie_id;
static volatile unsigned long g_cookie_val;
static volatile unsigned short g_ctrl;
static volatile unsigned long g_size;
static volatile unsigned long g_zero; /* stays 0: reset vectors, see below */
static volatile unsigned long g_sum;
static volatile int g_use_vbr;
static volatile int g_in_place; /* shadow is a copy of the running ROM */

/* Order-sensitive checksum, so swapped or misaddressed blocks show up. */
static unsigned long checksum(const volatile unsigned long *p, unsigned long bytes)
{
    unsigned long sum = 0, i;

    for (i = 0; i < bytes / 4; i++)
        sum = ((sum << 1) | (sum >> 31)) + p[i];
    return sum;
}

/* 64KB _FRB buffer; kept resident with Ptermres() in Alt-RAM mode. */
static char frb_buffer[FRB_SIZE] __attribute__((aligned(16)));

/* ---- supervisor helpers ------------------------------------------------ */

/*
 * The program is compiled as plain 68000 code so it can start (and refuse
 * cleanly) on a stock ST. GNU as won't take 68010+ instructions in 68000
 * mode, so the few movec instructions are emitted as raw opcodes, all
 * through d0. The cacr ones and the vbr write only run once the TF536 has
 * been detected; the vbr read in the probe needs _CPU >= 10.
 */
#define MOVEC_VBR_D0   ".word 0x4e7a,0x0801"   /* movec vbr,d0  */
#define MOVEC_CACR_D0  ".word 0x4e7a,0x0002"   /* movec cacr,d0 */
#define MOVEC_D0_VBR   ".word 0x4e7b,0x0801"   /* movec d0,vbr  */
#define MOVEC_D0_CACR  ".word 0x4e7b,0x0002"   /* movec d0,cacr */

static sup_ret_t sup_peek_long(void)
{
    return (long)*(volatile unsigned long *)g_addr;
}

/*
 * Read a word with a temporary bus error handler. Returns the word, or -1
 * on a bus error. The vector table is read from VBR only when g_use_vbr is
 * set (the _CPU cookie says 68010+); otherwise it is taken to be at 0, as
 * on a 68000 and on any TOS 1.x, which never moves it. This keeps the probe
 * safe to run on a plain 68000 ST.
 */
static sup_ret_t sup_probe_word(void)
{
    unsigned long vbase = 0;
    long result;

    if (g_use_vbr)
        __asm__ volatile (MOVEC_VBR_D0 "\n\tmove.l %%d0,%0"
                          : "=g" (vbase) : : "d0");

    __asm__ volatile (
        "move.l  %2,%%a1\n\t"
        "move.l  8(%%a1),%%d1\n\t"      /* save the bus error vector */
        "lea     1f(%%pc),%%a0\n\t"
        "move.l  %%a0,8(%%a1)\n\t"
        "move.l  %%sp,%%a2\n\t"
        "move.l  %1,%%a0\n\t"
        "moveq   #0,%0\n\t"
        "move.w  (%%a0),%0\n\t"
        "nop\n\t"                        /* let the access complete */
        "bra.s   2f\n"
        "1:\n\t"
        "move.l  %%a2,%%sp\n\t"          /* drop the exception frame */
        "moveq   #-1,%0\n"
        "2:\n\t"
        "move.l  %%d1,8(%%a1)\n\t"       /* restore the bus error vector */
        : "=&d" (result)
        : "r" (g_addr), "r" (vbase)
        : "d1", "a0", "a1", "a2", "cc", "memory");

    return result;
}

static sup_ret_t sup_get_cookie(void)
{
    volatile unsigned long *jar = P_COOKIES;

    if (jar == NULL)
        return 0;

    for (; jar[0] != 0; jar += 2) {
        if (jar[0] == g_cookie_id) {
            g_cookie_val = jar[1];
            return 1;
        }
    }
    return 0;
}

static sup_ret_t sup_add_cookie(void)
{
    volatile unsigned long *jar = P_COOKIES;
    long n = 0;

    if (jar == NULL)
        return 0;

    while (jar[n * 2] != 0)
        n++;

    /* the terminator's value is the number of slots, itself included */
    if (n + 2 > (long)jar[n * 2 + 1])
        return 0;

    jar[n * 2 + 2] = 0;
    jar[n * 2 + 3] = jar[n * 2 + 1];
    jar[n * 2 + 1] = g_cookie_val;
    jar[n * 2] = g_cookie_id;
    return 1;
}

static unsigned long read_cacr(void)
{
    unsigned long cacr;

    __asm__ volatile (MOVEC_CACR_D0 "\n\tmove.l %%d0,%0"
                      : "=g" (cacr) : : "d0");
    return cacr;
}

static void write_cacr(unsigned long cacr)
{
    __asm__ volatile ("move.l %0,%%d0\n\t" MOVEC_D0_CACR
                      : : "g" (cacr) : "d0", "memory");
}

/* Clear both 030 caches and leave them off. */
static void caches_clear_off(void)
{
    write_cacr(0x0808UL);   /* CD | CI: clear data and instruction caches */
    write_cacr(0);
}

/*
 * Enable the shadow and verify it. Then, with g_in_place, return 0 to the
 * (now shadowed) running TOS; otherwise jump into the loaded OS. On failure
 * returns -1 with the shadow disabled and the previous state restored.
 *
 * Until the window is verified the real TOS ROM must be considered gone (its
 * interrupt and trap handlers included), so interrupts stay masked and no
 * OS calls are made.
 */
static sup_ret_t sup_boot(void)
{
    const volatile unsigned long *win = (const volatile unsigned long *)SHADOW_WINDOW;
    const volatile unsigned long *vec = (const volatile unsigned long *)g_zero;
    unsigned long cacr;
    unsigned short sr;

    __asm__ volatile ("move.w %%sr,%0\n\tor.w #0x0700,%%sr"
                      : "=d" (sr) : : "cc", "memory");

    cacr = read_cacr();
    caches_clear_off();

    *SHADOW_REG = g_ctrl;

    if (*SHADOW_REG != g_ctrl)
        goto fail;

    /* the SDRAM copy now bus errors, so compare the window against the
     * checksum taken from the copy before enabling */
    if (checksum(win, g_size) != g_sum)
        goto fail;

    /* the reset vectors must come from the copy too */
    if (vec[0] != win[0] || vec[1] != win[1])
        goto fail;

    if (g_in_place) {
        write_cacr(0x0808UL);
        write_cacr(cacr);
        __asm__ volatile ("move.w %0,%%sr" : : "d" (sr) : "cc", "memory");
        return 0;
    }

    /* make the loaded OS do a full cold start */
    MEMVALID = 0;
    MEMVAL2 = 0;
    MEMVAL3 = 0;

    /* Same entry as a hardware reset: SSP and PC from $0 and $4, which now
     * come from the shadow copy. VBR back to 0, caches already off. */
    __asm__ volatile (
        "moveq   #0,%%d0\n\t"
        MOVEC_D0_VBR "\n\t"
        "suba.l  %%a1,%%a1\n\t"
        "move.l  (%%a1),%%sp\n\t"
        "move.l  4(%%a1),%%a0\n\t"
        "jmp     (%%a0)\n\t"
        : : : "d0", "a0", "a1", "memory");
    __builtin_unreachable();

fail:
    *SHADOW_REG = SHADOW_KEY;   /* shadow off: the real ROM is back */
    write_cacr(0x0808UL);
    write_cacr(cacr);
    __asm__ volatile ("move.w %0,%%sr" : : "d" (sr) : "cc", "memory");
    return -1;
}

/* ---- user mode helpers ------------------------------------------------- */

static unsigned long peek_long(unsigned long addr)
{
    g_addr = addr;
    return (unsigned long)Supexec(sup_peek_long);
}

static int get_cookie(unsigned long id, unsigned long *value)
{
    g_cookie_id = id;
    if (!Supexec(sup_get_cookie))
        return 0;
    if (value)
        *value = g_cookie_val;
    return 1;
}

static int add_cookie(unsigned long id, unsigned long value)
{
    g_cookie_id = id;
    g_cookie_val = value;
    return (int)Supexec(sup_add_cookie);
}

/*
 * Does the OS already own Alt-RAM? Mxalloc() only reports free memory, so it
 * can't tell "none" from "all of it in use"; our own cookie and ramtop cover
 * that. ramtop is only trusted on an OS that maintains it (TOS 3+, EmuTOS):
 * TOS 1.x/2.x may leave a stale value from an earlier EmuTOS session.
 * Alt-RAM added by another program and then used up is still not detected.
 */
static int altram_registered(void)
{
    unsigned long os;

    if ((long)Mxalloc(-1L, 1) > 0 || get_cookie(COOKIE_ALTRAM, NULL))
        return 1;

    os = peek_long(peek_long(0x4F2UL) + 8);     /* os_beg: the ROM header */
    if ((peek_long(os) & 0xFFFFUL) < 0x0300UL &&
        peek_long(os + 0x2C) != OS_MAGIC_ETOS)
        return 0;

    return peek_long(0x5A8UL) == RAMVALID_MAGIC &&
           peek_long(0x5A4UL) > ALTRAM_BASE;
}

static int overlaps_shadow(unsigned long start, unsigned long len)
{
    return start < SHADOW_ALIAS + SHADOW_MAX && start + len > SHADOW_ALIAS;
}

static unsigned long be32(const unsigned char *p)
{
    return ((unsigned long)p[0] << 24) | ((unsigned long)p[1] << 16) |
           ((unsigned long)p[2] << 8) | (unsigned long)p[3];
}

/* The program must not live in the area the image is copied to. */
static int in_shadow_area(void)
{
    int stack_marker;

    if (!overlaps_shadow((unsigned long)_base->p_lowtpa,
                         (unsigned long)_base->p_hitpa -
                             (unsigned long)_base->p_lowtpa) &&
        !overlaps_shadow((unsigned long)&stack_marker, sizeof(stack_marker)))
        return 0;

    printf("TOSLOAD: running from $%08lX-$%08lX; must not be loaded\r\n"
           "         in Alt-RAM (clear its TT-RAM load flag)\r\n",
           SHADOW_ALIAS, SHADOW_ALIAS + SHADOW_MAX - 1);
    return 1;
}

/* Enable the shadow over the finished copy. Returns only if in place, or
 * (nonzero) on failure. */
static int enable_shadow(long size, int in_place)
{
    g_size = (unsigned long)size;
    g_sum = checksum((const volatile unsigned long *)SHADOW_ALIAS, g_size);
    g_ctrl = SHADOW_KEY | SHADOW_EN | (size == 0x80000L ? SHADOW_512K : 0);
    g_zero = 0;
    g_in_place = in_place;

    if (Supexec(sup_boot) < 0) {
        printf("TOSLOAD: shadow window verify failed, shadow disabled\r\n");
        return 1;
    }
    return 0;
}

/* ---- mode 2: Alt-RAM under the shadowed OS ------------------------------ */

static int register_altram(void)
{
    long avail, r;
    unsigned long frb, keep;

    avail = (long)Mxalloc(-1L, 1);
    if (avail == EINVFN) {
        printf("TOSLOAD: this OS has no Mxalloc/Maddalt\r\n");
        return 1;
    }
    if (altram_registered()) {
        printf("TOSLOAD: Alt-RAM already present (%ld KB free)\r\n",
               avail > 0 ? avail / 1024 : 0L);
        return 0;
    }

    r = Maddalt((void *)ALTRAM_BASE, (long)ALTRAM_SIZE);
    if (r < 0) {
        printf("TOSLOAD: Maddalt failed (%ld)\r\n", r);
        return 1;
    }
    if (!add_cookie(COOKIE_ALTRAM, ALTRAM_BASE))
        printf("TOSLOAD: cookie jar full, registration not recorded\r\n");
    printf("TOSLOAD: added %lu KB Alt-RAM at $%08lX\r\n",
           (unsigned long)ALTRAM_SIZE / 1024, (unsigned long)ALTRAM_BASE);

    /* DMA (floppy/ACSI) can't reach Alt-RAM; drivers bounce through _FRB */
    if (get_cookie(COOKIE('_', 'F', 'R', 'B'), &frb)) {
        return 0;
    }

    if ((unsigned long)frb_buffer + FRB_SIZE > peek_long(0x42EUL)) {
        printf("TOSLOAD: not in ST-RAM, no _FRB installed\r\n");
        return 0;
    }

    if (!add_cookie(COOKIE('_', 'F', 'R', 'B'), (unsigned long)frb_buffer)) {
        printf("TOSLOAD: cookie jar full, no _FRB installed\r\n");
        return 0;
    }

    /* keep the program (and the buffer in its BSS) resident */
    keep = sizeof(BASEPAGE) + _base->p_tlen + _base->p_dlen + _base->p_blen;
    printf("TOSLOAD: _FRB buffer at $%08lX\r\n", (unsigned long)frb_buffer);
    Ptermres(keep, 0);
    return 0; /* not reached */
}

/* ---- mode 1: load the image and boot it --------------------------------- */

static int shadow_rom(void);

static int load_and_boot(const char *path, int fallback)
{
    unsigned char *buf;
    unsigned long phystop, off;
    long fh, size, n;

    fh = Fopen(path, 0);
    if (fh == EFILNF && fallback) {
        printf("TOSLOAD: no %s, shadowing the TOS ROM\r\n", path);
        return shadow_rom();
    }
    if (fh < 0) {
        printf("TOSLOAD: can't open %s (%ld)\r\n", path, fh);
        return 1;
    }

    /* The copy would overwrite memory the OS has handed out, and we return
     * to this OS if loading fails. */
    if (altram_registered()) {
        printf("TOSLOAD: Alt-RAM already registered; run TOSLOAD first\r\n");
        Fclose((short)fh);
        return 1;
    }

    size = Fseek(0L, (short)fh, 2);
    Fseek(0L, (short)fh, 0);
    if (size != 0x40000L && size != 0x80000L) {
        printf("TOSLOAD: %s is %ld bytes; need a 256KB or 512KB image\r\n",
               path, size);
        Fclose((short)fh);
        return 1;
    }

    /* the floppy/ACSI DMA can only reach ST-RAM, so read through a buffer
     * there and copy to the SDRAM ourselves */
    buf = (unsigned char *)Mxalloc(CHUNK, 0);
    if ((long)buf == EINVFN)
        buf = (unsigned char *)Malloc(CHUNK);
    phystop = peek_long(0x42EUL);
    if ((long)buf <= 0 || (unsigned long)buf + CHUNK > phystop) {
        printf("TOSLOAD: can't get an ST-RAM buffer\r\n");
        Fclose((short)fh);
        return 1;
    }

    if (in_shadow_area()) {
        Mfree(buf);
        Fclose((short)fh);
        return 1;
    }

    for (off = 0; off < (unsigned long)size; off += CHUNK) {
        n = Fread((short)fh, CHUNK, buf);
        if (n != CHUNK) {
            printf("TOSLOAD: read error at %lu (%ld)\r\n", off, n);
            Mfree(buf);
            Fclose((short)fh);
            return 1;
        }

        if (off == 0) {
            /* TOS ROM header: bra.s, version, reset PC, os_beg */
            unsigned long reseth = be32(buf + 4);
            unsigned long os_beg = be32(buf + 8);

            if (buf[0] != 0x60 || os_beg != SHADOW_WINDOW ||
                reseth < SHADOW_WINDOW ||
                reseth >= SHADOW_WINDOW + (unsigned long)size) {
                printf("TOSLOAD: %s is not a TOS image for $E00000\r\n"
                       "          (os_beg $%08lX, reset $%08lX)\r\n",
                       path, os_beg, reseth);
                Mfree(buf);
                Fclose((short)fh);
                return 1;
            }
        }

        memcpy((void *)(SHADOW_ALIAS + off), buf, CHUNK);
        if (memcmp((const void *)(SHADOW_ALIAS + off), buf, CHUNK) != 0) {
            printf("TOSLOAD: SDRAM verify failed at $%08lX\r\n",
                   SHADOW_ALIAS + off);
            Mfree(buf);
            Fclose((short)fh);
            return 1;
        }
    }

    Fclose((short)fh);
    Mfree(buf);

    printf("TOSLOAD: booting %s (%ld KB)...\r\n", path, size / 1024);

    return enable_shadow(size, 0);
}

/* ---- mode 1 fallback: shadow the running ROM ---------------------------- */

static int shadow_rom(void)
{
    const void *rom = (const void *)SHADOW_WINDOW;
    unsigned long sysbase = peek_long(0x4F2UL);
    unsigned long os_beg = peek_long(sysbase + 8);

    /* also keeps us from touching $E00000 on an ST, where it bus errors */
    if (os_beg != SHADOW_WINDOW) {
        printf("TOSLOAD: TOS is at $%08lX, only a ROM at $%08lX can be\r\n"
               "         shadowed\r\n", os_beg, SHADOW_WINDOW);
        return 1;
    }

    /* We keep running this TOS, and $04F80000 up is about to bus error, so
     * it must not already be in the OS's memory pool. */
    if (altram_registered()) {
        printf("TOSLOAD: Alt-RAM already registered; run TOSLOAD first\r\n");
        return 1;
    }

    if (in_shadow_area())
        return 1;

    memcpy((void *)SHADOW_ALIAS, rom, ROM_SIZE);
    if (memcmp((const void *)SHADOW_ALIAS, rom, ROM_SIZE) != 0) {
        printf("TOSLOAD: SDRAM verify failed\r\n");
        return 1;
    }

    if (enable_shadow(ROM_SIZE, 1))
        return 1;

    printf("TOSLOAD: TOS ROM shadowed (%ld KB)\r\n", ROM_SIZE / 1024);

    /* same as a later run with the shadow on; no Maddalt is not an error */
    (void)register_altram();
    return 0;
}

/* ---- main --------------------------------------------------------------- */

int main(int argc, char **argv)
{
    const char *path = (argc > 1) ? argv[1] : "\\EMUTOS.IMG";
    unsigned long cpu = 0;
    long status;

    /* TOS 1.00-1.04 has no cookie jar, and older TOS may not know a 68030,
     * so the CPU type can't be relied on. The probe decides instead: only
     * the TF536 ST firmware answers $E05x at $05000000, which also
     * proves a 68030 is present. Without the card, the read lands on the
     * ROM mirror at $000000 (a 24-bit alias) and returns the ROM header. */
    g_use_vbr = get_cookie(COOKIE('_', 'C', 'P', 'U'), &cpu) && cpu >= 10;

    g_addr = (unsigned long)SHADOW_REG;
    status = Supexec(sup_probe_word);
    if (status < 0 || ((unsigned long)status & SHADOW_KEY_MASK) != SHADOW_KEY) {
        printf("TOSLOAD: no TF536 ROM shadow (read $%04lX)\r\n",
               (unsigned long)status & 0xFFFFUL);
        return 1;
    }

    if (status & SHADOW_EN)
        return register_altram();

    if (Kbshift(-1) & 0x03) {
        printf("TOSLOAD: Shift held, staying in this TOS\r\n");
        return 0;
    }

    return load_and_boot(path, argc <= 1);
}
