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
[ "${#WANT[@]}" -eq 0 ] && WANT=(glib atk pango gdk-pixbuf dconf libxklavier libunique gtksourceview pcre vte libwnck libsoup libgtop libcanberra libcroco librsvg libsigcpp glibmm cairomm pangomm atkmm gtkmm poppler json-glib babl gegl libmypaint mypaint-brushes gexiv2 glib-networking)

export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:$GTK2_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
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
# fetch_tar / fetch_tar_named come from lib.sh.

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

# C++ bindings (gtkmm 2.4 stack) need c++ flags, not the C ones (DEP_CFLAGS
# carries -std=gnu11, which g++ rejects), and era C++ needs a few relaxations
# under a modern compiler.
cxx_build() {
    local name="$1" src="$2"; shift 2
    (
        export CFLAGS="-O2 -g -fcommon -D_GNU_SOURCE -DG_CONST_RETURN=const \
-include stdlib.h -include stdint.h"
        export CXXFLAGS="-O2 -g -std=gnu++14 -fcommon -D_GNU_SOURCE -DG_CONST_RETURN=const \
-include stdlib.h -include stdint.h -fpermissive \
-Wno-error=deprecated-declarations -Wno-error=unused-parameter \
-Wno-error=cast-function-type -Wno-error=class-memaccess \
-Wno-error=deprecated-copy -Wno-error=stringop-overflow \
-Wno-error=array-bounds -Wno-error=mismatched-new-delete \
-Wno-error=maybe-uninitialized -Wno-error=restrict"
        autotools_build "$name" "$src" "$@"
    )
}

# --------------------------------------------------------------------- GLib --
if want glib; then
    src="$(fetch_tar "glib-$GLIB_VERSION" \
        "https://download.gnome.org/sources/glib/${GLIB_VERSION%.*}/glib-$GLIB_VERSION.tar.xz")"
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
    # No startup-notification: it links the host libstartup-notification, which
    # calls XGetXCBConnection() on our (non-XCB) Display and crashes libwnck
    # users such as mate-system-monitor.
    autotools_build "libwnck-$LIBWNCK_VERSION" "$src" \
        --disable-gtk-doc --disable-introspection --disable-startup-notification
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

# ---------------------------------------------------------------- libcroco --
if want libcroco; then
    src="$(fetch_tar "libcroco-$LIBCROCO_VERSION" \
        "https://download.gnome.org/sources/libcroco/0.6/libcroco-$LIBCROCO_VERSION.tar.xz")"
    autotools_build "libcroco-$LIBCROCO_VERSION" "$src" --disable-gtk-doc
fi

# ----------------------------------------------------------------- librsvg --
if want librsvg; then
    src="$(fetch_tar "librsvg-$LIBRSVG_VERSION" \
        "https://download.gnome.org/sources/librsvg/2.40/librsvg-$LIBRSVG_VERSION.tar.xz")"
    # rsvg-private.h uses libxml2 types without including libxml/parser.h.
    ( export CPPFLAGS="-I/usr/include/libxml2 -include libxml/parser.h $CPPFLAGS"
      autotools_build "librsvg-$LIBRSVG_VERSION" "$src" \
          --disable-gtk-doc --disable-introspection )
fi

# ------------------------------------------------- gtkmm 2.4 C++ bindings --
if want libsigcpp; then
    src="$(fetch_tar "libsigc++-$LIBSIGCPP_VERSION" \
        "https://download.gnome.org/sources/libsigc++/2.10/libsigc++-$LIBSIGCPP_VERSION.tar.xz")"
    cxx_build "libsigc++-$LIBSIGCPP_VERSION" "$src" --disable-documentation
fi

if want glibmm; then
    src="$(fetch_tar "glibmm-$GLIBMM_VERSION" \
        "https://download.gnome.org/sources/glibmm/2.48/glibmm-$GLIBMM_VERSION.tar.xz")"
    cxx_build "glibmm-$GLIBMM_VERSION" "$src" --disable-documentation --disable-fulldocs
    # glibmm 2.48.1 has a one-character slip in its (inline, header-only)
    # GPrivate wrapper: gobj() returns the GPrivate struct where every sibling
    # returns its address.  GLib's GPrivate is a struct since 2.32, so this
    # only compiles if corrected.
    sed -i 's|return gobject_; }|return \&gobject_; }|' \
        "$GTK2_PREFIX/include/glibmm-2.4/glibmm/threads.h"
