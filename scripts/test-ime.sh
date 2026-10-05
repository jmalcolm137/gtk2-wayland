#!/usr/bin/env bash
# test-ime.sh — GTK2 input-method end to end.
#
# GTK2's im-xim module drives the shim's XIM bridge (GTK_IM_MODULE=xim), and the
# shim talks to the compositor's text-input.  The headless compositor's scripted
# text-input server sends a preedit and commits "你好"; tests/imtest.c checks that
# a real GtkEntry receives the commit.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

PREFIX="$GTK2_PREFIX"
HC="$PREFIX/build/xlib-wayland/headless-compositor"
[ -x "$HC" ] || die "headless compositor not built (run scripts/build-shim.sh)"
[ -e "$PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"

OUT="$GTK2_ROOT/tests/out"
mkdir -p "$OUT"
BIN="$PREFIX/build/imtest"

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --exists gtk+-2.0 \
    || die "gtk+-2.0 not found in $PREFIX"

step "building imtest"
# shellcheck disable=SC2046
gcc -O0 \
    $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --cflags gtk+-2.0) \
    "$GTK2_ROOT/tests/imtest.c" -o "$BIN" \
    $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --libs gtk+-2.0) \
    || die "could not build imtest"

step "running GTK2 im-xim under the headless compositor"
RT="$(mktemp -d)"
trap 'rm -rf "$RT"' EXIT

XDG_RUNTIME_DIR="$RT" timeout 12 "$HC" --socket mwime --size 400x300 \
    --timeout 6 --output "$OUT/imtest.png" >/dev/null 2>&1 &
hc=$!
sleep 0.3
env GTK_IM_MODULE=xim \
    XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY=mwime \
    LD_LIBRARY_PATH="$PREFIX/lib" GSETTINGS_BACKEND=memory \
    XDG_DATA_DIRS="$PREFIX/share:/usr/share" \
    timeout 10 "$BIN" >"$OUT/imtest.out" 2>"$OUT/imtest.err" || true
wait "$hc" 2>/dev/null || true

cat "$OUT/imtest.out"
if grep -q '^IMTEST:COMMIT' "$OUT/imtest.out"; then
    log "GTK2 committed through the shim's XIM bridge"
else
    warn "GTK2 did not commit; last error lines:"
    tail -20 "$OUT/imtest.err" >&2
    exit 1
fi
