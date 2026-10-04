# GTK2 test-suite results

Run with:

```sh
scripts/build-shim.sh
scripts/build-deps.sh          # GLib 2.66 / ATK 2.38 / Pango 1.48 / gdk-pixbuf 2.42
scripts/build-gtk2.sh
scripts/run-tests-labwc.sh     # gtester over gtk/tests, inside nested labwc
```

## Environment

* **Compositor:** labwc 0.20.2, built from source with `-Dxwayland=disabled`,
  nested inside the host's Wayland session via `WLR_BACKENDS=wayland`.
  XWayland is never started and `DISPLAY` is unset; clients can only reach the
  shim.
* **Toolkit:** GTK+ 2.24.33, built unmodified against `$GTK2_PREFIX`.
* **Supporting stack (contemporary with GTK 2.24.33):** GLib 2.66.8,
  ATK 2.38.0, Pango 1.48.11, gdk-pixbuf 2.42.10, cairo/fontconfig/FreeType/
  HarfBuzz/fribidi from the host.
* **Shim:** `xlib-wayland`, installed as `libX11.so.6`.

## Result

`gtester` over the 14 `gtk/tests` programs: **11 pass, 3 fail.**

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
| expander | ❌ | synthetic click (`gtk_test_widget_click`) |
| action | ✅ | |
| defaultvalue | ❌ | non-shim: `GdkPixbuf.rowstride` default |
| testing | ❌ | 3 synthetic-input subtests + 1 X-server-timing subtest |

## The failures, precisely

### 1. `expander`, and `testing`'s `test_button_clicks` / `test_send_shift_key` / `test_spin_button_arrows`
These use GDK's **synthetic event test helpers** (`gtk_test_widget_click`,
`gdk_test_simulate_button`, `gdk_test_simulate_key`). Those build an `XEvent`
by hand and submit it with `XSendEvent`; the shim queues it and GDK consumes it,
but GDK does not dispatch it to the target widget, so the widget never sees the
click/key.

* Characterised with a standalone probe: after `gtk_test_widget_click`,
  `XPending()` is 2 and `gtk_events_pending()` is 1; after GDK's drain,
  `XPending()` is 0 and the widget handlers never ran.
* The shim's `XSendEvent` itself works: a pure Xlib probe sends a `ButtonPress`,
  sees `XPending() == 2`, and reads the event back with `XNextEvent` intact.
* **Real input works.** Driving the headless compositor's input replay
  (`motion` / `button` / `key`) at a GTK2 window delivers a real `KeyPress`
  (`keyval=0x6c`) and button events to the toolkit. This is the path real
  applications use; the synthetic helpers are test-only.

Status: **backlog** — likely GDK's window lookup or event-mask handling for
`XSendEvent`-delivered core events. It does not affect MATE or GIMP.

### 2. `testing`'s `test_xserver_sync`
```
assertion failed: (sync_is_slower > 0)
```
The test measures whether a draw followed by `gdk_test_render_sync()`
(`XSync`) is measurably slower than one without, asserting that a round-trip
costs something. The shim is in-process, so `XSync` is essentially free. This is
inherent to an in-process Xlib, not a bug; the test asserts X *server* timing.

Status: **expected / not applicable to a shim.**

### 3. `defaultvalue`
```
Property GdkPixbuf.rowstride: 1 != 3
```
`defaultvalue` walks every property of every GObject type, constructs an
instance and compares the current value to the default. `GdkPixbuf.rowstride`
does not match for a newly constructed pixbuf. No Xlib is involved in the
failing path; it is a gdk-pixbuf/GTK2 default-value expectation. Confirmed with
gdk-pixbuf 2.42.10 (the era-correct version), so it is not simply a
modern-gdk-pixbuf regression.

Status: **non-shim**; upstream GTK2 test expectation.

## What the era stack fixed

Before pinning GLib etc., `liststore` **segfaulted** in
`gtk_list_store_iter_is_valid` → `g_sequence_iter_get_sequence` (GLib 2.88's
`GSequence` internals vs. GTK2's stale-iterator handling) and `defaultvalue`
reported a different gdk-pixbuf mismatch. Building the Dec-2020 stack removed
the `liststore` crash.

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
   (The Render-level `XftGlyphSpecRender` remains impossible without a Render
   extension; see DESIGN.md.)
