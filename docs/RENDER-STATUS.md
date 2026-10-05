# Render extension — status

The shim implements the X11 **Render** extension (`src/xlib/render.c` in
`xlib-wayland`), translating libXrender's wire requests onto the cairo raster
backend. It is **enabled by default**; `MW_RENDER=0` opts back into cairo's
core-protocol fallback (handy for isolating a Render bug).

GTK2 2.24.33's gtester suite and all built MATE 1.10 apps render identically
with Render on and off, so Render is now the normal path.

## Why it needed more than a request handler

libXrender builds its requests with Xlib's `Xlibint.h` macros, which write into
`Display.buffer`/`bufptr` and allocate ids through `Display.resource_alloc`
(`XAllocID`). The shim had never provided either, because the Xt/Motif stack
only calls public Xlib entry points. Render exposed both:

* `XOpenDisplay` allocates the output buffer and sets `resource_alloc`.
* `_XGetRequest` reserves space in that buffer; `mw_render_drain()` walks it on
  flush / `_XReply` and dispatches Render requests by major opcode.

Because requests are buffered, object lifetime and request ordering matter:

* `mw_unregister` drains pending Render requests first (guarded by
  `render_draining`), and `XFreePixmap`/`XDestroyWindow` drain before freeing
  the drawable's surface — cairo creates a temporary pixmap, pictures it, draws,
  and frees it all before its requests reach us.
* `mw_canvas_for_drawable` (used by all core drawing/copy entry points) drains
  first, so GDK's `XCopyArea` backing-store flush observes preceding Render
  draws.

## Implemented

| Area | Requests |
|---|---|
| Queries | QueryVersion, QueryPictFormats, QueryFilters, QuerySubpixelOrder |
| Pictures | CreatePicture, ChangePicture, FreePicture, SetPictureClipRectangles |
| Compositing | Composite, FillRectangles |
| Sources | CreateSolidFill, CreateLinear/Radial/ConicalGradient (stops) |
| Glyphs | Create/Reference/FreeGlyphSet, AddGlyphs, FreeGlyphs, CompositeGlyphs8/16/32 |
| State | SetPictureTransform, SetPictureFilter |
| Geometry | Trapezoids, Triangles |
| Cursors | CreateCursor/CreateAnimCursor accepted |

Formats advertised: ARGB32, RGB24, A8, A1; the screen visual maps to RGB24
(ARGB32 at depth 32).

### Direct-format encoding

`xDirectFormat`'s component fields are bit **shifts** and the `*Mask` fields are
component value **masks** (the X server's `Mask()` convention). For ARGB32:

```
red=16, redMask=0xff, green=8, greenMask=0xff,
blue=0, blueMask=0xff, alpha=24, alphaMask=0xff
```

Consumers such as cairo reconstruct a pixel mask as `mask << shift`. Emitting
full pixel masks with zero shifts made cairo derive mask 0 and abort in
`_pixman_format_from_masks` (the caja/`mate-bg` failure). The correct encoding is
required for `XRenderFindStandardFormat`'s ARGB32/RGB24 templates too.

### Glyph runs

`CompositeGlyphs` is reproduced from the X server's `miGlyphs`:

* the pen accumulates from the picture origin — each element adds its
  `(deltax,deltay)`, then each glyph adds its stored advance (cairo/Xft put
  `x_advance` in the glyph-set entry's `xOff`/`yOff`, **not** the element
  delta). The request's `xSrc`/`ySrc` are *source* coordinates, not the
  destination origin.
* each glyph bitmap is placed at `pen - xGlyphInfo.x/y`: `x`/`y` are the
  bitmap bearing, not zero. Ignoring them shifted text left ~1px and down by
  the ascent (~10px).
* each element's glyph data is padded to a 4-byte boundary
  (`space = size*len; if (space&3) space += 4-(space&3)`); without this,
  kerned multi-element runs desync. The `0xff` glyphset-change marker is
  handled too.

### Composite / pictures

The cairo surface-pattern matrix maps **user space to pattern space**, so a
source sampled at `(xs,ys)` and drawn at `(xd,yd)` needs
`translate(xs-xd, ys-yd)`; the sign matters — inverting it pushes drawable
sources (icons) out of their pattern.

Fidelity is checked by diffing a labelled text grid rendered with `MW_RENDER=1`
against `MW_RENDER=0` (cairo's core-protocol path): the two agree except for a
one-pixel antialiasing row.

### Core GC clips interact with Render

cairo's core-Xlib path (used by Render-level glyph/tile scratch work) sets a GC
clip with `XSetClipRectangles` and clears it with `XSetClipMask(gc, None)`. A
mask replaces the rectangle clip, so `XSetClipMask` must drop the stored
rectangle clip as well — like the Render code does for `CPClipMask`. Leaving it
in place applied the previous tile's box to the following `XCopyArea`, silently
dropping it; the GIMP ruler's blitted scratch then carried a stale box over the
ticks, so a trail of ticks vanished behind the moving marker near the top-left
corner (`xlib-wayland` commit `46eceb7`).

## Still approximate

* Operator coverage beyond `PictOpOver`/`Src`, picture transforms and conical
  gradients are approximations, not exact.
* `libpangoxft`'s Render-level entry points remain no-ops; GTK2 uses
  pangocairo, so nothing in the current stack exercises them.

## Verifying

```sh
# Render (default)
scripts/run-app.sh --capture /tmp/render.png <app>

# core fallback
MW_RENDER=0 scripts/run-app.sh --capture /tmp/fallback.png <app>
```

`MW_TRACE_RENDER=1` logs each intercepted request and drain.
