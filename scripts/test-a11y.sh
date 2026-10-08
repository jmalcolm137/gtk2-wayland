#!/usr/bin/env bash
# test-a11y.sh — GTK2's accessible tree exposed over AT-SPI, end to end.
#
# A GTK2 app (GAIL + the atk-bridge module) publishes its accessibility tree on
# the session's accessibility bus; an AT-SPI client walks the desktop and finds
# a widget in it.  Under Wayland the *input* side of a11y is the compositor's,
# so only the tree is exercised.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

A11Y_PREFIX="${A11Y_PREFIX:-$GTK2_PREFIX/a11y}"
HC="$GTK2_PREFIX/build/xlib-wayland/headless-compositor"
[ -x "$HC" ] || die "headless compositor not built (run scripts/build-shim.sh)"
[ -e "$A11Y_PREFIX/lib/libatspi.so.0" ] || die "a11y stack not built (run scripts/build-a11y.sh)"
[ -e "$GTK2_PREFIX/lib/gtk-2.0/modules/libatk-bridge.so" ] || die "GTK2 bridge module missing (run scripts/build-a11y.sh)"
have dbus-run-session || die "dbus-run-session not found"

export PKG_CONFIG_PATH="$A11Y_PREFIX/lib/pkgconfig:$GTK2_PREFIX/lib/pkgconfig:$GTK2_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
pkg-config --exists gtk+-2.0 atspi-2 || die "gtk+-2.0/atspi-2 not found in the prefixes"

OUT="$GTK2_ROOT/tests/out"
mkdir -p "$OUT"
APP="$OUT/a11y_app"
QUERY="$OUT/a11y_query"

step "building the a11y test programs"
# shellcheck disable=SC2046
gcc -O0 $(pkg-config --cflags gtk+-2.0) "$GTK2_ROOT/tests/a11y_app.c" -o "$APP" \
    $(pkg-config --libs gtk+-2.0) || die "could not build a11y_app"
# shellcheck disable=SC2046
gcc -O0 $(pkg-config --cflags atspi-2) "$GTK2_ROOT/tests/a11y_query.c" -o "$QUERY" \
    $(pkg-config --libs atspi-2 gobject-2.0) || die "could not build a11y_query"

step "running the GTK2 app + AT-SPI query in a private DBus session"
RT="$(mktemp -d)"
trap 'rm -rf "$RT"' EXIT

# XDG_DATA_DIRS must be set for dbus-daemon so org.a11y.Bus activates *our*
# launcher (matching libatspi), not the host's (which wants systemd --user).
XDG_DATA_DIRS="$A11Y_PREFIX/share:$GTK2_PREFIX/share:/usr/share" \
dbus-run-session -- bash -c "
  XDG_RUNTIME_DIR='$RT' '$HC' --socket mwa11y --size 300x200 --timeout 12 \
      --output '$OUT/a11y.png' >/dev/null 2>&1 &
  hc=\$!
  sleep 0.4
  GTK_MODULES=gail:atk-bridge GSETTINGS_BACKEND=memory \
  XDG_DATA_DIRS='$A11Y_PREFIX/share:$GTK2_PREFIX/share:/usr/share' \
  LD_LIBRARY_PATH='$A11Y_PREFIX/lib:$GTK2_PREFIX/lib' \
  XDG_RUNTIME_DIR='$RT' WAYLAND_DISPLAY=mwa11y \
      timeout 8 '$APP' >'$OUT/a11y_app.err' 2>&1 &
  app=\$!
  sleep 2.5
  LD_LIBRARY_PATH='$A11Y_PREFIX/lib:$GTK2_PREFIX/lib' \
      timeout 8 '$QUERY' >'$OUT/a11y_query.out' 2>&1
  qrc=\$?
  kill \$app 2>/dev/null || true
  wait \$hc 2>/dev/null || true
  exit \$qrc
" || true

cat "$OUT/a11y_query.out"
if grep -q 'A11Y:RESULT found=1' "$OUT/a11y_query.out"; then
    log "GTK2 published its accessible tree over AT-SPI"
else
    warn "the AT-SPI query found nothing; diagnostics:"
    tail -20 "$OUT/a11y_app.err" >&2
    exit 1
fi
