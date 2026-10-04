#!/usr/bin/env bash
# build-deps.sh — build the MATE-era supporting stack into $GTK2_PREFIX.
#
# GTK+ 2.24.33, MATE 1.10 and GIMP 2.10 all build against the same c.2016 GNOME
# stack; MATE 1.10 is the constraint (it defines compat functions GLib later
# added).  This script builds GLib, ATK, Pango, gdk-pixbuf and dconf into
# $GTK2_PREFIX so the only non-period-correct component is our libX11 shim.
#
# cairo/fontconfig/FreeType/HarfBuzz/fribidi come from the host: they are
# ABI-stable across the window and do not carry GLib.
#
# The stack mixes build systems: glib/atk/dconf use autotools, pango/gdk-pixbuf
# use meson.
#
# Usage: scripts/build-deps.sh [glib] [atk] [pango] [gdk-pixbuf] [dconf]
#   With no arguments, builds all five in order.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

# ---------------------------------------------------------------- host tools -
if HOSTTOOLS="$(stage_glib_tools)" && [ -n "$HOSTTOOLS" ]; then
    export PATH="$HOSTTOOLS:$PATH"
fi

WANT=("$@")
[ "${#WANT[@]}" -eq 0 ] && WANT=(glib atk pango gdk-pixbuf dconf libxklavier libunique gtksourceview pcre vte libwnck libsoup libgtop libcanberra)

export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$GTK2_PREFIX/bin:$PATH"
export CPPFLAGS="-I$GTK2_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$GTK2_PREFIX/lib -Wl,-rpath,$GTK2_PREFIX/lib ${LDFLAGS:-}"
# Host-compiler accommodation for code older than the compiler (GCC 14+
# promoted several diagnostics to errors).
: "${DEP_CFLAGS:=-O2 -g -std=gnu11 -fcommon -D_GNU_SOURCE -DG_CONST_RETURN=const \
    -include stdlib.h -include stdint.h \
    -Wno-error=incompatible-pointer-types \
    -Wno-error=implicit-function-declaration \
    -Wno-error=implicit-int \
    -Wno-error=int-conversion \
    -Wno-error=return-mismatch \
    -Wno-error=declaration-missing-parameter-type}"
export CFLAGS="${DEP_CFLAGS} ${CFLAGS:-}"
export CXXFLAGS="${DEP_CFLAGS} ${CXXFLAGS:-}"

mkdir -p "$GTK2_DL" "$GTK2_CACHE/src"

# Automake's old in-tree py-compile uses the `imp` module, removed in Python
# 3.12; prefer the system py-compile when one is installed.
SYS_PY_COMPILE=""
for p in /usr/share/automake-*/py-compile; do [ -x "$p" ] && SYS_PY_COMPILE="$p"; done

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
    step "Building $name (meson)"
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

# autotools_build name srcdir [configure args...]
autotools_build() {
    local name="$1" src="$2"; shift 2
    local bdir="$GTK2_PREFIX/build/$name" cfg="$src/configure"
    step "Building $name (autotools)"
    rm -rf "$bdir"; mkdir -p "$bdir"; cd "$bdir"
    if [ ! -x "$cfg" ]; then
        ( cd "$src" && NOCONFIGURE=1 ./autogen.sh >/dev/null 2>&1 ) \
            || ( cd "$src" && autoreconf -fi ) \
            || die "$name: autoreconf failed"
    fi
    "$cfg" --prefix="$GTK2_PREFIX" --disable-static --disable-maintainer-mode "$@" \
        >configure.log 2>&1 || { tail -35 configure.log; die "$name configure failed"; }
    local pc=""
    [ -n "$SYS_PY_COMPILE" ] && pc="py_compile=$SYS_PY_COMPILE"
    # shellcheck disable=SC2086
    make -j"$JOBS" $pc >build.log 2>&1 \
        || { grep -nE 'error:|undefined reference|Error [0-9]' build.log | head -20; \
             tail -12 build.log; die "$name build failed"; }
    # shellcheck disable=SC2086
    make install $pc >install.log 2>&1 || { tail -15 install.log; die "$name install failed"; }
    log "$name installed"
}

want() { local w; for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done; return 1; }

# --------------------------------------------------------------------- GLib --
if want glib; then
    src="$(fetch_tar "glib-$GLIB_VERSION" \
        "https://download.gnome.org/sources/glib/2.48/glib-$GLIB_VERSION.tar.xz")"
    autotools_build "glib-$GLIB_VERSION" "$src" \
        --with-pcre=internal \
        --disable-selinux --disable-fam --disable-xattr --disable-man \
        --disable-gtk-doc --disable-compile-warnings \
        --disable-systemtap --disable-dtrace
fi

# ---------------------------------------------------------------------- ATK --
if want atk; then
    src="$(fetch_tar "atk-$ATK_VERSION" \
        "https://download.gnome.org/sources/atk/2.18/atk-$ATK_VERSION.tar.xz")"
    autotools_build "atk-$ATK_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection
fi

