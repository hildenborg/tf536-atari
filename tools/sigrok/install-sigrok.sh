#!/bin/bash
# Install sigrok-cli with the Kingst LA2016 driver (kingst-la2016) on Ubuntu.
#
#   tools/sigrok/install-sigrok.sh [KingstVIS_linux.tar.gz | KingstVIS-binary]
#
# Ubuntu's own sigrok packages (libsigrok 0.5.2, 2019) are older than the LA2016
# driver, so this builds libsigrok, libsigrokdecode and sigrok-cli from the
# sigrok git repositories and installs them in /usr/local.
#
# The LA2016 also needs firmware that only Kingst's own KingstVIS software
# contains. Download the Linux version of KingstVIS from Kingst and give its
# .tar.gz (or the unpacked KingstVIS program) as the argument; the firmware is
# extracted with sigrok's tool and installed in /usr/local/share/sigrok-firmware.
# Without the argument everything else is installed, and the script can be run
# again later with it.
#
# Sources go to $SIGROK_SRC (default ~/src/sigrok). Uses sudo for apt, make
# install, the firmware and the udev rules.
set -euo pipefail

SRC=${SIGROK_SRC:-$HOME/src/sigrok}
PREFIX=/usr/local
FWDIR=$PREFIX/share/sigrok-firmware
KVIS=${1:-}

say() { printf '\n== %s\n' "$*"; }
die() { echo "install-sigrok.sh: $*" >&2; exit 1; }

command -v apt-get > /dev/null || die "this script is for Ubuntu/Debian (apt)"
[ -z "$KVIS" ] || [ -f "$KVIS" ] || die "no such file: $KVIS"
[ "$(id -u)" != 0 ] || die "run it as your own user; it uses sudo where needed"

say "Build dependencies (apt)"
sudo apt-get update
sudo apt-get install -y git build-essential autoconf autoconf-archive automake \
    libtool pkg-config libglib2.0-dev libzip-dev libusb-1.0-0-dev python3-dev

# fetch NAME: clone, or update an earlier clone
fetch() {
    if [ -d "$SRC/$1/.git" ]; then
        git -C "$SRC/$1" pull --ff-only
    else
        git clone "https://github.com/sigrokproject/$1" "$SRC/$1"
    fi
    echo "$1 at $(git -C "$SRC/$1" log -1 --format='%h %cd' --date=short)"
}

# build NAME CONFIGURE-OPTIONS...
build() {
    local n=$1; shift
    say "Building $n"
    cd "$SRC/$n"
    ./autogen.sh
    ./configure --prefix="$PREFIX" "$@"
    make -j"$(nproc)"
    sudo make install
    sudo ldconfig
}

mkdir -p "$SRC"
say "Sources in $SRC"
for r in libsigrok libsigrokdecode sigrok-cli sigrok-util; do fetch "$r"; done

build libsigrok --disable-cxx --disable-python --disable-ruby --disable-java
grep -q '^#define HAVE_HW_KINGST_LA2016 1' "$SRC/libsigrok/config.h" ||
    die "libsigrok was built without the kingst-la2016 driver; see $SRC/libsigrok/config.log"
build libsigrokdecode
build sigrok-cli

say "udev rules (access to the analyzer without root)"
sudo install -m 644 "$SRC/libsigrok/contrib/60-libsigrok.rules" \
    "$SRC/libsigrok/contrib/61-libsigrok-uaccess.rules" /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger

if [ -n "$KVIS" ]; then
    say "LA2016 firmware from $KVIS"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    case $KVIS in
    *.tar.gz|*.tgz) tar -xzf "$KVIS" -C "$tmp" ;;
    *) cp "$KVIS" "$tmp/" ;;
    esac
    bin=$(find "$tmp" -type f -name KingstVIS | head -1)
    [ -n "$bin" ] || die "no KingstVIS program in $KVIS"
    (cd "$tmp" && python3 -I "$SRC/sigrok-util/firmware/kingst-la/sigrok-fwextract-kingst-la2016" "$bin")
    ls "$tmp"/kingst-la-*.fw > /dev/null 2>&1 || die "no firmware extracted from $bin"
    sudo install -d "$FWDIR"
    sudo install -m 644 "$tmp"/kingst-*.fw "$tmp"/kingst-*.bitstream "$FWDIR/"
    ls -l "$FWDIR"/kingst-*
fi

say "Check"
hash -r
sigrok-cli --version | head -3
sigrok-cli -L | grep -q kingst-la2016 || die "sigrok-cli does not list kingst-la2016"
echo "kingst-la2016 driver: present"
if ls "$FWDIR"/kingst-la-*.fw > /dev/null 2>&1; then
    echo "Firmware: present. With the LA2016 plugged in, this should find it:"
    echo "  sigrok-cli -d kingst-la2016 --scan"
else
    echo "Firmware: missing. Run this script again with the KingstVIS .tar.gz."
fi
echo "If the analyzer was plugged in already, unplug it and plug it in again."
