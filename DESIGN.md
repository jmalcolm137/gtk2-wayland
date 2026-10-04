# GTK+ 2 on Wayland — Design Document

**Status:** draft / living document
**Target:** Build and run stock, unmodified **GTK+ 2.24.33** on Wayland through
[`xlib-wayland`](https://github.com/jmalcolm137/xlib-wayland), then the
**MATE 1.10** desktop and **GIMP 2.10**.

---

## 1. Summary

"GTK on Wayland" normally means GTK's own Wayland backend (`GDK_BACKEND=wayland`
in GTK 3/4). GTK+ 2 predates that backend: every GTK2 release, including the
last one (2.24.33, 2020), renders and takes input exclusively through **GDK's
X11 backend**, i.e. through Xlib.

That is the same situation the Motif stack was in, and it is solved the same
way. Xlib is the *only* platform-specific layer in the stack; its handles
(`Display *`, `Window`, `GC`, `XImage`, `Picture`, …) are opaque. If we provide
a binary-compatible `libX11.so.6` whose implementation speaks Wayland instead
of the X11 wire protocol, then GTK2, its GDK X11 backend, and the whole
library stack beneath it compile and run **unmodified**.

> **This project is: build stock GTK+ 2 against the `xlib-wayland` shim, and
> prove it with GTK2's own test suite running in a nested labwc session.**

We do **not** patch GTK2. We do **not** fork the shim here. Every shim
accommodation is made in `xlib-wayland`, pushed there, and consumed here by
revision ([`versions.lock`](../versions.lock)).

### 1.1 Goals

* **G1** — `libgtk-x11-2.0` / `libgdk-x11-2.0` build from unmodified GTK+ 2.24.33
  against the shim.
* **G2** — a GTK2 window opens, draws (including antialiased text and alpha) and
  takes keyboard/pointer input under the shim, natively on Wayland.
* **G3** — GTK2's GTest suite runs under `gtester` inside nested **labwc**.
* **G4** — MATE 1.10 applications build unmodified against the same stack and
  run in labwc.
* **G5** — GIMP 2.10 builds unmodified and runs in labwc.
* **G6** — no root required; deterministic, re-runnable, headless-capable.

### 1.2 Non-goals

* A GTK2 *Wayland backend*. We deliberately keep the X11 backend and put the
  Wayland translation underneath GDK, where the shim already lives.
* Porting GTK2 to GTK3 or to `gtk-backend-wayland`.
* Fixing the inherent limits of an **in-process** Xlib (§2.3): cross-process X
  IPC (XSMP, inter-client DnD, selection watching of *other* processes) is not
  available on the shim.
* Xwayland in the test session. labwc's XWayland is disabled.

---

## 2. Why this works

### 2.1 The layer that changes

```
        GTK+ 2 application
        ─────────────────────────────────────────────
        libgtk-x11-2.0   (GTK widgets)                 unmodified upstream
        libgdk-x11-2.0   (GDK, X11 backend)            unmodified upstream
        libatk · libpango · libgdk-pixbuf · cairo      unmodified upstream
        ─────────────────────────────────────────────
        libX11  ← xlib-wayland : Xlib ABI, Wayland impl
        libXext · libXrender · libXi · libXfixes …
        libXft  ← xlib-wayland (Xft over the same font path)
        ─────────────────────────────────────────────
        X11 wire protocol   ← replaced by →   Wayland
```

Xlib is the platform layer. GDK calls it; it does not care how `XPutImage` or
`XCopyArea` is implemented. The shim has already proven this boundary by
building and running **libXt, Open Motif, XV and NEdit** unmodified.

### 2.2 How the extension libraries work without a server

GTK2/GDK link several X11 extension libraries — `libXrender`, `libXext`,
`libXi`, `libXfixes`, `libXdamage`, `libXcomposite`, `libXinerama`,
`libXrandr`, `libXcursor`. Those libraries are built against the real Xlib and
drive it through Xlib's **internal** ABI (`_XSend`, `_XGetRequest`, `_XReply`,
`_XRead`, …). They never touch a socket themselves.

`xlib-wayland` installs as `libX11.so.6` and implements that internal ABI
(`src/xlib/xlibint.c`). Extension requests therefore arrive at the shim; it
recognises them by major opcode and either synthesises the reply the library
expects or performs the operation against its own model. This is how the
existing `XInput2` query path (`src/xlib/xi2.c`) and the built-in `XRandR` /
`XShape` implementations already work.

