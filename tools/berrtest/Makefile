# BERRTEST.PRG
#
# Builds with whichever Atari cross toolchain is available:
#   mint - m68k-atari-mint-gcc + MiNTLib, found on PATH (preferred)
#   elf  - m68k-atari-elf-gcc + newlib/libtos, in $(ELF_DIR)/bin or on PATH
#
# Override the choice with: make TOOLCHAIN=elf   (or TOOLCHAIN=mint)
# and the ELF location with: make ELF_DIR=/path/to/m68k-atari-elf

ELF_DIR ?= $(HOME)/toolchain/m68k-atari-elf

MINT_CC := $(shell command -v m68k-atari-mint-gcc 2>/dev/null)
ELF_CC  := $(firstword $(wildcard $(ELF_DIR)/bin/m68k-atari-elf-gcc) \
                       $(shell command -v m68k-atari-elf-gcc 2>/dev/null))

# clean needs no toolchain
ifneq ($(MAKECMDGOALS),clean)

ifndef TOOLCHAIN
  ifneq ($(MINT_CC),)
    TOOLCHAIN := mint
  else ifneq ($(ELF_CC),)
    TOOLCHAIN := elf
  else
    $(error No Atari toolchain found: install m68k-atari-mint-gcc on PATH, \
            or m68k-atari-elf in $(ELF_DIR))
  endif
endif

CFLAGS = -m68000 -O2 -Wall -fomit-frame-pointer -fno-delete-null-pointer-checks

ifeq ($(TOOLCHAIN),mint)
  ifeq ($(MINT_CC),)
    $(error TOOLCHAIN=mint but m68k-atari-mint-gcc is not on PATH)
  endif
  CC := $(MINT_CC)
else ifeq ($(TOOLCHAIN),elf)
  ifeq ($(ELF_CC),)
    $(error TOOLCHAIN=elf but m68k-atari-elf-gcc is not in $(ELF_DIR)/bin or on PATH)
  endif
  CC      := $(ELF_CC)
  ELF_PRG := $(dir $(ELF_CC))m68k-atari-elf-prg
  # GCC 12+ warns about fixed low addresses (system variables) otherwise
  CFLAGS  += --param=min-pagesize=0
else
  $(error Unknown TOOLCHAIN '$(TOOLCHAIN)': use mint or elf)
endif

$(info Using $(TOOLCHAIN) toolchain: $(CC))

endif

all: berrtest.prg

ifeq ($(TOOLCHAIN),mint)
berrtest.prg: berrtest.c
	$(CC) $(CFLAGS) -s -o $@ $<
else
berrtest.prg: berrtest.elf
	$(ELF_PRG) $< $@

berrtest.elf: berrtest.c
	$(CC) $(CFLAGS) -o $@ $< -ltos
endif

clean:
	rm -f berrtest.prg berrtest.elf

.PHONY: all clean
