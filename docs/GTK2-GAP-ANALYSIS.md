# GTK+ 2.24.33 — X11/Xlib Requirements Inventory

This is the gap analysis that drives the `xlib-wayland` work for GTK2. It was
produced by auditing the GTK+ 2.24.33 tree (paths relative to the source root,
`gtk+-2.24.33/`). It is the authoritative list of what the shim must provide.

> **Method:** ripgrep over the whole tree for `#include <X11/extensions/...>`,
> `X*()` call sites and configure probes. The shim installs as `libX11.so.6`
> and intercepts extension protocol at Xlib's internal `_XGetRequest`/
> `_XReply` layer, synthesising replies against its own model.

## 0. The one-paragraph version

The X11 backend is selected at **compile time** (`--with-gdktarget=x11`); there
is no `GDK_BACKEND` in GTK2, so the shim must be the linked `libX11`/`libXext`/
`libXrender`. GTK2 **hard-requires** the symbols `XOpenDisplay` (libX11),
`XextFindDisplay` (libXext), `XRenderQueryExtension` (libXrender),
`XShapeCombineMask` (Shape), a valid `xReply` typedef, and fontconfig. It draws
through **cairo-xlib + PangoCairo**, so the **full RENDER protocol must be
emulated**, not merely answered "present". Everything else (XFixes, XSync,
XDamage, XComposite, Xinerama, RandR, XKB, Xcursor, XShm, XInput) is optional
and GTK2 degrades gracefully when it is absent. GTK2 does **not** link Xft
directly.

---

## 1. Extension usage

### 1.1 XRender (RENDER) — HARD BUILD REQUIREMENT
- Build: `configure.ac:1005-1006` aborts if `XRenderQueryExtension` is missing
  (`libXrender` mandatory). `configure.ac:959-963` also lists `xrender` in the
  base X pkg-config set.
- Header: `gdk/x11/gdkdrawable-x11.h:33` includes `<X11/extensions/Xrender.h>`
  unconditionally.
- Runtime probe: `gdk/x11/gdkdrawable-x11.c:264` `XRenderQueryExtension()` in
  `_gdk_x11_have_render()` (`display_x11->have_render`,
  `gdkdisplay-x11.h:81`).
- Functions called directly:
  - `XRenderQueryExtension` `gdkdrawable-x11.c:264`
  - `XRenderFindVisualFormat` `:345`
  - `XRenderCreatePicture` `:351,:1298,:1302,:1393,:1396`
  - `XRenderFreePicture` `:209,:1334,:1336,:1357,:1359`
  - `XRenderSetPictureClipRectangles` `:383`
  - `XRenderChangePicture` `:405`
  - `XRenderFindFormat` `:1014,:1034,:1052,:1064,:1085,:1109`
  - `XRenderComposite` `:1331,:1455`
  - `XRenderQuerySubpixelOrder` `gdk/x11/gdkxftdefaults.c:178`
- **Transitively**: cairo-xlib and PangoCairo drive RENDER for every
  `gdk_cairo_create()` and every glyph draw. This is the bulk of the traffic.

### 1.2 XFixes — optional
- Configure `configure.ac:1209-1216` → `HAVE_XFIXES`.
- Headers guarded: `gdkdisplay-x11.c:50-52`, `gdkcursor-x11.c:36-38`,
  `gdkscreen-x11.c:50-52`, `gdkevents-x11.c:57-59`, `gdkwindow-x11.c:66-68`,
  `gtk/gtksocket-x11.c:44`.
- Runtime `XFixesQueryExtension()` `gdkdisplay-x11.c:239`.
- Functions: `XFixesSelectSelectionInput` `:1295`; `XFixesCreateRegion`
  `gdkevents-x11.c:2192`; `XFixesDestroyRegion` `:2197`; `XFixesChangeCursor`
  `gdkcursor-x11.c:592`; `XFixesChangeSaveSet` `gtk/gtksocket-x11.c:282`.

### 1.3 XSync — optional
- Configure `configure.ac:1062-1065` → `HAVE_XSYNC`.
- Runtime `XSyncQueryExtension`/`XSyncInitialize` `gdkdisplay-x11.c:392-403`.
- Functions: `XSyncValueIsZero`, `XSyncIntToValue`, `XSyncIntsToValue`,
  `XSyncCreateCounter`, `XSyncDestroyCounter`, `XSyncSetCounter`.