Consequence: **we do not reimplement libXrender etc.** We link the system
libraries (built against real Xlib) but arrange that `libX11.so.6` resolves to
the shim, and we make the intercepted protocol paths *functional* in the shim.
Where a facility can be reported absent and the caller degrades gracefully, we
do that instead.

### 2.3 The pivotal constraint: the shim is in-process

Every process gets its own copy of the library, its own root window, atom table,
property store and window tree. There is no shared server. For GTK2 this is
mostly invisible — a GTK2 application is a single client that owns its own
widgets and input — but it matters for:

* **X selections / clipboard** — in-process only, except as bridged to
  `wl_data_device` for text (the shim already does this).
* **XSettings** — GDK reads settings from a `_XSETTINGS_S*` selection owned by a
  settings daemon. There is no daemon; the shim surfaces defaults.
* **Inter-client DnD** — GDK's XDND targets another process's X window; across
  shim processes this is not visible. Treated as a later milestone.
* **`XSendEvent` to another process** — not possible cross-process.

These limits are inherited, not new; the design treats them as explicit
non-goals for the first milestones.

---

## 3. What GTK2 actually needs

The precise, file-and-line inventory is maintained in
[`docs/GTK2-GAP-ANALYSIS.md`](docs/GTK2-GAP-ANALYSIS.md). The shape of it:

* **Core Xlib** — the window tree, GCs, drawing primitives, `XImage`,
  `XPutImage`/`XGetImage`, colours/colormaps, core fonts, events, input,
  properties/atoms, selections, cursors, regions, Xrm, XIM. Most of this the
  shim already implements for Motif.
* **Render (`XRender*`)** — **the critical path.** Since GTK 2.8, GTK draws
  through **cairo**, and GDK's X11 surfaces are `cairo_xlib_surface_t`s. cairo's
  Xlib backend composits through the **Render** extension. GDK and Pango use
  Render directly too (alpha pixmaps, antialiased text, ARGB visuals,
  `XRenderCreateCursor`, gradients). Without a functional Render, GTK2 cannot
  draw at all.
* **Xft** — GDK/Pango use Xft for font handling. The shim already ships a
  `libXft.so.2` built on its own FreeType/fontconfig/cairo font path, so Xft
  works without Render.
* **XInput2 (`XI*`)** — GDK 2.24 can use XI2 for device enumeration and events.
  This is optional: if XI2 is absent GDK falls back to core input. The shim
  already answers the XI2 query path. A first milestone may run with XInput
  disabled at build time.
* **XFixes** — cursor naming (`XFixesSetCursorName`), selection notifications
  (`XFixesSelectSelectionInput`), region copy.
* **XSync** — counters used by GDK for frame timing / `gdk_window_thaw`.
* **Xinerama / XRandR** — monitor enumeration. The shim already reports one
  output through XRandR and can report Xinerama as absent → single screen.
* **XShape / XKB / Xcursor / XDamage / XComposite** — small surfaces; likely
  reported absent or implemented minimally.

### 3.3 Render as the centre of gravity

Render pictures are the natural fit for the shim's model: a `Picture` on a
`Drawable` is essentially "a cairo surface with a format, transform, filter,
clip and repeat". The shim already rasterises through cairo
(`src/raster/raster.h`). The implementation route is therefore:

1. Intercept the Render major opcode in `_XGetRequest`/`_XReply`.
2. Map `XRenderCreatePicture` / `XRenderFreePicture` to a picture object
   wrapping a drawable or an in-memory pixmap.
3. Implement `XRenderComposite`, `XRenderFillRectangle(s)`, solid/font/glyph
   pictures, filters (nearest/bilinear), repeat and the transform with cairo's
   operators against the existing `mw_raster_*` interface.
4. `XRenderQueryExtension` / `XRenderQueryVersion` / `XRenderFindVisualFormat`
   report a version and a format set that cairo accepts (ARGB32, RGB24,
   A8, A1).

This is the largest single piece of new shim code and is tracked as
`xlib-wayland` milestone work.

