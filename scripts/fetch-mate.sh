#!/usr/bin/env bash
# fetch-mate.sh — download and unpack MATE 1.10 component sources.
#
# Sources come from the MATE release mirror.  They are unpacked under
# $GTK2_CACHE/src/mate/<component>-<version>.  No root, nothing is patched.
#
# Usage: scripts/fetch-mate.sh [component ...]
#   With no arguments, fetches the MATE_DEFAULT set (the foundation plus the
#   applications that do not need a rebuilt GTK2-era dependency).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

MATE_LOCK="$GTK2_ROOT/config/mate.lock"
[ -f "$MATE_LOCK" ] || die "missing $MATE_LOCK"

MATE_DL="$GTK2_DL/mate"
MATE_SRC="$GTK2_CACHE/src/mate"
: "${MATE_MIRROR:=https://pub.mate-desktop.org/releases/1.10}"

MATE_DEFAULT=(mate-common mate-desktop libmatekbd libmateweather mate-menus
              engrampa eom mozo)

WANT=("$@")
[ "${#WANT[@]}" -eq 0 ] && WANT=("${MATE_DEFAULT[@]}")

mkdir -p "$MATE_DL" "$MATE_SRC"

ver_of() { sed -n "s/^$1=//p" "$MATE_LOCK" | head -1; }

for c in "${WANT[@]}"; do
    v="$(ver_of "$c")"
    [ -n "$v" ] || die "unknown MATE component: $c (see config/mate.lock)"
    tarball="$MATE_DL/$c-$v.tar.xz"
    if [ ! -f "$tarball" ]; then
        log "downloading $c-$v"
        curl -fsSL -o "$tarball" "$MATE_MIRROR/$c-$v.tar.xz" \
            || die "download failed: $c-$v"
    fi
    rm -rf "$MATE_SRC/$c-$v"
    tar xf "$tarball" -C "$MATE_SRC"
    [ -d "$MATE_SRC/$c-$v" ] || die "unpack failed: $c-$v"
    dim "$c-$v"
done

step "MATE sources under $MATE_SRC"
