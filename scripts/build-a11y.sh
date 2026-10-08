#!/usr/bin/env bash
# build-a11y.sh — build the accessibility stack against the GTK2 prefix.
#
# GTK2's ATK implementation is the GAIL module; publishing that tree over
# AT-SPI needs at-spi2-atk's bridge (libatk-bridge-2.0 and the gtk-2.0 module)
# and at-spi2-core's libatspi plus the a11y bus launcher/registry.  The host's
# copies are built against glib >= 2.78, while the GTK2 stack here is glib 2.56,
# so era-matched releases are built into $A11Y_PREFIX and the GTK2 module is
# installed where GTK2 looks for modules.
#
# Input synthesis (a screen reader driving the app) is deliberately not part of
# this: under Wayland that is the compositor's job.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

A11Y_PREFIX="${A11Y_PREFIX:-$GTK2_PREFIX/a11y}"
export A11Y_PREFIX
export PATH="$GTK2_PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:$GTK2_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"

have gcc || die "no C compiler"
have curl || have wget || die "no downloader (curl/wget)"
[ -e "$GTK2_PREFIX/lib/libglib-2.0.so.0" ] || die "dependency stack not built (run scripts/build-deps.sh)"

# --- at-spi2-core: libatspi + at-spi-bus-launcher + at-spi2-registryd ---------
core="$(fetch_tar "at-spi2-core-$AT_SPI2_CORE_VERSION" \
    "https://download.gnome.org/sources/at-spi2-core/${AT_SPI2_CORE_VERSION%.*}/at-spi2-core-$AT_SPI2_CORE_VERSION.tar.xz")"
step "building at-spi2-core $AT_SPI2_CORE_VERSION"
( cd "$core" \
  && [ -f config.status ] || ./configure --prefix="$A11Y_PREFIX" --disable-x11 >/dev/null \
  && make -j"$(nproc)" >/dev/null \
  && make install >/dev/null ) || die "at-spi2-core build failed"

# --- at-spi2-atk: libatk-bridge-2.0 + the GTK2 module -------------------------
atk="$(fetch_tar "at-spi2-atk-$AT_SPI2_ATK_VERSION" \
    "https://download.gnome.org/sources/at-spi2-atk/${AT_SPI2_ATK_VERSION%.*}/at-spi2-atk-$AT_SPI2_ATK_VERSION.tar.xz")"
step "building at-spi2-atk $AT_SPI2_ATK_VERSION"
( cd "$atk" \
  && [ -f config.status ] || PKG_CONFIG_PATH="$A11Y_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH" \
        ./configure --prefix="$A11Y_PREFIX" >/dev/null \
  && make -j"$(nproc)" >/dev/null \
  && make install >/dev/null ) || die "at-spi2-atk build failed"

# GTK2 loads GTK_MODULES entries from <libdir>/gtk-2.0/modules.
mkdir -p "$GTK2_PREFIX/lib/gtk-2.0/modules"
cp "$A11Y_PREFIX/lib/gtk-2.0/modules/libatk-bridge.so" \
   "$GTK2_PREFIX/lib/gtk-2.0/modules/libatk-bridge.so"

log "a11y stack in $A11Y_PREFIX; GTK2 bridge module installed"
