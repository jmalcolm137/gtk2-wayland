#!/usr/bin/env bash
# build-shim.sh — build and install xlib-wayland into $GTK2_PREFIX.
#
# The shim is a separate upstream project; this script never edits it.  It
# builds a checkout at $XLIB_WAYLAND (sibling by default) and installs it next
# to GTK2 so that `-lX11` and `dlopen("libX11.so.6")` resolve to the shim.
#
# Usage: scripts/build-shim.sh [--update]
#   --update  git fetch + checkout $XLIB_WAYLAND_REF first
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

UPDATE=0
for a in "$@"; do case "$a" in --update) UPDATE=1;; *) die "unknown argument: $a";; esac; done

[ -d "$XLIB_WAYLAND" ] || die "no shim checkout at $XLIB_WAYLAND (run scripts/fetch-sources.sh --shim)"

if [ "$UPDATE" = 1 ] && [ -d "$XLIB_WAYLAND/.git" ]; then
    step "Updating shim to $XLIB_WAYLAND_REF"
    ( cd "$XLIB_WAYLAND" && git fetch --all --prune && git checkout "$XLIB_WAYLAND_REF" )
fi
if [ -d "$XLIB_WAYLAND/.git" ]; then
    log "shim revision: $(cd "$XLIB_WAYLAND" && git rev-parse --short HEAD)"
fi

BUILDDIR="$GTK2_PREFIX/build/xlib-wayland"
step "Building the shim into $GTK2_PREFIX"
if [ ! -d "$BUILDDIR" ]; then
    meson setup "$BUILDDIR" "$XLIB_WAYLAND" --prefix="$GTK2_PREFIX" >"$BUILDDIR.setup.log" 2>&1 \
        || { tail -25 "$BUILDDIR.setup.log"; die "meson setup failed"; }
else
    meson setup --reconfigure "$BUILDDIR" "$XLIB_WAYLAND" --prefix="$GTK2_PREFIX" \
        >"$BUILDDIR.setup.log" 2>&1 || { tail -25 "$BUILDDIR.setup.log"; die "meson reconfigure failed"; }
fi

ninja -C "$BUILDDIR" >"$BUILDDIR.build.log" 2>&1 || { tail -30 "$BUILDDIR.build.log"; die "shim build failed"; }
meson install -C "$BUILDDIR" >"$BUILDDIR.install.log" 2>&1 || { tail -20 "$BUILDDIR.install.log"; die "shim install failed"; }

for lib in libX11.so.6 libXft.so.2; do
    [ -e "$GTK2_PREFIX/lib/$lib" ] || die "expected $GTK2_PREFIX/lib/$lib after install"
done
log "shim installed: $(ls -l "$GTK2_PREFIX/lib/libX11.so.6" | awk '{print $NF}')"
