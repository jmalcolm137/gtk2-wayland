# gtk-demo on the shim — status

`scripts/test-gtk-demo.sh` renders **every** gtk-demo demo (and the gtk-demo
browser itself) under the headless compositor twice — once on the shim's Render
path and once on cairo's core-protocol fallback — and compares the frames. The
fallback is cairo's own long-standing path, so a static demo must match it.

Animated demos are detected by capturing the fallback twice: if the fallback
itself differs between the two frames, the demo is skipped. `tests/gtk-demo-walker.c`
builds against the gtk-demo objects and runs one demo per invocation.

## Current result

The browser and 35 of 38 demos match the fallback (the browser to 0.03%).
Three remain:

| Demo | Symptom | Cause |
|---|---|---|
| Effects | reflection row missing (~20%) | the offscreen window is mirrored with a **source-picture transform** faded by a depth-8 alpha mask; the mask pixmap ends up empty, so nothing composites |
| Rotated Text | blank (~50%) | cairo renders the rotated glyphs through a **temporary surface + transform** that is never flushed/composited to the window |
| Multiple Views | ~9% | the two text views sit a few pixels higher than the fallback (a scroll-position/line-height rounding difference); every line therefore differs |

All three involve picture transforms or a subtle text-view scroll offset.
Everything cairo draws axis-aligned (the overwhelming majority of GTK2)
matches.

## What this test caught and fixed

* **GtkFrame titles and many labels vanished** (Button Boxes and others):
  cairo clears a picture clip with `ChangePicture(CPClipMask = None)`, which we
  ignored, leaving a stale one-glyph rectangle clip in force.
* **Black squares behind every icon** (Tool Palette) and a **black Icon View
  background**: `XPutImage` forced alpha to `0xff`, so cairo's premultiplied
  ARGB icon uploads into depth-32 pixmaps lost transparency.
* **Icons missing/wrong** (caja): the surface-pattern matrix had the wrong sign,
  pushing drawable sources out of their pattern.
* **Text spacing/position** (everywhere): glyph bitmap bearing and per-element
  padding were not applied.

## Running it

```sh
scripts/test-gtk-demo.sh            # all demos + browser, render vs fallback
scripts/test-gtk-demo.sh --jobs 8 --threshold 4
```

Frames and per-demo logs land in `tests/out/gtk-demo/`. The script exits
non-zero when a static demo differs from the fallback.