fi

if want cairomm; then
    src="$(fetch_tar "cairomm-$CAIROMM_VERSION" \
        "https://download.gnome.org/sources/cairomm/1.12/cairomm-$CAIROMM_VERSION.tar.xz")"
    cxx_build "cairomm-$CAIROMM_VERSION" "$src" --disable-documentation --disable-fulldocs
fi

if want pangomm; then
    src="$(fetch_tar "pangomm-$PANGOMM_VERSION" \
        "https://download.gnome.org/sources/pangomm/2.40/pangomm-$PANGOMM_VERSION.tar.xz")"
    cxx_build "pangomm-$PANGOMM_VERSION" "$src" --disable-documentation --disable-fulldocs
fi

if want atkmm; then
    src="$(fetch_tar "atkmm-$ATKMM_VERSION" \
        "https://download.gnome.org/sources/atkmm/2.24/atkmm-$ATKMM_VERSION.tar.xz")"
    cxx_build "atkmm-$ATKMM_VERSION" "$src" --disable-documentation --disable-fulldocs
fi

if want gtkmm; then
    src="$(fetch_tar "gtkmm-$GTKMM_VERSION" \
        "https://download.gnome.org/sources/gtkmm/2.24/gtkmm-$GTKMM_VERSION.tar.xz")"
    cxx_build "gtkmm-$GTKMM_VERSION" "$src" --disable-documentation --disable-fulldocs
fi

# ---------------------------------------------------------------- poppler --
if want poppler; then
    src="$(fetch_tar "poppler-$POPPLER_VERSION" \
        "https://poppler.freedesktop.org/poppler-$POPPLER_VERSION.tar.xz")"
    autotools_build "poppler-$POPPLER_VERSION" "$src" \
        --disable-gtk-doc --disable-cpp --enable-cairo-output \
        --disable-poppler-qt4 --disable-poppler-qt5 \
        --disable-libopenjpeg --disable-utils
fi

# ---------------------------------------------------------------- json-glib --
# GEGL and GIMP both require json-glib-1.0.
if want json-glib; then
    src="$(fetch_tar "json-glib-$JSON_GLIB_VERSION" \
        "https://download.gnome.org/sources/json-glib/${JSON_GLIB_VERSION%.*}/json-glib-$JSON_GLIB_VERSION.tar.xz")"
    # json-glib 1.4's autotools build insists on the `mesontest` program (the
    # pre-1.0 spelling of `meson test`), which modern meson no longer installs,
    # so build it with meson.
    meson_build "json-glib-$JSON_GLIB_VERSION" "$src" \
        -Dintrospection=false -Ddocs=false -Dman=false
fi

# --------------------------------------------------------------------- babl --
# babl and GEGL are GIMP's pixel-conversion and processing engine.  GNOME's
# release tarballs for them are not being served right now, so use GitLab's
# generated archives (fetch_tar_named renames the extracted directory).
if want babl; then
    bt="BABL_${BABL_VERSION//./_}"
    src="$(fetch_tar_named "babl-$BABL_VERSION" \
        "https://gitlab.gnome.org/GNOME/babl/-/archive/$bt/babl-$bt.tar.bz2")"
    gitify "$src"
    meson_build "babl-$BABL_VERSION" "$src" \
        -Denable-gir=false -Denable-vapi=false -Dwith-docs=false -Dwith-lcms=true
fi