### 1.4 XDamage — optional
- Configure `configure.ac:1229-1234` → `HAVE_XDAMAGE`; runtime
  `XDamageQueryExtension()` `gdkdisplay-x11.c:272`.
- Functions: `XDamageCreate`, `XDamageDestroy`, `XDamageSubtract`.

### 1.5 XComposite — optional
- Configure `configure.ac:1220-1225` → `HAVE_XCOMPOSITE`; runtime
  `XCompositeQueryExtension`/`XCompositeQueryVersion` `gdkdisplay-x11.c:254-266`.
- Functions: `XCompositeGetOverlayWindow` `gdkdnd-x11.c:591`;
  `XCompositeReleaseOverlayWindow` `:593`; `XCompositeRedirectWindow`
  `gdkwindow-x11.c:5627`; `XCompositeUnredirectWindow` `:5632`.

### 1.6 XInput (XI1, not XI2) — off by default
- `--with-xinput=no/yes` (`configure.ac:252-253`). Absent = `XINPUT_NONE` and
  `gdkinput-none.c` (`gdk/x11/Makefile.am:62-66`). `yes`/`xfree` = legacy XI1
  (`gdkinput-x11.c` + `gdkinput-xfree.c`), links `-lXi`.
- GTK2 does **not** use XInput2 (`XIQueryVersion`, `XISelectEvents`,
  GenericEvent). We build with `--with-xinput=no`.

### 1.7 Xinerama — optional, default yes
- `configure.ac:1117-1171`; `HAVE_XFREE_XINERAMA` via `pkg-config xinerama` or
  `-lXinerama`. Runtime `XQueryExtension(..., "XINERAMA", ...)`
  `gdkscreen-x11.c:1095`; `XineramaIsActive`/`XineramaQueryScreens` under
  `HAVE_XFREE_XINERAMA` (:972).
- We configure `--disable-xinerama`; the fallback is RandR or single monitor.

### 1.8 XRandR — optional
- `configure.ac:1192-1199` → `HAVE_RANDR` (>=1.2.99) / `HAVE_RANDR15`
  (>=1.5.0). Runtime `XRRQueryExtension`/`XRRQueryVersion`
  `gdkdisplay-x11.c:186-203`.
- Functions: `XRRSelectInput`, `XRRUpdateConfiguration`, `XRRGetMonitors`,
  `XRRFreeMonitors`, `XRRGetScreenResourcesCurrent`, `XRRGetOutputInfo`,
  `XRRFreeOutputInfo`, `XRRGetCrtcInfo`, `XRRFreeCrtcInfo`,
  `XRRFreeScreenResources`, `XRRGetOutputPrimary`.

### 1.9 XShape — required symbol, optional at runtime
- `configure.ac:1055-1056` aborts if `XShapeCombineMask` is missing; header
  included unconditionally (`gdkdisplay-x11.c:54`, `gdkdnd-x11.c:32`,
  `gdkwindow-x11.c:60`).
- Runtime `XShapeQueryExtension`/`XShapeQueryVersion`
  `gdkdisplay-x11.c:289-295`.
- Functions: `XShapeCombineMask`, `XShapeCombineRectangles`,
  `XShapeGetRectangles`, `XShapeSelectInput`.

### 1.10 XKB — optional, default "maybe"
- `--enable-xkb=no/yes/maybe` (`configure.ac:235-238`); maybe enables
  `HAVE_XKB` if `XkbQueryExtension` links. Runtime probe
  `gdkdisplay-x11.c:349-389`.
- Extensive `gdkkeys-x11.c` use (`XkbGetMap`, `XkbGetNames`, `XkbGetState`,
  …). Fallback (`HAVE_XKB` absent) builds the keymap from core
  `XGetKeyboardMapping`/`XGetModifierMapping` (`gdkkeys-x11.c:355-421`).

### 1.11 Xcursor — optional client-side library
- `configure.ac:1203-1207` → `HAVE_XCURSOR`. Not a server extension; uploads
  ARGB cursors through RENDER. Fallback is `XCreateFontCursor`/
  `XCreatePixmapCursor` (`gdkcursor-x11.c:956-1063`).

