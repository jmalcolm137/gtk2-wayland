#!/usr/bin/env bash
# build-deps.sh — build the GTK2-era supporting stack into $GTK2_PREFIX.
#
# GTK+ 2.24.33 is from December 2020.  Built against a much newer GLib it
# misbehaves in ways that are not the shim's fault: GtkListStore's stale-iter
# check dereferences freed memory (a segfault in GLib's GSequence), and
# gdk-pixbuf property defaults have moved.  This script builds the stack GTK2
# was designed for — GLib, ATK, Pango, gdk-pixbuf — into $GTK2_PREFIX, so that
# the only non-period-correct component in the process is our libX11 shim.
#
# cairo/fontconfig/FreeType/HarfBuzz/fribidi are taken from the host; they are
# ABI-stable across the window and do not carry GLib.
#
# Usage: scripts/build-deps.sh [glib] [atk] [pango] [gdk-pixbuf]
#   With no arguments, builds all four in order.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

# ---------------------------------------------------------------- host tools -
if HOSTTOOLS="$(stage_glib_tools)" && [ -n "$HOSTTOOLS" ]; then
    # Only needed to bootstrap if the prefix has no glib yet.
    export PATH="$HOSTTOOLS:$PATH"
fi

WANT=("$@")
[ "${#WANT[@]}" -eq 0 ] && WANT=(glib atk pango gdk-pixbuf)

export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$GTK2_PREFIX/bin:$PATH"
export CPPFLAGS="-I$GTK2_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$GTK2_PREFIX/lib -Wl,-rpath,$GTK2_PREFIX/lib ${LDFLAGS:-}"
# Host-compiler accommodation for code older than the compiler (same set as
# the GTK2 build; GCC 14+ promoted several diagnostics to errors).
: "${DEP_CFLAGS:=-O2 -g \
    -Wno-error=incompatible-pointer-types \
    -Wno-error=implicit-function-declaration \
    -Wno-error=implicit-int \
    -Wno-error=int-conversion \
    -Wno-error=return-mismatch \
    -Wno-error=declaration-missing-parameter-type}"
export CFLAGS="${DEP_CFLAGS} ${CFLAGS:-}"

mkdir -p "$GTK2_DL" "$GTK2_CACHE/src"

# ------------------------------------------------------------------ helpers --
fetch_tar() { # name url
    local name="$1" url="$2" tar="$GTK2_DL/$1"
    [ -f "$tar" ] || { log "downloading $(basename "$url")"; curl -fsSL -o "$tar" "$url" || die "download failed: $url"; }
    rm -rf "$GTK2_CACHE/src/$name"
    tar xf "$tar" -C "$GTK2_CACHE/src"
    printf '%s' "$GTK2_CACHE/src/$name"
}

# meson_build name srcdir [meson args...]
meson_build() {
    local name="$1" src="$2"; shift 2
    local bdir="$GTK2_PREFIX/build/$name"
    step "Building $name"
    rm -rf "$bdir"
    meson setup "$bdir" "$src" --prefix="$GTK2_PREFIX" --buildtype=release "$@" \
        >"$GTK2_PREFIX/$name.setup.log" 2>&1 \
        || { tail -30 "$GTK2_PREFIX/$name.setup.log"; die "$name configure failed"; }
    ninja -C "$bdir" >"$GTK2_PREFIX/$name.build.log" 2>&1 \
        || { tail -40 "$GTK2_PREFIX/$name.build.log"; die "$name build failed"; }
    ninja -C "$bdir" install >"$GTK2_PREFIX/$name.install.log" 2>&1 \
        || { tail -20 "$GTK2_PREFIX/$name.install.log"; die "$name install failed"; }
    log "$name installed"
}

want() { local w; for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }

# --------------------------------------------------------------------- GLib --
if want glib; then
    src="$(fetch_tar "glib-$GLIB_VERSION" \
        "https://download.gnome.org/sources/glib/2.66/glib-$GLIB_VERSION.tar.xz")"
    meson_build "glib-$GLIB_VERSION" "$src" \
        -Dinternal_pcre=true \
        -Dselinux=disabled -Dlibmount=disabled -Dnls=disabled \
        -Dman=false -Ddtrace=false -Dsystemtap=false \
        -Dgtk_doc=false -Dinstalled_tests=false
    export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi

# ---------------------------------------------------------------------- ATK --
if want atk; then
    src="$(fetch_tar "atk-$ATK_VERSION" \
        "https://download.gnome.org/sources/atk/2.38/atk-$ATK_VERSION.tar.xz")"
    meson_build "atk-$ATK_VERSION" "$src" \
        -Dintrospection=false -Ddocs=false
fi

# -------------------------------------------------------------------- Pango --
if want pango; then
    src="$(fetch_tar "pango-$PANGO_VERSION" \
        "https://download.gnome.org/sources/pango/1.48/pango-$PANGO_VERSION.tar.xz")"
    meson_build "pango-$PANGO_VERSION" "$src" \
        -Dintrospection=disabled -Dgtk_doc=false -Dinstall-tests=false \
        -Dlibthai=disabled -Dfontconfig=enabled -Dcairo=enabled \
        -Dxft=disabled -Dfreetype=enabled
fi

# -------------------------------------------------------------- gdk-pixbuf --
if want gdk-pixbuf; then
    src="$(fetch_tar "gdk-pixbuf-$GDK_PIXBUF_VERSION" \
        "https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-$GDK_PIXBUF_VERSION.tar.xz")"
    meson_build "gdk-pixbuf-$GDK_PIXBUF_VERSION" "$src" \
        -Dintrospection=disabled -Dgtk_doc=false -Ddocs=false -Dman=false \
        -Dtests=false -Dinstalled_tests=false -Dgio_sniffing=false
fi

step "Dependency stack ready in $GTK2_PREFIX"
PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig" pkg-config --modversion \
    glib-2.0 atk pango gdk-pixbuf-2.0 2>/dev/null || true
dim "gtester is now $GTK2_PREFIX/bin/gtester if the prefix's GLib provides it"