**Status (implemented, default-on):** `xlib-wayland` implements the Render
extension (`src/xlib/render.c`) — queries and the format/visual list, pictures
and clip, `Composite`/`FillRectangles`, solid and gradient sources, glyph sets
and `CompositeGlyphs`, transforms/filters and traps — and provides the Xlib
output buffer and `resource_alloc` that libXrender requires. Getting the
direct-format encoding and glyph-run advance semantics right (plus dispatching
buffered requests before a drawable is freed or core-drawn) made text render
pixel-correctly, so Render is advertised by default; `MW_RENDER=0` opts back into
cairo's core-protocol fallback. See
[`docs/RENDER-STATUS.md`](docs/RENDER-STATUS.md).

### 3.4 The supporting stack must be a single, common era

Building GTK+ 2.24.33 (December 2020) against a much newer host GLib is not
neutral. It caused a real segfault: `gtk_list_store_iter_is_valid` hands a
stale iterator to GLib's `GSequence`, and with GLib 2.88 the freed memory is
dereferenced rather than benignly rejected. gdk-pixbuf property defaults drift
too. The host's GLib is simply too new.

One stack has to serve GTK+ 2.24.33, MATE 1.10 and GIMP 2.10, and MATE 1.10 is
the most demanding constraint: it defines compatibility functions (e.g.
`g_strv_equal`) that GLib only *declared* from 2.60, so a 2.60+ stack collides
with it. Pango 1.48 in turn requires GLib ≥ 2.62. The common denominator is the
**MATE 1.10-era stack** (c. 2016):

`scripts/build-deps.sh` builds **GLib 2.48.2, ATK 2.18.0, Pango 1.38.1 (with
Xft), gdk-pixbuf 2.34.0** — into `$GTK2_PREFIX`. GTK2 and GIMP only set lower
bounds and build against it happily. cairo, fontconfig, FreeType, HarfBuzz and
fribidi come from the host: they are ABI-stable across the window and do not
carry GLib, so the process ends up with a single GLib. With this pinned,
`liststore` passes.

The compositor is the one process that must *not* use the prefix: labwc is
built against the host GLib and would break if the prefix's GLib shadowed it.
The harness therefore gives labwc only its own library path and lets the test
runner set the prefix path for the GTK2 clients it spawns.

### 3.5 XKB

GDK uses XKB for keyboard handling, and it does so hard: if `XkbGetMap` returns
NULL it calls `g_error("Failed to get keymap")`, and with a descriptor whose
`map` is NULL it dereferences `xkb->map->key_sym_map[...]` and crashes on the
first key event. The shim reports XKB present (real xkbcommon keycodes and
keysyms; setxkbmap and xterm depend on it), so `XkbGetMap` must return a
**valid** description, not an empty one.

The shim now builds a genuine client map from the compositor's xkbcommon
keymap: `key_sym_map`, the flattened `syms` array, one key type, and zeroed
modifier maps. A subtlety that cost a crash of its own: the per-key arrays must
span the full `0..255` keycode range that `XDisplayKeycodes()` advertises, not
just up to the keymap's maximum, because GDK's keyval search iterates to the
advertised maximum and would otherwise read past the end.

### 3.6 Xft

GTK2 does not link Xft; Pango's modern renderer is pangocairo. The shim's
`libXft.so.2` exists for other Xft clients and draws on the shim's own
FreeType/fontconfig/cairo path rather than via Render. Its **draw-level** glyph
entry points (`XftGlyphExtents`, `XftDrawGlyphs`, `XftDrawGlyphSpec`,
`XftDrawGlyphFontSpec`, `XftDrawCharFontSpec`) are implemented there. The
**Render-level** ones (`XftGlyphSpecRender`, `XftGlyphFontSpecRender`,
`XftCharSpecRender`) take Render `Picture`s and cannot be implemented without a
Render extension; a stub would silently draw nothing. Pango's legacy Xft
backend (`pangoxft`) is therefore left disabled (`-Dxft=disabled`); it needs
the Render work of §3.3, and nothing in the GTK2/MATE/GIMP stack uses it.

---

## 4. Keeping GTK2 pristine

The GTK+ 2.24.33 tarball is unpacked under `$GTK2_CACHE` and built
**out-of-tree** under `$GTK2_PREFIX/build`. The source is never patched. The
build only supplies:

* `PKG_CONFIG_PATH` so `x11`/`xft` resolve to the shim,
* `CPPFLAGS`/`LDFLAGS` pointing at the prefix,
* `--with-gdktarget=x11` and configure switches that select supported
  fallbacks (e.g. XInput) rather than altering source.

Any needed change that cannot be expressed as configuration is, by rule, a
**shim change** in `xlib-wayland`.