### 1.12 XShm — optional
- `--enable-shm` default yes; code guarded by local `USE_SHM`
  (`gdkimage-x11.c:32-34`, `gdkdrawable-x11.c:37-39`). Runtime
  `XShmQueryExtension` gate `gdkimage-x11.c:187-191`. Fallback
  `XCreateImage`/`XPutImage`.

### 1.13 XTest / XScreenSaver — NOT USED
No references. GDK test utils synthesise input with `XSendEvent`/`XWarpPointer`.

---

## 2. Core Xlib surface

The complete call inventory is long; the functional groups are:

- **Display/connection**: `XOpenDisplay`, `XCloseDisplay`, `XFlush`, `XSync`,
  `XSynchronize`, `NextRequest`, `XExtendedMaxRequestSize`, `XMaxRequestSize`,
  `XAddConnectionWatch`, `XProcessInternalConnection`, `XSetErrorHandler`,
  `XSetIOErrorHandler`.
- **Windows**: create/map/unmap/destroy, `XConfigureWindow`, move/resize/raise/
  lower, `XReparentWindow`, `XRestackWindows`, `XQueryTree`,
  `XGetGeometry`, `XGetWindowAttributes`, `XChangeWindowAttributes`,
  `XTranslateCoordinates`, background/colormap setters, `X*WM*` hints,
  `XIconifyWindow`, `XWithdrawWindow`, `XReconfigureWMWindow`.
- **Events/input**: `XPending`, `XNextEvent`, `XPeekEvent`, `XPutBackEvent`,
  `XIfEvent`, `XCheckIfEvent`, `XSendEvent`, `XFilterEvent`, selection/input,
  grabs (`XGrabPointer/Keyboard/Key/Server`), `XQueryPointer`, `XWarpPointer`.
- **Drawing/GC**: create/change/free GC, all draw/fill primitives, `XCopyArea`,
  clip setters, `XSetFont`.
- **Images/pixmaps**: `XCreateImage`, `XGetImage`, `XGetSubImage`,
  `XPutImage`, `XGetPixel`, `XPutPixel`, `XCreatePixmap*`, `XFreePixmap`,
  `XListPixmapFormats`.
- **Colour/visual**: `XAllocColor`, `XAllocColorCells`, `XQueryColor(s)`,
  `XStoreColor(s)`, `XCreateColormap`, `XFreeColors`, `XGetVisualInfo`,
  `XListDepths`, `XMatchVisualInfo`.
- **Fonts (legacy GdkFont only)**: `XLoadQueryFont`, `XCreateFontSet`,
  `XTextWidth*`, `XTextExtents*`, `XDrawString*`, `XSetFont` — deprecated and
  not used by cairo/Pango rendering.
- **Atoms/properties/selections**: `XInternAtom(s)`, `XGetAtomName`,
  `XChangeProperty`, `XGetWindowProperty`, `XDeleteProperty`,
  `XSetSelectionOwner`, `XGetSelectionOwner`, `XConvertSelection`.

### 2.1 Internals GTK2 relies on
- `gdk/x11/gdkasync.c:50` includes `<X11/Xlibint.h>` and uses `_XReply`
  (`:461,:731`), `_XRead32` (`:476`) and `_XAsyncHandler` structs
  (`:100,:111,:119,:427,:634`).
- `NextRequest()` serials compared against received events:
  `gdkmain-x11.c:282`, `gdkdisplay-x11.c:451,:637`, `gdkwindow-x11.c:1364,1469`,
  `gdkgeometry-x11.c:120,221`, `gdkselection-x11.c:176`.
- `XAddConnectionWatch`/`XProcessInternalConnection` (`HAVE_X11R6`).
- Error trap depends on `XErrorEvent.error_code`/`serial`.

---

## 3. Font path

- **GTK+ 2.24.33 does not link Xft.** No `HAVE_XFT`/`USE_XFT` anywhere; the
  direct Xft/FreeType/pangoxft dependency was removed before 2.8
  (`ChangeLog.pre-2-8:85`).
- Text goes through **Pango + Cairo**: `gdk/gdkpango.c:22` includes
  `<pango/pangocairo.h>`; `gdkpango.c:168` gets a `cairo_t` from
  `gdk_cairo_create()`; `:247,:252` `pango_cairo_show_glyph_string()`.