# --------------------------------------------------------------------- GEGL --
if want gegl; then
    gt="GEGL_${GEGL_VERSION//./_}"
    src="$(fetch_tar_named "gegl-$GEGL_VERSION" \
        "https://gitlab.gnome.org/GNOME/gegl/-/archive/$gt/gegl-$gt.tar.bz2")"
    # The GitLab archive omits the generated OpenCL kernel headers that the
    # release tarball ships; generate them with GEGL's own script.
    if [ ! -f "$src/opencl/colors.cl.h" ]; then
        log "generating GEGL OpenCL kernel headers"
        ( cd "$src" && for cl in opencl/*.cl; do
              python3 opencl/cltostring.py "$cl" "$cl.h" || exit 1
          done ) || die "gegl: OpenCL header generation failed"
    fi
    meson_build "gegl-$GEGL_VERSION" "$src" \
        -Ddocs=false -Dworkshop=false -Dintrospection=false -Dvapigen=disabled \
        -Dgdk-pixbuf=enabled -Dcairo=enabled -Dpango=enabled -Dpangocairo=enabled \
        -Dlcms=enabled -Dlibtiff=enabled -Dwebp=enabled -Dlibrsvg=enabled \
        -Dgexiv2=disabled -Dgraphviz=disabled -Djasper=disabled -Dlensfun=disabled \
        -Dlibav=disabled -Dlibraw=disabled -Dpoppler=disabled -Dpygobject=disabled \
        -Dsdl2=disabled -Dumfpack=disabled -Dlua=disabled -Dmrg=disabled \
        -Dmaxflow=disabled -Dopenexr=disabled -Dlibv4l=disabled -Dlibv4l2=disabled \
        -Dlibspiro=disabled
fi

# --------------------------------------------------------------- libmypaint --
# GIMP's MyPaint brush tool.  --disable-gegl keeps it independent of GEGL
# (built just above); GIMP drives libmypaint directly.
if want libmypaint; then
    src="$(fetch_tar "libmypaint-$LIBMYPAINT_VERSION" \
        "https://github.com/mypaint/libmypaint/releases/download/v$LIBMYPAINT_VERSION/libmypaint-$LIBMYPAINT_VERSION.tar.xz")"
    # The 1.6.1 tarball ships a release-time config.h with
    # MYPAINT_CONFIG_USE_GLIB 1.  In an out-of-tree build `#include "config.h"`
    # searches the includer's directory first and picks that one up instead of
    # the generated (USE_GLIB 0) header, so drop it.
    rm -f "$src/config.h"
    autotools_build "libmypaint-$LIBMYPAINT_VERSION" "$src" \
        --disable-gegl --disable-docs --disable-i18n
fi

# ----------------------------------------------------------- mypaint-brushes --
if want mypaint-brushes; then
    src="$(fetch_tar "mypaint-brushes-$MYPAINT_BRUSHES_VERSION" \
        "https://github.com/mypaint/mypaint-brushes/archive/refs/tags/v$MYPAINT_BRUSHES_VERSION.tar.gz")"
    autotools_build "mypaint-brushes-$MYPAINT_BRUSHES_VERSION" "$src"
fi

# ------------------------------------------------------------------ gexiv2 --
# GIMP's metadata editor.  Built against the host Exiv2 0.28 (a C++ library
# with no GLib dependency) and our prefix GLib.
# --------------------------------------------------------- glib-networking --
# GIO's TLS backend.  GIMP 2.10's configure runs g_tls_backend_supports_tls()
# and fails without it.  The module lands in $GTK2_PREFIX/lib/gio/modules,
# which our GLib's compiled-in giomoduledir points at.
if want glib-networking; then
    src="$(fetch_tar "glib-networking-$GLIB_NETWORKING_VERSION" \
        "https://download.gnome.org/sources/glib-networking/${GLIB_NETWORKING_VERSION%.*}/glib-networking-$GLIB_NETWORKING_VERSION.tar.xz")"
    meson_build "glib-networking-$GLIB_NETWORKING_VERSION" "$src" \
        -Dlibproxy_support=false -Dgnome_proxy_support=false \
        -Dpkcs11_support=false -Dinstalled_tests=false
fi

if want gexiv2; then
    src="$(fetch_tar_named "gexiv2-$GEXIV2_VERSION" \
        "https://gitlab.gnome.org/GNOME/gexiv2/-/archive/gexiv2-$GEXIV2_VERSION/gexiv2-gexiv2-$GEXIV2_VERSION.tar.bz2")"
    meson_build "gexiv2-$GEXIV2_VERSION" "$src" \
        -Dintrospection=false -Dgtk_doc=false -Dvapi=false -Dpython3=false \
        -Dtools=false -Dtests=false
fi

step "Dependency stack ready in $GTK2_PREFIX"
PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig" pkg-config --modversion \
    glib-2.0 atk pango gdk-pixbuf-2.0 dconf 2>/dev/null || true
