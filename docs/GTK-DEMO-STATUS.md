# gtk-demo on the shim — status

`scripts/test-gtk-demo.sh` renders **every** gtk-demo demo (and the gtk-demo
browser itself) under the headless compositor twice — once on the shim's Render
path and once on cairo's core-protocol fallback — and compares the frames. The
fallback is cairo's own long-standing path, so a static demo must match it.

Animated demos are detected by capturing the fallback twice: if the fallback
itself differs between the two frames, the demo is skipped. `tests/gtk-demo-walker.c`
builds against the gtk-demo objects and runs one demo per invocation.

## Current result

The browser and 34 of 38 demos match the fallback (the browser to 0.03%).
Four remain:

| Demo | Symptom | Cause |
|---|---|---|
| Images | partial frame differs (~34%) | the demo animates (robot, progressive loading); the measured diff is dominated by animation phase |
| Effects | reflection row missing (~20%) | draws the offscreen window through a **source-picture transform** (vertical flip) plus a gradient mask |
| Rotated Text | blank (~50%) | cairo renders the rotated glyphs through a **temporary surface + transform**; the glyph run arrives in the temp surface's coordinates and is never composited back |
| Multiple Views | ~9% | the text view is scrolled a few pixels differently at capture time |

All four are **transformed-source / transformed-destination** paths. Everything
that cairo draws axis-aligned (the overwhelming majority of GTK2) matches.

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
