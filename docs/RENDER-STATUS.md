# Render extension — status

The shim now implements the X11 **Render** extension (`src/xlib/render.c` in
`xlib-wayland`), translating libXrender's wire requests onto the cairo raster
backend. It is **gated behind `MW_RENDER=1`** while text/glyph compositing is
finished: without it, cairo-xlib keeps using its core-protocol fallback (which
renders GTK2 correctly today); with it, cairo takes the Render path.

## Why it needed more than a request handler

libXrender builds its requests with Xlib's `Xlibint.h` macros, which write into
`Display.buffer`/`bufptr` and allocate ids through `Display.resource_alloc`
(`XAllocID`). The shim had never provided either, because the Xt/Motif stack
only calls public Xlib entry points. Render exposed both:

* `XOpenDisplay` now allocates the output buffer and sets `resource_alloc`.
* `_XGetRequest` reserves space in that buffer; `mw_render_drain()` walks it on
  flush / `_XReply` and dispatches Render requests by major opcode.

## Implemented

| Area | Requests |
|---|---|
| Queries | QueryVersion, QueryPictFormats (4 formats, screen/depth/visual map, subpixel), QueryFilters, QuerySubpixelOrder |
| Pictures | CreatePicture, ChangePicture, FreePicture, SetPictureClipRectangles |
| Compositing | Composite, FillRectangles |
| Sources | CreateSolidFill, CreateLinear/Radial/ConicalGradient (stops) |
| Glyphs | Create/Reference/FreeGlyphSet, AddGlyphs, FreeGlyphs, CompositeGlyphs8/16/32 |
| State | SetPictureTransform, SetPictureFilter |
| Geometry | Trapezoids, Triangles |
| Cursors | CreateCursor/CreateAnimCursor accepted |

Formats advertised: ARGB32, RGB24, A8, A1; the screen visual maps to RGB24
(ARGB32 at depth 32).

## Remaining before it can be the default

* **Glyph/text compositing.** `AddGlyphs` parses glyph images and
  `CompositeGlyphs8` dispatches per-glyph draws, but the **glyph-element
  `deltax`/`deltay` semantics are not right**: cairo's request sets
  `xSrc=65, ySrc=105` and a single element `len=28, deltax=65, deltay=105`
  (the run's start), so advancing per glyph by `deltax` spreads the glyphs
  65px apart instead of by the glyph advance — which means cairo is encoding
  the position differently than a naive per-glyph `+= deltax` reading. This
  needs to be matched against cairo's `_cairo_xlib_surface_show_glyphs` (or
  the X server's `CompositeGlyphs`) before text is correct.
* `XRenderFindStandardFormat`'s A8 template matches; ARGB32/RGB24 still need
  the exact field values libXrender compares.
* Operator coverage beyond `PictOpOver`/`Src`, picture transforms and conical
  gradients are approximate.

Once glyphs render, flip the `MW_RENDER` gate to default-on: that removes the
last reason `libpangoxft`'s Render-level entry points are no-ops, and lets
`pangoxft` use its real path too.

## Verifying

```sh
# core fallback (default): GTK2 text renders (217 colours in the smoke frame)
scripts/run-app.sh --capture /tmp/default.png <app>

# Render path
MW_RENDER=1 scripts/run-app.sh --capture /tmp/render.png <app>
```

`MW_TRACE_RENDER=1` logs each intercepted request and drain.
