# GTK2 test-suite results

Run with:

```sh
scripts/build-shim.sh
scripts/build-deps.sh          # GLib 2.48 / ATK 2.18 / Pango 1.38 / gdk-pixbuf 2.34
scripts/build-gtk2.sh
scripts/run-tests-labwc.sh     # gtester over gtk/tests, inside nested labwc
```

## Environment

* **Compositor:** labwc 0.20.2, built from source with `-Dxwayland=disabled`,
  nested inside the host's Wayland session via `WLR_BACKENDS=wayland`.
  XWayland is never started and `DISPLAY` is unset; clients can only reach the
  shim.
* **Toolkit:** GTK+ 2.24.33, built unmodified against `$GTK2_PREFIX`.
* **Supporting stack (MATE 1.10 era, the common era for GTK2/MATE/GIMP):**
  GLib 2.48.2, ATK 2.18.0, Pango 1.38.1, gdk-pixbuf 2.34.0,
  cairo/fontconfig/FreeType/HarfBuzz/fribidi from the host.
* **Shim:** `xlib-wayland`, installed as `libX11.so.6`; Render is on by default
  (the suite passes identically with `MW_RENDER=0`).

## Result

`gtester` over the 14 `gtk/tests` programs: **14 pass, 0 fail** (identical with
Render on and off).

| Program | Result | Notes |
|---|---|---|
| object | ✅ | |
| floating | ✅ | |
| builder | ✅ | |
| liststore | ✅ | passes once built against the era GLib (see below) |
| treestore | ✅ | |
| treeview | ✅ | |
| treeview-scrolling | ✅ | |
| textbuffer | ✅ | |
| recentmanager | ✅ | |
| filtermodel | ✅ | |
| expander | ✅ | synthetic click (`gtk_test_widget_click`) |
| action | ✅ | |
| defaultvalue | ✅ | passes with the era gdk-pixbuf (see below) |
| testing | ✅ | all synthetic-input subtests pass |

## The synthetic-input tests (all passing)

`expander` and `testing`'s `button-clicks` / `keys-events` / `send-shift-key` /
`spin-button-arrows` drive GDK's **synthetic event test helpers**
(`gtk_test_widget_click`, `gdk_test_simulate_button`, `gdk_test_simulate_key`).
Those build an `XEvent` by hand and submit it with `XSendEvent`; the shim queued
and delivered it, but the widget never saw it. Two shim gaps, both found by
comparing a synthesised event against a real one:

1. **`XWarpPointer` produced no crossing/motion events.** GDK's client-side
   window hit test (`_gdk_window_get_input_window_for_event` →
   `get_pointer_window`) only descends into child windows when its
   `toplevel_under_pointer` is set, which happens on `EnterNotify`. A real
   server emits the Leave/Enter and Motion for the new location on a warp.
   `XWarpPointer` now drives the same path as a real motion, so a warped then
   synthesised click resolves to the widget's client-side window.
2. **The XKB key *type* had no modifier→level map.** GDK (like Xlib) derives the
   shift level from `XkbKeyTypeRec.map`, not directly from the core `ShiftMask`.
   Our client map had a single type with `map == NULL`, so Shift never selected
   level 1 and a shifted key reported its unshifted keysym. `XkbGetMap` now
   builds a one-level and a two-level type (Shift → level 1), and
   `XkbLookupKeySym` honours the state.

Two further focus fixes were needed for `keys-events` (which asserts the button
has focus right after `gtk_widget_grab_focus()`):

3. **Focus arrived too late.** Our `XSendEvent`-era focus only came from the
   compositor's `wl_keyboard.enter`, which lands after `gtk_widget_show_now()`
   has already returned. A window manager focuses a newly mapped toplevel, so
   the shim now emits the matching FocusIn with the map (after the `MapNotify`)
   and a FocusOut when the focus window is destroyed.
4. **A stale `wl_keyboard.leave` deactivated the wrong window.** `kbd_leave()`
   delivered FocusOut to whatever `kbd_focus` currently pointed at, ignoring
   which surface had left. When focus moved A → B the compositor's delayed
   `leave(A)` aimed a FocusOut at B. It is now matched to the leaving surface;
   this was the only reason `keys-events` failed when run after another subtest
   (it passed in isolation).

### 2. `testing`'s `test_xserver_sync` (now passing)
This measures whether a draw followed by `gdk_test_render_sync()` (`XSync`) is
measurably slower than one without, asserting a round-trip costs *something*.
The shim is in-process, so `XSync` is nearly free; it passes now that enough
real request-buffer work happens around the sync. It is timing-sensitive, not a
correctness check.

### 3. `defaultvalue` (now passing)
`defaultvalue` walks every property of every GObject type, constructs an
instance and compares the current value to the default. It used to fail on
`GdkPixbuf.rowstride` with a modern gdk-pixbuf; with the era gdk-pixbuf 2.34.0 it
passes. No Xlib is involved.

## What the era stack fixed

Before pinning GLib etc., `liststore` **segfaulted** in
`gtk_list_store_iter_is_valid` → `g_sequence_iter_get_sequence` (GLib 2.88's
`GSequence` internals vs. GTK2's stale-iterator handling) and `defaultvalue`
reported a gdk-pixbuf mismatch. Building the pinned era stack (MATE 1.10 era,
the common era for GTK2/MATE/GIMP) removed the `liststore` crash and the
`defaultvalue` mismatch.

## Shim fixes this suite drove

1. `xft.pc`/`x11.pc` reported the project version (`0.1.0`); GTK2's
   `BASE_DEPENDENCIES` requires `xft >= 2.0.0`. Now `xft` reports 2.3.6 and
   `x11` 1.8.13.
2. `XGetSubImage` was missing.
3. `XkbGetState`, `XkbGetControls`, `XkbSelectEvents`, `XkbSelectEventDetails`,
   `XkbSetDetectableAutoRepeat`, `XkbFreeKeyboard` were missing.
4. `XkbGetMap` returned a descriptor with a NULL `map`/`server`/`names`, so any
   XKB client (GDK above all) crashed. It now builds a real client map from the
   compositor's xkbcommon keymap — including sizing the per-key arrays to the
   full 0..255 keycode range that `XDisplayKeycodes()` advertises, which was an
   out-of-bounds read for keycodes above the keymap's maximum.
5. `Xft` gained the draw-level glyph entry points (`XftGlyphExtents`,
   `XftDrawGlyphs`, `XftDrawGlyphSpec`, `XftDrawGlyphFontSpec`,
   `XftDrawCharFontSpec`, `XftDefaultHasRender`) on the shim's own font path.
   (Xft's Render-level `XftGlyphSpecRender` stays a no-op; GTK2 uses
   pangocairo, which goes through Render directly. See `docs/RENDER-STATUS.md`.)
6. `XWarpPointer` now emits the crossing and motion events for the new pointer
   position (see the synthetic-input section above).
7. `XkbGetMap` emits one- and two-level key types with a real modifier→level
   map so Shift selects level 1; `XkbLookupKeySym` honours the state.
8. A normal toplevel gets `FocusIn` with its map and `FocusOut` when the focus
   window is destroyed, instead of waiting for the compositor's
   `wl_keyboard.enter`.
9. `wl_keyboard.leave` is matched to the surface that actually lost the
   keyboard, so a delayed leave cannot focus out the window that just took
   focus.