- `gdk/x11/gdkxftdefaults.c` is named Xft but only reads `Xft/*` X resources
  with `XGetDefault()` and parses them with **fontconfig**
  (`gdkxftdefaults.c:44,90,111,134,137`); it calls `XRenderQuerySubpixelOrder`
  (`:178`).
- **GDK drawing is cairo-xlib and therefore requires RENDER.** `gdkdrawable-x11.c`
  includes `<cairo-xlib.h>` (`:32`) and creates surfaces with
  `cairo_xlib_surface_create()`/`..._for_bitmap()` (`:1553,:1558`).

---

## 4. Compile-time configuration

| Option | Default | Effect |
|---|---|---|
| `--with-gdktarget=x11` | x11 on Unix | the only backend selector |
| `--enable-shm` | yes | `USE_SHM` |
| `--enable-xkb=no/yes/maybe` | maybe | `HAVE_XKB` |
| `--enable-xinerama` | yes | `HAVE_XFREE_XINERAMA` |
| `--with-xinput=no/yes` | no (absent) | `XINPUT_NONE` vs `XINPUT_XFREE` (XI1) |

Relevant defines: `HAVE_X11R6`, `HAVE_XCONVERTCASE`, `HAVE_XINTERNATOMS`,
`HAVE_XKB`, `HAVE_XSYNC`, `HAVE_XSHM_H`, `HAVE_XFREE_XINERAMA`, `XINPUT_NONE`,
`HAVE_RANDR`, `HAVE_RANDR15`, `HAVE_XCURSOR`, `HAVE_XFIXES`, `HAVE_XCOMPOSITE`,
`HAVE_XDAMAGE`, `NEED_XIPROTO_H_FOR_XREPLY`, `GDK_WINDOWING_X11`. See
`config.h.in` and `configure.ac:1025-1234`.

Hard link requirements (configure aborts without them): `XOpenDisplay`,
`XextFindDisplay`, `XRenderQueryExtension`, `XShapeCombineMask`, a usable
`xReply`, fontconfig.

---

## 5. Test suite

- `tests/` — 65 GUI programs built but **not** in `TESTS`; only
  `autotestkeywords` is (`tests/Makefile.am:95`). Useful smoke tests:
  `testgtk`, `testdnd`, `testcairo`, `testsocket`.
- `gtk/tests/` — the real gtester unit suite, **14 binaries** on Unix
  (`gtk/tests/Makefile.am:25-95`): `testing`, `liststore`, `treestore`,
  `treeview`, `treeview-scrolling`, `recentmanager`, `floating`, `object`,
  `builder`, `defaultvalue`, `textbuffer`, `filtermodel`, `expander`, `action`.
- `gdk/tests/` — empty. `gdk/x11/` — `checksettings`. `gdk/` — `abicheck.sh`,
  `pltcheck.sh`.
- `Makefile.decl:3-4` defines `GTESTER = gtester`,
  `GTESTER_REPORT = gtester-report`; `:13` defines
  `XVFB = Xvfb -ac -noreset -screen 0 800x600x16`; `test-cwd` runs
  `${GTESTER} --verbose ${TEST_PROGS}` under Xvfb; `check-local: test-cwd`.
- `DISPLAY` is what GTK2 uses (`gdkdisplay-x11.c:166`); `GDK_BACKEND` is
  irrelevant. `GTESTER_LOGDIR` controls XML output.

**For the shim, GTK2's own `Makefile.decl` starts Xvfb and sets `DISPLAY`. We
instead run the same `gtester` over `gtk/tests` binaries inside nested labwc,
with `DISPLAY` unset.**

---

## 6. Prioritised shim gap list

**Tier 0 — must be functional for a GTK2 window to open and draw:**
1. Core display/connection + screen/visual/root setup.
2. Window create/map/configure/destroy + input mask.
3. Event loop (`XPending`/`XNextEvent`/`XPeekEvent`/`XIfEvent`/`XSendEvent`) and
   `XSync`/`XFlush`, with correct serials.
4. `NextRequest` accounting; `_XReply`/`_XRead32`/`_XAsyncHandler`.
5. Error-handler semantics and `XErrorEvent` codes (error trap).
6. **Full RENDER protocol**: QueryExtension/Version, QueryPictFormats,
   CreatePicture, ChangePicture, SetPictureClipRectangles, Composite,
   FillRectangles, FreePicture, glyph sets, QuerySubpixelOrder.
