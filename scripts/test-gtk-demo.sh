#!/usr/bin/env bash
# test-gtk-demo.sh — render every gtk-demo demo (and the gtk-demo browser
# itself) under the headless compositor, on the shim's Render path and on
# cairo's core-protocol fallback, and compare the two.
#
# The core fallback is cairo's own, long-standing path; on a static demo the
# Render path must match it.  Demos that are genuinely animated are detected by
# capturing the fallback twice: if the fallback itself differs between frames,
# the demo is skipped rather than reported.
#
# Usage: scripts/test-gtk-demo.sh [--jobs N] [--threshold PCT] [--keep]
set -euo pipefail
. "$(dirname "$0")/lib.sh"
load_versions

JOBS=6
THRESH=4.0
KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --jobs)      JOBS="$2"; shift 2;;
        --threshold) THRESH="$2"; shift 2;;
        --keep)      KEEP=1; shift;;
        *) die "unknown option: $1";;
    esac
done

PREFIX="$GTK2_PREFIX"
GDEMO_BUILD="$PREFIX/build/gtk+-2.24.33/demos/gtk-demo"
OUT="$GTK2_ROOT/tests/out/gtk-demo"
WALKER="$PREFIX/build/gtk-demo-walker"

[ -e "$PREFIX/lib/libX11.so.6" ] || die "shim not installed (run scripts/build-shim.sh)"
[ -d "$GDEMO_BUILD" ] || die "gtk-demo objects not found (build GTK2 first)"

# ------------------------------------------------------------- build walker -
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
    pkg-config --exists gtk+-2.0 || die "gtk+-2.0 not found in $PREFIX"
