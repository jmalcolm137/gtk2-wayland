# Accessibility (ATK / AT-SPI)

GTK2's accessibility is **ATK** inside the toolkit (implemented by the in-tree
**GAIL** module) plus the **AT-SPI bridge** that publishes the ATK tree over
**D-Bus**.  Assistive technology (Orca, a magnifier, …) connects to the
accessibility bus and walks that tree.

None of that is libX11: the shim is not on the path, and GDK already gets
everything its a11y code needs from it (window geometry, focus events,
`_NET_WM_PID`).  The work is therefore on this side — making the bridge actually
load and run against the GTK2 stack.

## The glib mismatch

The host's `libatk-bridge-2.0` (at-spi2-core 2.6x) is built against **glib ≥
2.78** and additionally **refuses same-version glib** — and needs newer glib
symbols (`g_free_sized`, `g_once_init_enter_pointer`, …) that the GTK2 stack's
**glib 2.56** does not have.  The host's GTK2 bridge module
(`gtk-2.0/modules/libatk-bridge.so`) is not even shipped any more.

So `scripts/build-a11y.sh` builds **era-matched** releases against the GTK2
prefix and installs them into `$GTK2_PREFIX/a11y`:

* **at-spi2-core 2.26.2** — `libatspi`, `at-spi-bus-launcher`,
  `at-spi2-registryd`.  Configured `--disable-x11`: input synthesis is the
  compositor's job under Wayland, so the XTest path is deliberately absent.
* **at-spi2-atk 2.22.0** — `libatk-bridge-2.0` and the **GTK2 module**
  (`gtk-2.0/modules/libatk-bridge.so`), which is copied into
  `$GTK2_PREFIX/lib/gtk-2.0/modules` where GTK2 looks for `GTK_MODULES` entries.

(2.22.0 only needs atk ≥ 2.15.4, so the prefix's atk 2.18 is fine and atk does
not have to be rebuilt.)

## Running it

A GTK2 app enables the bridge with `GTK_MODULES=gail:atk-bridge`.  The a11y bus
is a D-Bus service (`org.a11y.Bus`); it must be activated from **our**
launcher, not the host's (which is a systemd `--user` unit that fails in a bare
session).  Because `dbus-daemon` reads `XDG_DATA_DIRS` when it starts, the a11y
prefix has to be on it for the whole `dbus-run-session`:

```sh
XDG_DATA_DIRS="$GTK2_PREFIX/a11y/share:$GTK2_PREFIX/share:/usr/share" \
  dbus-run-session -- …
```

and the app runs with `LD_LIBRARY_PATH=$GTK2_PREFIX/a11y/lib:$GTK2_PREFIX/lib`.

## Test

`scripts/test-a11y.sh` starts the headless compositor and a GTK2 app
(`tests/a11y_app.c`, a window with a button) inside `dbus-run-session`, then
runs an AT-SPI client (`tests/a11y_query.c`) that walks the desktop and finds
the button.  It passes when the client reports `A11Y:RESULT found=1`.

## Not covered here

* **Input synthesis** (a screen reader driving the app): under Wayland that is
  the compositor's, via `libei`/`zwp_virtual_keyboard`, not XTest — so the shim
  does not emulate XTest and this stack is built `--disable-x11`.
* The **host** GTK3 a11y stack is unaffected; this is a separate era-matched
  copy under `$GTK2_PREFIX/a11y`.
