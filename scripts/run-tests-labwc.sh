#!/usr/bin/env bash
# run-tests-labwc.sh — run GTK2's GTest suite under gtester in nested labwc.
#
# GTK2 ships its own suite under gtk/tests/, normally driven by `gtester` under
# Xvfb (see Makefile.decl).  We run the same binaries with the same tool, but
# inside a nested labwc session, so the whole GDK -> libX11 shim -> Wayland path
# is exercised.  XWayland is disabled in our labwc, so DISPLAY is unset and the
# clients can only reach the shim.
#
# Usage: scripts/run-tests-labwc.sh [TEST...]
#   With no arguments, runs the standard gtk/tests programs.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

# gtester / gtester-report: the prefix's GLib 2.66 ships them; newer host GLib
# may not, so fall back to the staged glib2-devel tools if needed.
use_prefix
if HOSTTOOLS="$(stage_glib_tools)" && [ -n "$HOSTTOOLS" ]; then
    export PATH="$HOSTTOOLS:$PATH"
fi
have gtester || die "gtester not found (build the dependency stack or stage glib2-devel)"

[ -d "$GTK2_SRC" ] || die "no GTK2 source (run scripts/fetch-sources.sh)"
[ -x "$LABWC_PREFIX/usr/bin/labwc" ] || die "no nested labwc (run scripts/setup-labwc.sh)"
[ -e "$GTK2_PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"
[ -d "$GTK2_BUILD" ] || die "GTK2 not built (run scripts/build-gtk2.sh)"

if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    :
fi
[ -n "${XDG_RUNTIME_DIR:-}" ] || die "nested labwc needs a parent Wayland session (XDG_RUNTIME_DIR unset)"
: "${WAYLAND_DISPLAY:=wayland-0}"

TESTDIR="$GTK2_BUILD/gtk/tests"

# --- the programs to run -----------------------------------------------------
DEFAULT_PROGS=(testing liststore treestore treeview treeview-scrolling
               recentmanager floating object builder defaultvalue textbuffer
               filtermodel expander action)
if [ "$#" -gt 0 ]; then PROGS=("$@"); else PROGS=("${DEFAULT_PROGS[@]}"); fi

# --- build them if needed ----------------------------------------------------
missing=0
for p in "${PROGS[@]}"; do [ -x "$TESTDIR/$p" ] || missing=1; done
if [ "$missing" = 1 ]; then
    step "Building GTK2 test programs"
    ( cd "$GTK2_BUILD" && make -C gtk/tests ) >"$GTK2_PREFIX/gtk-tests-build.log" 2>&1 \
        || { tail -25 "$GTK2_PREFIX/gtk-tests-build.log"; die "could not build test programs"; }
fi

OUT="$GTK2_ROOT/tests/out"
mkdir -p "$OUT"
GTLOG="$OUT/gtester.log"
RUNNER="$OUT/runner.sh"

# The runner labwc executes on startup.  Keep it a file: labwc -S runs a shell
# command string and quoting a 14-program gtester invocation inline is fragile.
#
# The runner puts the prefix (GTK2-era GLib/Pango/gdk-pixbuf + the shim) on its
# library path itself.  labwc must not inherit it: the compositor is built
# against the host's GLib 2.88 and would break if the prefix's GLib 2.66
# shadowed it.  The two live in different processes; the env is set per process.
{
    printf '#!/bin/sh\n'
    printf 'export PATH=%q:"$PATH"\n' "$GTK2_PREFIX/bin"
    printf 'export LD_LIBRARY_PATH=%q:%q${LD_LIBRARY_PATH:+:"$LD_LIBRARY_PATH"}\n' \
        "$GTK2_PREFIX/lib" "$LABWC_PREFIX/usr/lib"
    printf 'cd %q || exit 99\n' "$TESTDIR"
    printf 'gtester --keep-going --verbose'
    for p in "${PROGS[@]}"; do printf ' %q' "$p"; done
    printf ' >%q 2>&1\n' "$GTLOG"
    printf 'rc=$?\n'
    printf 'echo "gtester rc=$rc"\n'
    printf 'exit $rc\n'
} >"$RUNNER"
chmod +x "$RUNNER"

step "Running ${#PROGS[@]} GTK2 test programs under gtester in nested labwc"
dim "runner: $RUNNER"
dim "parent: WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

set +e
env -u DISPLAY \
    WLR_BACKENDS=wayland WLR_RENDERER_ALLOW_SOFTWARE=1 \
    LD_LIBRARY_PATH="$LABWC_PREFIX/usr/lib" \
    PATH="$PATH" \
    timeout "${TEST_TIMEOUT:-900}" \
    "$LABWC_PREFIX/usr/bin/labwc" -C "$LABWC_PREFIX/config" -S "$RUNNER" \
    >"$OUT/labwc.log" 2>&1
RC=$?
set -e

echo
if [ -f "$GTLOG" ]; then
    tail -n 40 "$GTLOG" >&2
    if grep -qE 'FAIL|ERROR' "$GTLOG"; then
        warn "failures reported; full log: $GTLOG"
        exit 1
    fi
fi
if [ "$RC" != 0 ]; then
    warn "labwc/gtester exited $RC; see $OUT/labwc.log"
    exit "$RC"
fi
log "all GTK2 tests passed ($GTLOG)"
