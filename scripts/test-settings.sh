#!/usr/bin/env bash
# test-settings.sh — GTK2 reads XSETTINGS published by the shim.
#
# There is no settings daemon inside a shim process, so the shim is the
# _XSETTINGS_S0 manager itself: it publishes the config file named by
# XLIB_WAYLAND_XSETTINGS and GDK's XSettings client turns those into
# GtkSettings.  This checks a real GtkSettings reports the configured values.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

PREFIX="$GTK2_PREFIX"
HC="$PREFIX/build/xlib-wayland/headless-compositor"
[ -x "$HC" ] || die "headless compositor not built (run scripts/build-shim.sh)"
[ -e "$PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"

OUT="$GTK2_ROOT/tests/out"
mkdir -p "$OUT"
BIN="$PREFIX/build/settingstest"

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --exists gtk+-2.0 \
    || die "gtk+-2.0 not found in $PREFIX"

step "building settingstest"
# shellcheck disable=SC2046
gcc -O0 \
    $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --cflags gtk+-2.0) \
    "$GTK2_ROOT/tests/settingstest.c" -o "$BIN" \
    $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --libs gtk+-2.0) \
    || die "could not build settingstest"

RT="$(mktemp -d)"; CFG="$(mktemp)"
chmod 700 "$RT"
trap 'rm -rf "$RT" "$CFG"' EXIT
cat >"$CFG" <<'EOF'
# Settings published by the shim's XSETTINGS manager.
Net/ThemeName     = TraditionalOk
Gtk/FontName      = DejaVu Sans 11
Net/IconThemeName = mate
EOF

step "running settingstest (shim as the XSETTINGS manager)"
XDG_RUNTIME_DIR="$RT" timeout 12 "$HC" --socket mwset --size 400x300 \
    --timeout 3 --output "$OUT/settings.png" >/dev/null 2>&1 &
hc=$!
sleep 0.3
env XLIB_WAYLAND_XSETTINGS="$CFG" \
    XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY=mwset \
    LD_LIBRARY_PATH="$PREFIX/lib" GSETTINGS_BACKEND=memory \
    XDG_DATA_DIRS="$PREFIX/share:/usr/share" \
    timeout 6 "$BIN" >"$OUT/settings.out" 2>"$OUT/settings.err" || true
wait "$hc" 2>/dev/null || true

cat "$OUT/settings.out"
if grep -q 'SETTINGS:theme=TraditionalOk' "$OUT/settings.out" \
   && grep -q 'SETTINGS:font=DejaVu Sans 11' "$OUT/settings.out" \
   && grep -q 'SETTINGS:icon=mate' "$OUT/settings.out"; then
    log "GTK2 read theme/font/icon from the shim's XSETTINGS"
else
    warn "GTK2 did not read the configured settings:"
    tail -20 "$OUT/settings.err" >&2
    exit 1
fi
