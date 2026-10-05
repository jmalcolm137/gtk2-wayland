# MATE 1.10 on Wayland — status

MATE 1.10 (February 2016) is the second target: build its GUI applications
unmodified against the `xlib-wayland` shim and run them in nested labwc.

## The era-correct supporting stack

One stack serves GTK+ 2.24.33, MATE 1.10 and GIMP 2.10. MATE 1.10 sets the
upper bound on GLib: it defines compatibility functions GLib added later
(`libmatekbd` defines its own `g_strv_equal`, which GLib 2.60 declares), so a
2.60+ GLib collides with it. GIMP 2.10 sets the lower bound: it needs GLib
>= 2.54.2 (2.10.20+ needs 2.56.2). The common denominator is **GLib 2.56.2**
(the rest of the stack is the c.2016 era), built by `scripts/build-deps.sh`
into `$GTK2_PREFIX`:

| Library | Version | Why |
|---|---|---|
| GLib | 2.56.2 | base; the GTK2/MATE-1.10/GIMP-2.10 common denominator |
| ATK | 2.18.0 | base |
| Pango | 1.38.1 | with Xft (pangoxft), needed by marco |
| gdk-pixbuf | 2.34.0 | base |
| dconf | 0.26.0 | GSettings |
| libxklavier | 5.4 | libmatekbd |
| libunique | 1.1.6 | caja |
| gtksourceview | 2.10.5 | pluma |
| PCRE | 8.45 (1.x) | vte |
| vte | 0.28.2 | mate-terminal |
| libwnck | 2.30.7 | marco, mate-panel, applets |
| libsoup | 2.54.1 | libmateweather |
| libgtop | 2.40.0 | marco, mate-system-monitor |
| libcanberra | 0.30 | marco, settings-daemon, media |
| libcroco | 0.6.13 | librsvg |
| librsvg | 2.40.20 | mate-panel clock |
| libsigc++ / glibmm / gtkmm | 2.10 / 2.48 / 2.24 | mate-system-monitor (gtkmm 2.4 C++ bindings); also cairomm/pangomm/atkmm |
| poppler-glib | 0.50.0 | atril (PDF) and GIMP's PDF import (GIMP needs >= 0.50) |

cairo, fontconfig, FreeType, HarfBuzz and fribidi stay on the host.

Why so many: a host library compiled against a modern GLib embeds references to
GLib symbols the era stack lacks (`g_once_init_enter_pointer`, added 2.80),
and a host library that needs GLib >= 2.50 or 2.62 (librsvg, libsoup, libgtop,
libcanberra, ...) simply fails pkg-config. Every host library linked into the
MATE process must be its era build.

## Build matrix

Built (29 components):

```
mate-common        mate-desktop      libmatekbd        libmateweather
mate-menus         mate-icon-theme   mate-backgrounds  libmatemixer
marco              mate-panel        mate-applets      mate-session-manager
mate-settings-daemon  mate-control-center  mate-netbook  mate-netspeed
mate-sensors-applet   mate-media       mate-screensaver  caja
caja-extensions    engrampa          eom               pluma
mate-terminal      mate-utils        mate-calc (1.8)   mate-system-monitor
atril
```

Verified running and rendering under the shim (`scripts/run-app.sh --capture`):

| App | Evidence |
|---|---|
| caja | file manager: menubar, toolbar, Places sidebar, icon view |
| eom | image viewer chrome |
| engrampa | archive manager |
| pluma | editor: toolbar, tab, status bar |
| mate-terminal | live shell prompt |
| mate-panel | panel strip |
| mate-calc | 1.8.0 (last GTK2 release; no 1.10): keypad, menu, display |

Every app above renders identically with Render on (the default) and with
`MW_RENDER=0`. caja in particular used to abort in `mate_bg`'s
`_cairo_xlib_surface_draw_image` under Render; that was the shim's direct-format
mask encoding and is fixed (see `docs/RENDER-STATUS.md`). Text layout and icon
compositing now match cairo's core-protocol path pixel-for-pixel (glyph bearing
placement, per-element 4-byte padding, and the surface-pattern matrix sign).

## Remaining components and their blockers

| Component | Blocker |
|---|---|
| mate-notification-daemon | era libnotify (host 0.8.8 needs GLib >= 2.62) |
| mate-power-manager | era upower + libnotify |
| mate-polkit | era polkit (host needs GLib >= 2.62) |
| mate-user-share | gobject-introspection >= 2.82 / era deps |
| mozo | Python 2 + pygtk |
| python-caja | Python 2 |
| caja-dropbox | proprietary Dropbox; out of scope |

## Shim accommodations this drove

* **XKB**: `XkbGetKeyboard`, `XkbTranslateKeyCode`, `XkbKeysymToModifiers`,
  `XkbGetIndicatorState`, `XkbLockGroup`, `XkbLatchGroup`, `XkbLockModifiers`,
  `XkbLatchModifiers`, `XkbSetControls`, `XkbChangeEnabledControls`, the bell
  family, and `XkbUseExtension`. Getters answer from the real keymap;
  state-changing requests are accepted and not carried.
* **Xft**: `XftInit`, `XftInitFtLibrary`, and the Render-level glyph entry
  points, so pangoxft exists for marco. pangoxft renders through the draw-level
  path the shim implements. The shim now also provides a full Render extension
  (`docs/RENDER-STATUS.md`), but Xft's Render-level entry points remain no-ops;
  nothing in the GTK2/MATE stack exercises them (GTK2 draws via pangocairo).

## Host-compiler / host-tool accommodations (not source patches)

* `-fcommon` (GCC 10 defaults), `_GNU_SOURCE` (IPC_INFO), forced
  `stdlib.h`/`stdint.h` includes (newer glibc), `-DG_CONST_RETURN=const`,
  and the usual `-Wno-error=...` set.
* The system `py-compile` (the in-tree ones use the removed `imp` module).
* `itstool`, `icon-naming-utils` staged from distro packages for MATE's
  configure scripts.
* Install-time hooks: the prefix's `gtk-update-icon-cache`/`glib-compile-schemas`
  are used, and `update-mime-database`/`update-desktop-database` (host tools
  built against modern GLib) are no-ops.

## Running an app

```sh
scripts/run-app.sh caja                       # nested labwc
scripts/run-app.sh --capture caja.png caja    # headless frame capture
```