# -------------------------------------------------------------------- Pango --
if want pango; then
    src="$(fetch_tar "pango-$PANGO_VERSION" \
        "https://download.gnome.org/sources/pango/1.38/pango-$PANGO_VERSION.tar.xz")"
    # With Xft: pangoxft is required by marco (and drawn through the
    # draw-level Xft API, which the shim implements).  Its Render-level entry
    # points are provided as no-ops; see xlib-wayland src/xft/xft.c.
    autotools_build "pango-$PANGO_VERSION" "$src" \
        --with-xft --disable-introspection --disable-gtk-doc
fi

# -------------------------------------------------------------- gdk-pixbuf --
if want gdk-pixbuf; then
    src="$(fetch_tar "gdk-pixbuf-$GDK_PIXBUF_VERSION" \
        "https://download.gnome.org/sources/gdk-pixbuf/2.34/gdk-pixbuf-$GDK_PIXBUF_VERSION.tar.xz")"
    autotools_build "gdk-pixbuf-$GDK_PIXBUF_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection \
        --without-libjasper --with-libjpeg --with-libtiff --with-x11
fi

# ------------------------------------------------------------------- dconf --
if want dconf; then
    src="$(fetch_tar "dconf-$DCONF_VERSION" \
        "https://download.gnome.org/sources/dconf/0.26/dconf-$DCONF_VERSION.tar.xz")"
    autotools_build "dconf-$DCONF_VERSION" "$src" \
        --disable-gtk-doc --disable-man
fi

# --------------------------------------------------------------- libxklavier --
if want libxklavier; then
    src="$(fetch_tar "libxklavier-$LIBXKLAVIER_VERSION" \
        "https://people.freedesktop.org/~svu/libxklavier-$LIBXKLAVIER_VERSION.tar.bz2")"
    autotools_build "libxklavier-$LIBXKLAVIER_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection
fi

# ---------------------------------------------------------------- libunique --
if want libunique; then
    src="$(fetch_tar "libunique-$LIBUNIQUE_VERSION" \
        "https://download.gnome.org/sources/libunique/1.1/libunique-$LIBUNIQUE_VERSION.tar.bz2")"
    autotools_build "libunique-$LIBUNIQUE_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection --disable-maintainer-flags
fi

# ------------------------------------------------------------ gtksourceview --
if want gtksourceview; then
    src="$(fetch_tar "gtksourceview-$GTKSOURCEVIEW_VERSION" \
        "https://download.gnome.org/sources/gtksourceview/2.10/gtksourceview-$GTKSOURCEVIEW_VERSION.tar.bz2")"
    autotools_build "gtksourceview-$GTKSOURCEVIEW_VERSION" "$src" --disable-gtk-doc
fi

# -------------------------------------------------------------------- PCRE --
if want pcre; then
    src="$(fetch_tar "pcre-$PCRE_VERSION" \
        "https://downloads.sourceforge.net/project/pcre/pcre/$PCRE_VERSION/pcre-$PCRE_VERSION.tar.gz")"
    autotools_build "pcre-$PCRE_VERSION" "$src" \
        --enable-utf --enable-unicode-properties
fi

# --------------------------------------------------------------------- VTE --
if want vte; then
    src="$(fetch_tar "vte-$VTE_VERSION" \
        "https://download.gnome.org/sources/vte/0.28/vte-$VTE_VERSION.tar.xz")"
    autotools_build "vte-$VTE_VERSION" "$src" --disable-gtk-doc
fi

# ------------------------------------------------------------------ libwnck --
if want libwnck; then
    src="$(fetch_tar "libwnck-$LIBWNCK_VERSION" \
        "https://download.gnome.org/sources/libwnck/2.30/libwnck-$LIBWNCK_VERSION.tar.xz")"
    autotools_build "libwnck-$LIBWNCK_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection
fi

# ------------------------------------------------------------------ libsoup --
if want libsoup; then
    src="$(fetch_tar "libsoup-$LIBSOUP_VERSION" \
        "https://download.gnome.org/sources/libsoup/2.54/libsoup-$LIBSOUP_VERSION.tar.xz")"
    autotools_build "libsoup-$LIBSOUP_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection --disable-tls-check
fi

# ------------------------------------------------------------------ libgtop --
if want libgtop; then
    src="$(fetch_tar "libgtop-$LIBGTOP_VERSION" \
        "https://download.gnome.org/sources/libgtop/2.40/libgtop-$LIBGTOP_VERSION.tar.xz")"
    autotools_build "libgtop-$LIBGTOP_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection
fi

# --------------------------------------------------------------- libcanberra --
if want libcanberra; then
    src="$(fetch_tar "libcanberra-$LIBCANBERRA_VERSION" \
        "https://0pointer.de/lennart/projects/libcanberra/libcanberra-$LIBCANBERRA_VERSION.tar.xz")"
    autotools_build "libcanberra-$LIBCANBERRA_VERSION" "$src" \
        --disable-gtk-doc --enable-gtk --disable-gtk3 \
        --disable-alsa --disable-pulse --disable-gstreamer --disable-oss \
        --disable-udev --disable-tdb --disable-lynx
fi

step "Dependency stack ready in $GTK2_PREFIX"
PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig" pkg-config --modversion \
    glib-2.0 atk pango gdk-pixbuf-2.0 dconf 2>/dev/null || true
