#!/usr/bin/env bash
# test-print.sh — GtkPrint works, and the CUPS backend is built.
#
# GTK2 renders print jobs through cairo and its backends do the I/O: `file`
# (Export to PDF), `lpr`, and now `cups` (IPP to a CUPS server).  Export needs
# no server, so it is what runs here; the CUPS backend is checked as a built
# module that links libcups (a real print test needs a CUPS server).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

PREFIX="$GTK2_PREFIX"
HC="$PREFIX/build/xlib-wayland/headless-compositor"
[ -x "$HC" ] || die "headless compositor not built (run scripts/build-shim.sh)"
[ -e "$PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"

OUT="$GTK2_ROOT/tests/out"
mkdir -p "$OUT"
BIN="$OUT/printtest"
PDF="$OUT/printtest.pdf"
rm -f "$PDF"

# --- the CUPS backend must exist and link libcups ----------------------------
CUPS_BACKEND="$PREFIX/lib/gtk-2.0/2.10.0/printbackends/libprintbackend-cups.so"
[ -e "$CUPS_BACKEND" ] || die "CUPS print backend not built (rebuild GTK2 with --enable-cups)"
ldd "$CUPS_BACKEND" | grep -q 'libcups' || die "CUPS backend does not link libcups"
log "CUPS backend present: $(basename "$CUPS_BACKEND") -> $(ldd "$CUPS_BACKEND" | awk '/libcups/{print $1}')"

step "building printtest"
# shellcheck disable=SC2046
gcc -O0 $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --cflags gtk+-2.0) \
    "$GTK2_ROOT/tests/printtest.c" -o "$BIN" \
    $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --libs gtk+-2.0) \
    || die "could not build printtest"

step "exporting a job to PDF under the headless compositor"
RT="$(mktemp -d)"
trap 'rm -rf "$RT"' EXIT

XDG_RUNTIME_DIR="$RT" timeout 12 "$HC" --socket mwprint --size 400x300 \
    --timeout 6 --output "$OUT/printtest.png" >/dev/null 2>&1 &
hc=$!
sleep 0.3
PRINT_OUT="$PDF" \
    XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY=mwprint \
    LD_LIBRARY_PATH="$PREFIX/lib" GSETTINGS_BACKEND=memory \
    XDG_DATA_DIRS="$PREFIX/share:/usr/share" \
    timeout 10 "$BIN" >"$OUT/printtest.out" 2>"$OUT/printtest.err" || true
wait "$hc" 2>/dev/null || true

cat "$OUT/printtest.out"
if grep -q 'PRINT:result=.*exists=1' "$OUT/printtest.out" && [ -s "$PDF" ]; then
    log "GtkPrint exported a job ($(stat -c%s "$PDF") bytes)"
else
    warn "print export failed; diagnostics:"
    tail -20 "$OUT/printtest.err" >&2
    exit 1
fi
