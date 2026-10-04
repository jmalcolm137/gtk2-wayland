#!/usr/bin/env bash
# build-mate.sh — build MATE 1.10 components against the GTK2 prefix.
#
# Sources stay pristine: tarballs are configured out-of-tree under
# $GTK2_PREFIX/build/mate/<component>-<version> and installed into
# $GTK2_PREFIX.  Unknown configure options are warnings under autoconf, so a
# common flag set can be passed to every component.
#
# Usage: scripts/build-mate.sh [component ...]
#   With no arguments, builds MATE_DEFAULT in dependency order.  Named
#   components are built in the order given.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

MATE_LOCK="$GTK2_ROOT/config/mate.lock"
[ -f "$MATE_LOCK" ] || die "missing $MATE_LOCK"
MATE_SRC="$GTK2_CACHE/src/mate"
: "${MATE_MIRROR:=https://pub.mate-desktop.org/releases/1.10}"

[ -e "$GTK2_PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"
[ -x "$GTK2_PREFIX/bin/gtester" ] || warn "prefix GLib not found; run scripts/build-deps.sh first"

use_prefix
# MATE's configure scripts require itstool even when no user guide is built.
# Append the host-tools dir so it is found, but keep the prefix's glib tools
# (gdbus-codegen, glib-mkenums, glib-genmarshal) first -- a newer codegen would
# emit code that needs symbols GLib 2.48 does not have.
if DOCTOOLS="$(stage_doc_tools)" && [ -n "$DOCTOOLS" ]; then
    export PATH="$PATH:$DOCTOOLS"
fi
# Host-compiler accommodation, as for GTK2 and the dependency stack.
: "${MATE_CFLAGS:=-O2 -g -fcommon -include stdlib.h -include string.h -include stdint.h \
    -Wno-error=incompatible-pointer-types \
    -Wno-error=implicit-function-declaration \
    -Wno-error=implicit-int \
    -Wno-error=int-conversion \
    -Wno-error=return-mismatch \
    -Wno-error=declaration-missing-parameter-type \
    -Wno-error=deprecated-declarations}"
export CFLAGS="${MATE_CFLAGS} ${CFLAGS:-}"
export CXXFLAGS="${MATE_CFLAGS} ${CXXFLAGS:-}"
export CPPFLAGS="-I$GTK2_PREFIX/include ${CPPFLAGS:-}"
export LDFLAGS="-L$GTK2_PREFIX/lib -Wl,-rpath,$GTK2_PREFIX/lib ${LDFLAGS:-}"

# Components that are GUI applications, in a sensible order.  The foundation
# first, then the applications whose dependencies are already in the prefix.
MATE_DEFAULT=(mate-common mate-desktop libmatekbd libmateweather mate-menus
              engrampa eom mozo)

ver_of() { sed -n "s/^$1=//p" "$MATE_LOCK" | head -1; }

# Per-component configure flags beyond the common set.
extra_flags() {
    case "$1" in
        libmateweather) printf '%s' "--disable-python";;
        mate-menus)     printf '%s' "--disable-python";;
        eom)            printf '%s' "--disable-python";;
        engrampa)       printf '%s' "";;
        caja)           printf '%s' "--disable-packagekit --disable-update-mimedb --disable-icon-update";;
        *)              printf '%s' "";;
    esac
}

build_one() {
    local c="$1" v src bdir
    v="$(ver_of "$c")"
    [ -n "$v" ] || die "unknown MATE component: $c"
    src="$MATE_SRC/$c-$v"
    if [ ! -d "$src" ]; then
        log "$c-$v not fetched; fetching"
        "$GTK2_ROOT/scripts/fetch-mate.sh" "$c"
    fi
    bdir="$GTK2_PREFIX/build/mate/$c-$v"
    step "Building $c $v"

    rm -rf "$bdir"
    mkdir -p "$bdir"
    cd "$bdir"

    # Prefer the shipped configure; regenerate only if it is absent.
    local configure="$src/configure"
    if [ ! -x "$configure" ]; then
        log "no shipped configure; running autoreconf"
        ( cd "$src" && NOCONFIGURE=1 ./autogen.sh >/dev/null 2>&1 ) \
            || ( cd "$src" && autoreconf -fi ) \
            || die "$c: autoreconf failed"
        configure="$src/configure"
    fi

    # shellcheck disable=SC2086
    "$configure" \
        --prefix="$GTK2_PREFIX" \
        --disable-static \
        --disable-maintainer-mode \
        --disable-gtk-doc --disable-gtk-doc-html \
        --disable-scrollkeeper \
        $(extra_flags "$c") \
        >configure.log 2>&1 \
        || { tail -35 configure.log; die "$c: configure failed"; }
    make -j"$JOBS" >build.log 2>&1 \
        || { grep -nE 'error:|undefined reference|Error [0-9]' build.log | head -20; \
             tail -12 build.log; die "$c: build failed"; }
    make install >install.log 2>&1 || { tail -15 install.log; die "$c: install failed"; }
    log "$c $v installed"
}

if [ "${1:-}" = "--list" ]; then
    for c in "${MATE_DEFAULT[@]}"; do printf '%s ' "$c"; done; echo; exit 0
fi

if [ "$#" -gt 0 ]; then WANT=("$@"); else WANT=("${MATE_DEFAULT[@]}"); fi
for c in "${WANT[@]}"; do build_one "$c"; done

step "MATE components built"
for c in "${WANT[@]}"; do printf '  %s %s\n' "$c" "$(ver_of "$c")" >&2; done
