#!/usr/bin/env bash
# build-gtk2.sh — build stock GTK+ 2 against the shim, unmodified.
#
# The GTK2 source tree is never patched: it is configured out-of-tree with the
# shim's pkg-config and library paths, and built with the X11 GDK backend.  Any
# change needed to make this succeed belongs in xlib-wayland, not here.
#
# Usage: scripts/build-gtk2.sh [--configure] [--jobs N]
#   --configure  stop after `configure` (useful for gap analysis)
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

[ -d "$GTK2_SRC" ] || die "no GTK2 source at $GTK2_SRC (run scripts/fetch-sources.sh)"
[ -e "$GTK2_PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"

# The era-correct dependency stack lives in the prefix; prefer it and its tools.
use_prefix

# glib-mkenums and glib-genmarshal are build-time host tools GTK2 needs; on
# some distros they live in a separate package.  Stage them if necessary.
if HOSTTOOLS="$(stage_glib_tools)" && [ -n "$HOSTTOOLS" ]; then
    export PATH="$HOSTTOOLS:$PATH"
    # GTK2's configure reads these through pkg-config's glib_mkenums /
    # glib_genmarshal variables, which hardcode the distro's /usr/bin path.
    # Exporting them makes configure prefer the staged tools.
    export GLIB_MKENUMS="$HOSTTOOLS/glib-mkenums"
    export GLIB_GENMARSHAL="$HOSTTOOLS/glib-genmarshal"
fi

# --- what the toolkit links against -----------------------------------------
# Our prefix supplies x11 and xft (the shim).  Everything else, notably the X11
# extension libraries, comes from the host but will bind to the shim at runtime
# because the shim installs as libX11.so.6.
export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CPPFLAGS="-I$GTK2_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$GTK2_PREFIX/lib -Wl,-rpath,$GTK2_PREFIX/lib ${LDFLAGS:-}"

# Host-compiler accommodation (not a source patch, not a shim change):
# GTK+ 2.24.33 predates GCC 14, which turned several C diagnostics that older
# compilers merely warned about into hard errors.  Downgrade just those.
: "${GTK2_CFLAGS:=-O2 -g \
    -Wno-error=incompatible-pointer-types \
    -Wno-error=implicit-function-declaration \
    -Wno-error=implicit-int \
    -Wno-error=int-conversion \
    -Wno-error=return-mismatch \
    -Wno-error=declaration-missing-parameter-type}"
export CFLAGS="${GTK2_CFLAGS} ${CFLAGS:-}"
export CXXFLAGS="${GTK2_CFLAGS} ${CXXFLAGS:-}"

: "${GTK2_CONFIGURE_OPTS:=
  --prefix=$GTK2_PREFIX
  --with-gdktarget=x11
  --disable-gtk-doc
  --disable-cups
  --disable-papi
  --disable-introspection
  --disable-xinerama
  --with-xinput=no
  --disable-dependency-tracking
}"

step "Configuring GTK+ $GTK2_VERSION against the shim"
mkdir -p "$GTK2_BUILD"
cd "$GTK2_BUILD"

# Reconfigure when there is no Makefile, when the existing one points at a
# glib-mkenums path that no longer exists (the tools were staged after the last
# configure), or when it lacks the host-compiler accommodation.  configure is
# cheap and idempotent.
NEED_CONFIG=0
if [ -f Makefile ]; then
    grep -q 'Wno-error=incompatible-pointer-types' gdk/Makefile 2>/dev/null || NEED_CONFIG=1
    if [ -n "${HOSTTOOLS:-}" ]; then
        grep -q "$HOSTTOOLS/glib-mkenums" gdk/Makefile 2>/dev/null || NEED_CONFIG=1
    fi
else
    NEED_CONFIG=1
fi

if [ "$NEED_CONFIG" = 1 ]; then
    # shellcheck disable=SC2086
    "$GTK2_SRC/configure" $GTK2_CONFIGURE_OPTS >configure.log 2>&1 \
        || { warn "configure failed; last lines:"; tail -40 configure.log >&2; \
             warn "full log: $GTK2_BUILD/configure.log"; exit 1; }
    log "configure OK"
else
    log "already configured (remove $GTK2_BUILD/Makefile to redo)"
fi

if [ "$CONFIGURE_ONLY" = 1 ]; then
    log "stopping after configure (--configure)"
    exit 0
fi

step "Building GTK+ ($JOBS jobs)"
make -j"$JOBS" >build.log 2>&1 || { warn "build failed; last lines:"; tail -40 build.log >&2; \
                                     warn "full log: $GTK2_BUILD/build.log"; exit 1; }
step "Installing GTK+ into $GTK2_PREFIX"
make install >install.log 2>&1 || { tail -25 install.log; die "install failed"; }

log "GTK+ installed: $(PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig" pkg-config --modversion gtk+-2.0 2>/dev/null || echo '?')"
