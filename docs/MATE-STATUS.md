# MATE 1.10 on Wayland — status

MATE 1.10 (February 2016) is the second target: build its GUI applications
unmodified against the `xlib-wayland` shim and run them in nested labwc.

## The era-correct supporting stack

MATE 1.10 constrains the whole stack. It is older than GTK+ 2.24.33 and defines
compatibility functions that GLib added later (`libmatekbd` defines its own
`g_strv_equal`, which GLib 2.60 declares), so a 2.60+ GLib collides with it.
Pango 1.48 in turn needs GLib >= 2.62. The common denominator — used for GTK2,
MATE 1.10 and GIMP 2.10 — is:

| Library | Version | Build |
|---|---|---|
| GLib | 2.48.2 | autotools |
| ATK | 2.18.0 | autotools |
| Pango | 1.38.1 | autotools |
| gdk-pixbuf | 2.34.0 | autotools |
| dconf | 0.26.0 | autotools |
| libxklavier | 5.4 | autotools |
| libunique | 1.1.6 | autotools |
| gtksourceview | 2.10.5 | autotools |
| PCRE | 8.45 (1.x) | autotools |
| vte | 0.28.2 | autotools |

These are built by `scripts/build-deps.sh` into `$GTK2_PREFIX`. cairo,
fontconfig, FreeType, HarfBuzz and fribidi stay on the host.

The reason several of these had to be added at all: a host library compiled
against a modern GLib embeds references to GLib symbols the era stack does not
have (for example `libdconf` and `libxklavier` need `g_once_init_enter_pointer`,
added in GLib 2.80). Any host library linked into the MATE process must be the
era build. dconf, libxklavier and libunique are the ones that surfaced.

## Components built

| Component | Version | Notes |
|---|---|---|
| mate-common | 1.10.0 | m4 macros |
| mate-desktop | 1.10.2 | `libmate-desktop-2.0` |
| libmatekbd | 1.10.1 | needs libxklavier |
| mate-menus | 1.10.1 | |
| engrampa | 1.10.2 | **with** its Caja extension (`libcaja-engrampa.so`) |
| eom | 1.10.5 | image viewer |
| caja | 1.10.4 | file manager, `libcaja-extension` |
| pluma | 1.10.2 | text editor (needs gtksourceview 2.x) |
| mate-terminal | 1.10.2 | terminal (needs vte 0.28 + PCRE1) |

Verified running and rendering under the shim (`scripts/run-app.sh --capture`):

* **caja** — full menubar, toolbar, Places sidebar and icon view (800×550).
* **eom** — viewer menubar and zoom toolbar (540×450).
* **engrampa** — archive-manager window (600×480).
* **pluma** — editor with toolbar, tab and status bar (650×500).
* **mate-terminal** — terminal running a live shell prompt (658×487).

## Shim accommodations this drove

* **XKB**: `XkbGetKeyboard`, `XkbTranslateKeyCode`, `XkbKeysymToModifiers`,
  `XkbGetIndicatorState`, `XkbLockGroup`, `XkbLatchGroup`, `XkbLockModifiers`,
  `XkbLatchModifiers`, `XkbSetControls`. Getters answer from the real keymap;
  state-changing requests are accepted and not carried. (In `xlib-wayland`.)

## Host-compiler accommodations (not source patches)

MATE 1.10 predates GCC 10 and modern glibc:

* `-fcommon` — GCC 10 defaults to `-fno-common`, breaking tentative definitions.
* `-include stdlib.h -include string.h -include stdint.h` — newer glibc no
  longer pulls these in transitively, and 2016 code relies on it.
* `-DG_CONST_RETURN=const` — GLib removed the macro after 2.30; libunique
  still uses it.
* The usual `-Wno-error=...` set.

These live in `scripts/build-mate.sh` (`MATE_CFLAGS`) and `build-deps.sh`
(`DEP_CFLAGS`).

## Remaining components and their blockers

These need another era library before they can build; each is the same pattern
(host copy is GTK3-only or GLib-2.60+-built):

| Component | Needs |
|---|---|
| libmateweather, mate-panel, mate-applets | libsoup 2.4 (era; host is 2.74 → GLib 2.58) |
| marco, mate-panel, mate-applets, mate-system-monitor | libwnck (GTK2) |
| mate-system-monitor | gtkmm 2.4 / glibmm 2.4 |
| mate-settings-daemon, mate-media, mate-power-manager | libcanberra-gtk (GTK2) |
| atril | poppler-glib with the GTK2 API |
| mozo | Python 2 + pygtk (no build without it) |
| mate-polkit | polkit-gobject (glib-only; likely fine) |
| python-caja, caja-dropbox | Python 2 / proprietary; out of scope |

## Running an app

```sh
scripts/run-app.sh caja                 # in nested labwc (needs a host session)
scripts/run-app.sh --capture caja.png caja   # headless, captures a frame
```
