#!/usr/bin/env bash
# run-app.sh — run a built MATE/GTK2 application inside nested labwc.
#
# The application must never see XWayland: labwc was built with
# -Dxwayland=disabled and we unset DISPLAY.  The compositor needs the host's
# GLib, while the application needs the prefix's era stack, so each gets its own
# library path (the app through a generated runner, labwc through its own env).
#
# Usage: scripts/run-app.sh [--capture PNG] APP [args...]
#   --capture PNG   run under the shim's headless compositor instead and save a
#                   frame (useful for headless verification)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

CAPTURE=""
if [ "${1:-}" = "--capture" ]; then CAPTURE="$2"; shift 2; fi
APP="${1:?usage: run-app.sh [--capture PNG] APP [args...]}"; shift || true

BIN="$GTK2_PREFIX/bin/$APP"
[ -x "$BIN" ] || die "no such application: $BIN"

OUT="$GTK2_ROOT/tests/out"
mkdir -p "$OUT"
RUNNER="$OUT/run-$APP.sh"

# Application environment, applied by the runner (not by the compositor).
{
    printf '#!/bin/sh\n'
    printf 'export LD_LIBRARY_PATH=%q:%q${LD_LIBRARY_PATH:+:"$LD_LIBRARY_PATH"}\n' \
        "$GTK2_PREFIX/lib" "$LABWC_PREFIX/usr/lib"
    printf 'export PATH=%q:"$PATH"\n' "$GTK2_PREFIX/bin"
    printf 'export GSETTINGS_BACKEND="${GSETTINGS_BACKEND:-memory}"\n'
    printf 'export XDG_DATA_DIRS=%q:/usr/share${XDG_DATA_DIRS:+:"$XDG_DATA_DIRS"}\n' "$GTK2_PREFIX/share"
    printf 'export XDG_CONFIG_DIRS=%q:/etc/xdg${XDG_CONFIG_DIRS:+:"$XDG_CONFIG_DIRS"}\n' "$GTK2_PREFIX/etc/xdg"
    printf 'exec %q' "$BIN"
    for a in "$@"; do printf ' %q' "$a"; done
    printf ' 2>%q\n' "$OUT/$APP.err"
} >"$RUNNER"
chmod +x "$RUNNER"

if [ -n "$CAPTURE" ]; then
    # Headless compositor: no host session required.
    RT="/tmp/gtk2-wayland-hc"; rm -rf "$RT"; mkdir -p "$RT"; chmod 700 "$RT"
    step "Running $APP under the headless compositor"
    XDG_RUNTIME_DIR="$RT" timeout 30 "$GTK2_PREFIX/build/xlib-wayland/headless-compositor" \
        --socket mwapp --size 1024x768 --timeout "${APP_TIMEOUT:-5}" --output "$CAPTURE" \
        >"$OUT/$APP.ready" 2>"$OUT/$APP.hc.log" &
    HC=$!
    for _ in $(seq 1 100); do grep -q READY "$OUT/$APP.ready" 2>/dev/null && break; sleep 0.05; done
    XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY=mwapp timeout 25 "$RUNNER" >/dev/null 2>&1 || true
    wait "$HC" 2>/dev/null || true
    [ -f "$CAPTURE" ] && log "captured $CAPTURE" || warn "no frame captured"
    exit 0
fi

[ -n "${XDG_RUNTIME_DIR:-}" ] || die "nested labwc needs a parent Wayland session"
: "${WAYLAND_DISPLAY:=wayland-0}"
[ -x "$LABWC_PREFIX/usr/bin/labwc" ] || die "no nested labwc (run scripts/setup-labwc.sh)"

step "Running $APP in nested labwc"
set +e
env -u DISPLAY \
    WLR_BACKENDS=wayland WLR_RENDERER_ALLOW_SOFTWARE=1 \
    LD_LIBRARY_PATH="$LABWC_PREFIX/usr/lib" \
    timeout "${APP_TIMEOUT:-15}" \
    "$LABWC_PREFIX/usr/bin/labwc" -C "$LABWC_PREFIX/config" -S "$RUNNER" \
    >"$OUT/$APP.labwc.log" 2>&1
RC=$?
set -e
[ -s "$OUT/$APP.err" ] && { echo "--- $APP stderr ---" >&2; tail -20 "$OUT/$APP.err" >&2; }
log "$APP exited $RC"