7. Geometry/hit-testing: `XGetGeometry`, `XQueryTree`,
   `XTranslateCoordinates`, `XQueryPointer`, colour/visual queries.
8. Basic selections/clipboard.

**Tier 1 — functional preferred, graceful fallback:**
Shape (present, for DnD), XFixes, XKB (report absent), RandR (present/one
output), Xinerama (absent).

**Tier 2 — report absent, clean fallback:**
XSync, XDamage, XComposite, XShm, XInput, Xcursor.

---

## 7. Resolution log (as built)

Findings from the first successful GTK2 builds and test runs, and the shim
changes they produced:

| Symptom | Cause | Fix (in `xlib-wayland`) |
|---|---|---|
| `configure` aborts: `xft >= 2.0.0` unsatisfied | `xft.pc`/`x11.pc` reported the project version `0.1.0` | report `xft` 2.3.6, `x11` 1.8.13 |
| link: undefined `XGetSubImage` | not implemented | added |
| link: undefined `XkbGetState`, `XkbGetControls`, `XkbSelectEvents`, `XkbSelectEventDetails`, `XkbSetDetectableAutoRepeat`, `XkbFreeKeyboard` | XKB surface incomplete | added |
| first key event → SIGSEGV in `gdkkeys-x11.c` `XkbKeyNumGroups` | `XkbGetMap` returned a descriptor with NULL `map`/`server`/`names` | `XkbGetMap` now builds a real map from the xkbcommon keymap |
| keyval search aborts: `assertion failed (XkbKeySymEntry …)` | per-key arrays sized to the keymap max, but clients iterate to `XDisplayKeycodes()` max | size key arrays to the full 0..255 range |
| `pangoxft` link: undefined `XftGlyphExtents`, `XftDefaultHasRender`, `XftGlyphSpecRender`, `XftDrawGlyphSpec` | Xft subset | draw-level entry points implemented; Render-level ones are no-ops. GTK2 does not use pangoxft (it draws via pangocairo/Render), so this is inert. See `docs/RENDER-STATUS.md` |
| `liststore` segfault in GLib `GSequence` | GTK2 2.24 built against GLib 2.88 | build the pinned MATE 1.10-era stack (GLib 2.48.2, ATK 2.18.0, Pango 1.38.1, gdk-pixbuf 2.34.0) |
| `expander`/`testing` synthetic clicks did not reach widgets | `XWarpPointer` produced no crossing/motion, and the XKB key type had no modifier→level map | `XWarpPointer` now drives the motion path; `XkbGetMap` builds one- and two-level types so Shift selects level 1 |
| `keys-events` saw no focus right after `gtk_widget_grab_focus()` | focus waited for the compositor's `wl_keyboard.enter`; a stale leave deactivated the wrong window | FocusIn is emitted with the map; `wl_keyboard.leave` is matched to the surface that lost focus |
| gtk-demo frames differed from the core fallback | several Render-path bugs (stale clip on `CPClipMask=None`, alpha dropped by `XPutImage`, interleaved gradient stops, compound glyph ids) | fixed in the shim; all static demos now match — see [GTK-DEMO-STATUS.md](GTK-DEMO-STATUS.md) |
| Input methods could not compose | the shim's XIM was a local stub | XIM is a real bridge to `zwp_text_input_v3`; the shim's `docs/IME-STATUS.md` |
| Dead keys produced no composed character | `XLookupString` ignored compose state | keymap uses xkbcommon-compose |
| A selection owned by another shim process was invisible | each process is its own X server | `broker.c` shares X selections and `smprops.c` shares `_DT_SM_*` properties |

The earlier "remaining" items in this list (`XSendEvent` test helpers,
`testing`'s X-server timing, `defaultvalue`) are now passing; see
[TEST-RESULTS.md](TEST-RESULTS.md). The open gaps are tracked in
[STATUS.md](STATUS.md).

## 8. First findings during the GTK2 configure

- The shim's `xft.pc` reported version `0.1.0`; GTK2's `BASE_DEPENDENCIES`
  requires `xft >= 2.0.0` and aborted. Fixed in `xlib-wayland` by reporting
  `xft` 2.3.6 and `x11` 1.8.13.
