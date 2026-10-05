# gtk-demo on the shim — status

`scripts/test-gtk-demo.sh` renders **every** gtk-demo demo and the gtk-demo
browser itself under the headless compositor on the shim's Render path and on
cairo's core-protocol fallback, and compares the frames. The fallback is
cairo's own long-standing path, so a static demo must match it.

A demo is treated as **animated** if either path changes between two frames
captured a second apart; those are skipped rather than compared. Everything
else must match the fallback within a 4% pixel threshold.

## Result

**All static demos match the core fallback** (browser to 0.03%). Two demos are
legitimately animated and skipped:

| Demo | Why skipped |
|---|---|
| Pixbufs | the pixbufs animate continuously |
| Automatic scrolling | the text view scrolls continuously |

Everything else — including the transform-heavy beacons below — is a 0.00%
pixel match:

* **Rotated Text** — the rotated `I ♥ GTK+` ring, drawn through cairo's
  transformed-glyph path.
* **Effects** — the offscreen-window mirror with its flipped, gradient-faded
  reflection.
* **Multiple Views** — two text views sharing one buffer.
* **Button Boxes, Tool Palette, Icon View, Images, Application main window**,
  and the rest.

## What the walker found (and fixed)

Each of these was a real shim bug the fallback comparison caught:

* **GtkFrame titles and many labels vanished** (Button Boxes): cairo clears a
  picture clip with `ChangePicture(CPClipMask = None)`, which we ignored,
  leaving a stale one-glyph clip.
* **Black squares behind every icon** (Tool Palette) and a **black Icon View
  background**: `XPutImage` forced alpha to `0xff`, so cairo's premultiplied
  ARGB icon uploads lost transparency.
* **Every gradient's colours were garbage**: Create*Gradient stops are sent as
  *all positions then all colours*, which we read interleaved.
* **Transformed gradients were evaluated in the wrong space**: `set_source`
  returned from the gradient branch before applying the picture transform.
* **Rotated Text blank / Effects reflection missing / Multiple Views offset**:
  cairo's glyph indices are compound (`font << 24 | glyph`), so the
  array-per-glyph-set grew to 268M entries and the allocation failure made
  cairo abandon the draw. A hash map keyed by glyph id fixes all three.
* Plus glyph bitmap bearing/per-element padding, and the surface-pattern matrix
  sign.

## Running it

```sh
scripts/test-gtk-demo.sh            # all demos + browser, render vs fallback
scripts/test-gtk-demo.sh --jobs 8 --threshold 4
```

Frames and per-demo logs land in `tests/out/gtk-demo/`. The script exits
non-zero if any static demo differs from the fallback.
