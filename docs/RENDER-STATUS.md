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

* **Glyph/text compositing.** `AddGlyphs`/`CompositeGlyphs` parse and store glyph
  masks, but the per-glyph placement and mask/colour interaction are not yet
  pixel-correct, so text disappears on the Render path. This is the main gap.
* `XRenderFindStandardFormat`'s templates do not all match the advertised
  formats yet (A8 matches; ARGB32/RGB24 matching needs the exact template
  fields from libXrender's table).
* Operator coverage beyond the common `PictOpOver`/`Src`, and picture
  transforms, are approximate.
* Conical gradients are approximated.

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
