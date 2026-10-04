#!/usr/bin/env bash
# setup-labwc.sh — stage a nested-compositor test environment, no root.
#
# We build labwc from source with `-Dxwayland=disabled`: the whole point of
# this project is to run GTK2 natively on Wayland, so the test compositor must
# never start XWayland nor touch the host X server.  labwc's only non-obvious
# build dependency that is not usually installed is libsfdo, which we stage
# from a distro package into a local prefix.
#
# Usage: scripts/setup-labwc.sh [--force]
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

FORCE=0
for a in "$@"; do case "$a" in --force) FORCE=1;; *) die "unknown argument: $a";; esac; done

step "Staging nested labwc into $LABWC_PREFIX/usr"

mkdir -p "$LABWC_PREFIX/usr" "$LABWC_PREFIX/dl" "$LABWC_PREFIX/src"

# ---------------------------------------------------------------- libsfdo ---
if ! PKG_CONFIG_PATH="$LABWC_PREFIX/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
       pkg-config --exists libsfdo-desktop 2>/dev/null; then
    log "libsfdo not found; staging it from a distro package"
    if have pacman; then
        url="$(pacman -Sp --print-format '%l' libsfdo 2>/dev/null | head -1 || true)"
        if [ -n "$url" ]; then
            pkg="$LABWC_PREFIX/dl/$(basename "$url")"
            [ -f "$pkg" ] || curl -fsSL -o "$pkg" "$url" || die "could not download libsfdo"
            tar --zstd -xf "$pkg" -C "$LABWC_PREFIX/usr" 2>/dev/null \
                || tar -xf "$pkg" -C "$LABWC_PREFIX/usr"
            # The packaged .pc files hardcode prefix=/usr; repoint them here.
            for pc in "$LABWC_PREFIX"/usr/lib/pkgconfig/libsfdo-*.pc; do
                [ -f "$pc" ] || continue
                sed -i "s#^prefix=/usr\$#prefix=$LABWC_PREFIX/usr#" "$pc"
            done
            log "libsfdo staged"
        else
            warn "pacman could not resolve libsfdo; install libsfdo-dev another way"
        fi
    else
        warn "no pacman; cannot stage libsfdo automatically (install libsfdo-dev)"
    fi
else
    dim "libsfdo already staged"
fi

export PKG_CONFIG_PATH="$LABWC_PREFIX/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# ------------------------------------------------------------------ labwc ---
if [ "$FORCE" = 0 ] && [ -x "$LABWC_PREFIX/usr/bin/labwc" ]; then
    # Probe with the prefix's libs: a bare --version fails to load libsfdo and
    # would otherwise look like "not built", forcing a rebuild every run.
    if LD_LIBRARY_PATH="$LABWC_PREFIX/usr/lib:${LD_LIBRARY_PATH:-}" \
           "$LABWC_PREFIX/usr/bin/labwc" --version 2>/dev/null | grep -q -- '-xwayland'; then
        log "labwc already built with XWayland disabled"
        exit 0
    fi
fi

log "fetching labwc $LABWC_VERSION"
mkdir -p "$LABWC_PREFIX/dl" "$LABWC_PREFIX/src"
tarball="$LABWC_PREFIX/dl/labwc-$LABWC_VERSION.tar.gz"
[ -f "$tarball" ] || curl -fsSL -o "$tarball" \
    "https://github.com/labwc/labwc/archive/refs/tags/$LABWC_VERSION.tar.gz" \
    || die "could not download labwc $LABWC_VERSION"

rm -rf "$LABWC_SRC"
tar xf "$tarball" -C "$LABWC_PREFIX/src"
[ -d "$LABWC_SRC" ] || die "labwc source did not unpack to $LABWC_SRC"

log "building labwc (xwayland disabled, man-pages/labnag/nls off)"
rm -rf "$LABWC_BUILD"
meson setup "$LABWC_BUILD" "$LABWC_SRC" --prefix="$LABWC_PREFIX/usr" \
    -Dxwayland=disabled -Dman-pages=disabled -Dlabnag=disabled -Dnls=disabled \
    -Dsystemd-session=disabled -Dsvg=enabled -Dicon=enabled \
    >"$LABWC_PREFIX/setup.log" 2>&1 || { tail -25 "$LABWC_PREFIX/setup.log"; die "labwc configure failed"; }
ninja -C "$LABWC_BUILD" >"$LABWC_PREFIX/build.log" 2>&1 \
    || { tail -25 "$LABWC_PREFIX/build.log"; die "labwc build failed"; }
ninja -C "$LABWC_BUILD" install >"$LABWC_PREFIX/install.log" 2>&1 \
    || { tail -25 "$LABWC_PREFIX/install.log"; die "labwc install failed"; }

# --------------------------------------------------------------- verify ----
ver="$(LD_LIBRARY_PATH="$LABWC_PREFIX/usr/lib" "$LABWC_PREFIX/usr/bin/labwc" --version 2>&1 || true)"
log "labwc: $ver"
case "$ver" in
    *-xwayland*) ;;
    *) die "labwc was not built with XWayland disabled (got: $ver)";;
esac

# Install the harness configuration.
mkdir -p "$LABWC_PREFIX/config"
cp "$GTK2_ROOT"/config/labwc/*.xml "$LABWC_PREFIX/config/"
log "nested labwc ready ($LABWC_PREFIX/usr/bin/labwc)"