---

## 5. Test harness: GTK2's suite under gtester in nested labwc

```
host Wayland session (KWin / sway / …)
   └─ labwc                      WLR_BACKENDS=wayland, XWayland OFF
        └─ gtester <test binaries>
             WAYLAND_DISPLAY = labwc's nested socket
```

* **labwc** is staged from distro packages into `$LABWC_PREFIX` with no root
  (`scripts/setup-labwc.sh`); its `-S '<command>'` option runs the test command
  and terminates when it finishes, so the compositor's lifetime is exactly the
  test run.
* **gtester** — GTK+ 2.24's `tests/Makefile.am` drives GTest binaries with
  `gtester` and formats results with `gtester-report`. Modern GLib no longer
  ships `gtester`; `scripts/gtester` is a small MIT-licensed driver that
  implements the subset of the `gtester` command line GTK2's suite uses and can
  emit the XML log that `gtester-report` consumes. If the host provides a real
  `gtester`, it is used instead.
* The harness asserts on the GTest exit status and on the parsed per-binary
  results, and captures the compositor log on failure.

---

## 6. Milestones

| M | Scope | Exit criterion |
|---|---|---|
| **M0** | repo, docs, pins, nested-labwc harness | nested labwc starts under the host session; `scripts/*` run |
| **M1** | GTK2 configures + links against the shim | `libgtk-x11-2.0`/`libgdk-x11-2.0` built; `nm` shows no unresolved X |
| **M2** | Render implemented in the shim; a window draws | a GTK2 test binary opens a toplevel and paints under labwc |
| **M3** | GTK2 GTest suite green under `gtester` | `scripts/run-tests-labwc.sh` passes |
| **M4** | MATE 1.10 | each MATE app builds unmodified and runs in labwc |
| **M5** | GIMP 2.10 | GIMP builds unmodified and runs in labwc |

---

## 7. MATE 1.10 and GIMP 2.10

Both are ordinary GTK2 clients, so once M2/M3 hold they should reduce to
*more of the same* — but they stress areas a synthetic test suite does not:

* **MATE 1.10** — `libmate-desktop`, `mate-panel`, `caja`, `pluma`, `mate-terminal`,
  `marco`, etc.; many processes, XSettings, DnD, panel struts, session
  management. Because the shim is in-process, cross-process features degrade;
  MATE apps must still start, draw and respond.
* **GIMP 2.10** — heavy `XImage`/`XPutImage` use, XDND, colour management,
  multiple windows, and its own GEGL/GTK2 plug-in split. A good end-to-end
  stress test of the drawing and input paths.

The plan is to add them incrementally to the same harness: one application at a
time, each a GTK2 client under nested labwc.

---

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Render is large and subtle | GTK2 draws nothing | make it M2's sole focus; drive it with cairo-xlib conformance before GTK2 |
| Extension libraries bind to the *system* libX11 | two Xlibs, wrong one wins | force the shim first (`LD_LIBRARY_PATH`/rpath); verify with `ldd` and `LD_DEBUG=libs` |
| GLib no longer ships `gtester` | test suite cannot run as upstream intends | ship an MIT `gtester` compatible driver; use a real one if present |
| GTK2 requires XSettings daemon | theme/font settings wrong | shim surfaces defaults; settings can be seeded via properties/resources |
| In-process Xlib breaks cross-process features | DnD/XSMP/session gaps | documented non-goal for early milestones; Wayland bridges later |
| `--with-xinput` pulls in XI2 device classes | build/run breakage | start with XInput disabled; enable once XI2 is functional |
| labwc package depends on exact wlroots minor | nested session won't start | pin and verify; fall back to a source build of labwc |
| Scope is enormous | never "done" | milestone-gated; GTK2 test suite before whole applications |

---

## 9. Appendix — reference

* **Shim:** [`xlib-wayland`](https://github.com/jmalcolm137/xlib-wayland) —
  README and DESIGN describe the Xlib model, the Wayland backend, and the
  Xt/Motif/XV/NEdit evidence.
* **Upstream:** GTK+ 2.24.33 (`download.gnome.org`), cairo, Pango, ATK,
  gdk-pixbuf, Xft, and the X11 extension libraries.
* **Compositor:** labwc (wlroots-based stacking compositor).
* **Harness:** `gtester` (GTest) — reimplemented under `scripts/gtester`.
