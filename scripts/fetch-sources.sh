#!/usr/bin/env bash
# fetch-sources.sh — download the toolkit source and stage the test compositor.
#
# No root.  Everything lands under $GTK2_CACHE (GTK2) and $LABWC_PREFIX (labwc).
#
# Usage: scripts/fetch-sources.sh [--shim] [--force]
#   --shim    also clone/update the xlib-wayland checkout (default: sibling)
#   --force   re-download / re-extract even if present
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

FETCH_SHIM=0
FORCE=0
for a in "$@"; do
    case "$a" in
        --shim)  FETCH_SHIM=1;;
        --force) FORCE=1;;
        *) die "unknown argument: $a";;
    esac
done

mkdir -p "$GTK2_DL" "$GTK2_CACHE/src"

# ------------------------------------------------------------- GTK+ 2 -------
step "GTK+ $GTK2_VERSION"
if [ "$FORCE" = 1 ] || [ ! -d "$GTK2_SRC" ]; then
    tarball="$GTK2_DL/$GTK2_TARBALL"
    [ "$FORCE" = 0 ] && [ -f "$tarball" ] || {
        log "downloading $GTK2_URL"
        curl -fsSL -o "$tarball" "$GTK2_URL" || die "download failed"
    }
    log "verifying checksum"
    if [ -n "${GTK2_SHA256:-}" ] && [ "${GTK2_SHA256}" != "UNKNOWN" ]; then
        echo "$GTK2_SHA256  $tarball" | sha256sum -c - \
            || die "GTK2 tarball checksum mismatch"
    else
        dim "sha256: $(sha256sum "$tarball" | awk '{print $1}')  (pin it in versions.lock)"
    fi
    rm -rf "$GTK2_SRC"
    tar xf "$tarball" -C "$GTK2_CACHE/src"
    log "unpacked to $GTK2_SRC"
else
    dim "already present: $GTK2_SRC"
fi

# --------------------------------------------------------- the shim ---------
if [ "$FETCH_SHIM" = 1 ]; then
    step "xlib-wayland shim"
    if [ ! -d "$XLIB_WAYLAND/.git" ]; then
        log "cloning $XLIB_WAYLAND_REPO -> $XLIB_WAYLAND"
        git clone "$XLIB_WAYLAND_REPO" "$XLIB_WAYLAND"
    fi
    ( cd "$XLIB_WAYLAND" && git fetch --all --prune && git checkout "$XLIB_WAYLAND_REF" )
    log "shim at $(cd "$XLIB_WAYLAND" && git rev-parse --short HEAD)"
else
    [ -d "$XLIB_WAYLAND" ] || warn "no shim checkout at $XLIB_WAYLAND (use --shim, or set XLIB_WAYLAND)"
fi

# --------------------------------------------------- the test compositor ----
step "nested labwc"
"$GTK2_ROOT/scripts/setup-labwc.sh"

step "done"
log "GTK2 source : $GTK2_SRC"
log "shim        : $XLIB_WAYLAND"
log "labwc       : $LABWC_PREFIX/usr/bin/labwc"
