#!/usr/bin/env bash
# build-gimp.sh — build GIMP 2.10 against the GTK2 prefix and the shim.
#
# GIMP 2.10 is the last GTK2 GIMP and the final target of this tree.  Its
# source stays pristine: the tarball is configured out-of-tree under
# $GTK2_PREFIX/build/gimp-<version> and installed into $GTK2_PREFIX.  Every
# change needed to make GIMP run under Wayland belongs in xlib-wayland.
#
# GIMP is a GEGL application: babl/GEGL (its engine), libmypaint (the MyPaint
# brush tool), mypaint-brushes (brush data), json-glib and gexiv2 are all
# supplied by scripts/build-deps.sh.
#
# Usage: scripts/build-gimp.sh [--configure] [--jobs N]
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

CONFIGURE_ONLY=0
for a in "$@"; do
    case "$a" in
        --configure) CONFIGURE_ONLY=1;;
        --jobs) shift; JOBS="$1";;
        *) die "unknown argument: $a";;
    esac
done

GIMP_SRC="$GTK2_CACHE/src/gimp-$GIMP_VERSION"
GIMP_BUILD="$GTK2_PREFIX/build/gimp-$GIMP_VERSION"

[ -e "$GTK2_PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"
[ -x "$GTK2_PREFIX/bin/gegl" ] || die "GEGL not built (run scripts/build-deps.sh)"

use_prefix
export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:$GTK2_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPPFLAGS="-I$GTK2_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$GTK2_PREFIX/lib -Wl,-rpath,$GTK2_PREFIX/lib ${LDFLAGS:-}"

# Host-compiler accommodation, as for GTK2 and MATE.
: "${GIMP_CFLAGS:=-O2 -g -fcommon -D_GNU_SOURCE -include stdlib.h -include string.h -include stdint.h \
    -Wno-error=incompatible-pointer-types \
    -Wno-error=implicit-function-declaration \
    -Wno-error=implicit-int \
    -Wno-error=int-conversion \
    -Wno-error=return-mismatch \
    -Wno-error=declaration-missing-parameter-type \
    -Wno-error=deprecated-declarations}"
# GCC 16 defaults to C23, where `bool` is a keyword; GIMP 2.10 (2018) still
# uses `bool` as an identifier, so pin the C dialect.  Keep it out of CXXFLAGS
# (the `-std=gnu++14` there must win).
export CFLAGS="-std=gnu11 ${GIMP_CFLAGS} ${CFLAGS:-}"
export CXXFLAGS="-std=gnu++14 -fpermissive ${GIMP_CFLAGS} ${CXXFLAGS:-}"

if [ ! -d "$GIMP_SRC" ]; then
    GIMP_SRC="$(fetch_tar "gimp-$GIMP_VERSION" \
        "https://download.gimp.org/gimp/v${GIMP_VERSION%.*}/gimp-$GIMP_VERSION.tar.bz2")"
fi

: "${GIMP_CONFIGURE_OPTS:=
  --prefix=$GTK2_PREFIX
  --disable-gtk-doc
  --disable-dependency-tracking
  --disable-python
  --disable-vector-icons
  --disable-check-update
  --without-gs
  --without-webkit
  --without-alsa
  --without-gudev
  --without-libheif
  --without-libmng
  --without-openexr
  --without-jpeg2000
  --without-xmc
  --without-libxpm
  --without-libbacktrace
  --without-libunwind
  --without-xvfb-run
  --without-appdata-test
}"

step "Configuring GIMP $GIMP_VERSION against the shim"
rm -rf "$GIMP_BUILD"
mkdir -p "$GIMP_BUILD"
cd "$GIMP_BUILD"

# shellcheck disable=SC2086
"$GIMP_SRC/configure" $GIMP_CONFIGURE_OPTS >configure.log 2>&1 \
    || { tail -40 configure.log; die "gimp: configure failed"; }
log "configure OK"

if [ "$CONFIGURE_ONLY" = 1 ]; then
    log "stopping after configure (--configure)"
    exit 0
fi

step "Building GIMP ($JOBS jobs)"
make -j"$JOBS" >build.log 2>&1 \
    || { grep -nE 'error:|undefined reference|Error [0-9]' build.log | head -30; \
         tail -15 build.log; die "gimp: build failed"; }

step "Installing GIMP into $GTK2_PREFIX"
make install \
    UPDATE_MIME_DATABASE=true \
    UPDATE_DESKTOP_DATABASE=true \
    GTK_UPDATE_ICON_CACHE="$GTK2_PREFIX/bin/gtk-update-icon-cache" \
    GLIB_COMPILE_SCHEMAS="$GTK2_PREFIX/bin/glib-compile-schemas" \
    GIMP_UPDATE_ICON_CACHE="$GTK2_PREFIX/bin/gtk-update-icon-cache" \
    >install.log 2>&1 || { tail -25 install.log; die "gimp: install failed"; }

log "GIMP $GIMP_VERSION installed"