OBJS=$(ls "$GDEMO_BUILD"/*.o | grep -v '/main.o$' | tr '\n' ' ')
# shellcheck disable=SC2086
gcc -O0 -I"$GTK2_CACHE/src/gtk+-2.24.33/demos/gtk-demo" \
    -DDEMOCODEDIR="\"$PREFIX/share/gtk-2.0/demo\"" \
    $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --cflags gtk+-2.0) \
    "$GTK2_ROOT/tests/gtk-demo-walker.c" $OBJS \
    -o "$WALKER" \
    $(PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --libs gtk+-2.0) -lm \
    || die "could not build the gtk-demo walker"

rm -rf "$OUT"; mkdir -p "$OUT"

# A runner: one demo, one render path, one frame.
run_one() { # index path [timeout]
    local i="$1" path="$2" tout="${3:-3}" rt
    rt="$(mktemp -d "$OUT/rt.XXXXXX")"
    XDG_RUNTIME_DIR="$rt" timeout 12 "$PREFIX/build/xlib-wayland/headless-compositor" \
        --socket "gd$i$path" --size 1300x950 --timeout "$tout" \
        --output "$OUT/d$i-$path.png" >/dev/null 2>&1 &
    local hc=$!
    sleep 0.3
    env "MW_RENDER=$([ "$path" = rn ] && echo 1 || echo 0)" \
        XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY="gd$i$path" \
        LD_LIBRARY_PATH="$PREFIX/lib" GSETTINGS_BACKEND=memory \
        XDG_DATA_DIRS="$PREFIX/share:/usr/share" \
        timeout 6 "$WALKER" --index "$i" --ms 20000 \
        >"$OUT/d$i-$path.out" 2>"$OUT/d$i-$path.err" || true
    wait "$hc" 2>/dev/null || true
    rm -rf "$rt"
}
export -f run_one
export PREFIX OUT WALKER

mapfile -t TITLES < <("$WALKER" --list 2>/dev/null)
N=${#TITLES[@]}
step "gtk-demo: $N demos, render vs fallback"

# Two frames on each path at different times.  A demo is animated if either
# path changes between its own two frames; the render/fallback pair is then not
# comparable and the demo is reported as skipped rather than failed.
args=()
for i in $(seq 0 $((N-1))); do
    args+=("$i" rn1 3 "$i" rn2 4 "$i" fb1 3 "$i" fb2 4)
done
printf '%s\n' "${args[@]}" | xargs -P "$JOBS" -n 3 bash -c 'run_one "$0" "$1" "$2"'

# ------------------------------------------------- gtk-demo browser itself --
# The browser is a GtkTreeView + text view; capture it on both paths too.
browser() { # path
    local path="$1" rt
    rt="$(mktemp -d "$OUT/rt.XXXXXX")"
    XDG_RUNTIME_DIR="$rt" timeout 10 "$PREFIX/build/xlib-wayland/headless-compositor" \
        --socket "gdb$path" --size 900x650 --timeout 4 \
        --output "$OUT/browser-$path.png" >/dev/null 2>&1 &
    local hc=$!
    sleep 0.3
    env "MW_RENDER=$([ "$path" = rn ] && echo 1 || echo 0)" \
        XDG_RUNTIME_DIR="$rt" WAYLAND_DISPLAY="gdb$path" \
        LD_LIBRARY_PATH="$PREFIX/lib" GSETTINGS_BACKEND=memory \
        XDG_DATA_DIRS="$PREFIX/share:/usr/share" SMOKE_MS=20000 \
        timeout 8 "$PREFIX/bin/gtk-demo" >"$OUT/browser-$path.out" 2>"$OUT/browser-$path.err" || true
    wait "$hc" 2>/dev/null || true
    rm -rf "$rt"
}
browser rn
browser fb

# ---------------------------------------------------------------- report ----
python3 - "$OUT" "$N" "$THRESH" "${TITLES[@]}" <<'PY'
import sys, os
from PIL import Image, ImageChops
out, N, thresh = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
titles = sys.argv[4:]

def load(p):
    try: return Image.open(p).convert("RGB")
    except Exception: return None

def diffpct(a, b):
    if a is None or b is None: return None
    if a.size != b.size: return 100.0
    d = ImageChops.difference(a, b)
    n = sum(1 for p in list(d.getdata()) if p != (0, 0, 0))
    return 100.0 * n / (a.size[0] * a.size[1])

fails = []
print(f"{'#':>2}  {'result':<26} demo")
for i in range(N):
    rn = load(f"{out}/d{i}-rn1.png")
    rn2 = load(f"{out}/d{i}-rn2.png")
    f1 = load(f"{out}/d{i}-fb1.png")
    f2 = load(f"{out}/d{i}-fb2.png")
    title = titles[i] if i < len(titles) else "?"
    cands = [x for x in (diffpct(rn, rn2), diffpct(f1, f2)) if x is not None]
    anim = max(cands) if cands else None
    if rn is None or f1 is None:
        status = "NO FRAME"; fails.append((i, title, status))
    elif anim is not None and anim > 1.5:
        status = f"animated (skip, {anim:.1f}%)"
    else:
        d = diffpct(rn, f1)
        # blank-on-render while fallback has content is always a failure
        rcol = len(rn.getcolors(1 << 24)); fcol = len(f1.getcolors(1 << 24))
        if d > thresh or (rcol <= 1 and fcol > 1):
            status = f"DIFF {d:.1f}% ({fcol}->{rcol} col)"
            fails.append((i, title, status))
        else:
            status = f"ok {d:.2f}%"
    print(f"{i:2d}  {status:<26} {title}")

# browser
br = diffpct(load(f"{out}/browser-rn.png"), load(f"{out}/browser-fb.png"))
print()
if br is None:
    print("gtk-demo browser: NO FRAME"); fails.append((-1, "gtk-demo browser", "NO FRAME"))
elif br > thresh:
    print(f"gtk-demo browser: DIFF {br:.2f}%"); fails.append((-1, "gtk-demo browser", f"DIFF {br:.2f}%"))
else:
    print(f"gtk-demo browser: ok {br:.2f}%")

print()
if fails:
    print(f"{len(fails)} demo(s) differ from the core fallback:")
    for i, t, s in fails: print(f"  d{i:02d} {t}: {s}")
    sys.exit(1)
print("all static demos match the core fallback")
PY
