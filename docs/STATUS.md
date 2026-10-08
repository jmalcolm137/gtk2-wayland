# GTK+ 2 on Wayland — consolidated status

This is the index and gap list for the whole port. The per-area documents
(`RENDER-STATUS.md`, `INPUT-STATUS.md`, `IME-STATUS.md` in the shim,
`MATE-STATUS.md`, `GIMP-STATUS.md`, `TEST-RESULTS.md`, `GTK-DEMO-STATUS.md`)
go into detail; this page says where we are and what is left.

> **Note on freshness.** The shim (`xlib-wayland`) moves faster than this tree's
> prose. Where the two disagree, the shim's `README.md`/`docs/` and the
> `versions.lock` revision are authoritative.

## What works

| Area | State | Evidence |
|---|---|---|
| Build, unmodified | ✅ | GTK+ 2.24.33 configures/builds against the shim; no source patches |
| Rendering | ✅ | full Render extension on by default; `MW_RENDER=0` falls back to cairo core |
| gtk-demo | ✅ | every *static* demo matches the core fallback; 2 animated skipped — [GTK-DEMO-STATUS.md](GTK-DEMO-STATUS.md) |
| GTK2 test suite | ✅ 14/14 | `scripts/run-tests-labwc.sh` under nested labwc — [TEST-RESULTS.md](TEST-RESULTS.md) |
| Pointer / keyboard / XKB | ✅ | shift levels, focus, popups/menus, wheel, key repeat |
| Dead keys / compose | ✅ | xkbcommon-compose in the shim's keymap |
| EWMH window states | ✅ | `_NET_WM_STATE` fullscreen/maximize honoured |
| Input methods | ✅ | XIM is a real bridge to `zwp_text_input_v3`; `scripts/test-ime.sh` |
| XSettings | ✅ | the shim owns `_XSETTINGS_S0` and publishes a config file; `scripts/test-settings.sh` (caveats below) |
| Clipboard (text) | ✅ | X selections ↔ `wl_data_device`; cross-process via the shim's broker |
| Clipboard (non-text) | ✅ | full MIME list, `TARGETS`, `image/png`/`text/uri-list` both ways — shim's `docs/CLIPBOARD-STATUS.md` |
| PRIMARY selection | ✅ | select-to-paste bridged to Wayland (primary-selection v1) |
| XFIXES / Xcursor | ✅ | shim `libXfixes`/`libXcursor` facades: GDK clipboard owner-change tracking and themed/image cursors — shim's `docs/XFIXES-STATUS.md` |
| MATE 1.10 | 🚧 29 components | build and run unmodified — [MATE-STATUS.md](MATE-STATUS.md) |
| GIMP 2.10 | ✅ | builds, runs, renders with no XWayland — [GIMP-STATUS.md](GIMP-STATUS.md) |

Cross-process fans-out the shim now handles: **selections** via `broker.c`
(`XLIB_WAYLAND_SHARE_SELECTIONS`) and **session-manager properties** via
`smprops.c` (`XLIB_WAYLAND_SHARE_PROPERTIES`). Both exist because every shim
process is its own X server.

## What is left for "full" GTK2

Ordered by user-visible impact.

| # | Gap | Notes |
|---|---|---|
| 1 | **XDND (GDK drag-and-drop)** | GDK's X11 DnD is XDND; it needs a source+destination bridge onto `wl_data_device` (the Motif bridge + broker are the model). **In progress separately — not touched here.** |
| 2 | **Non-text clipboard / PRIMARY** | Mostly done: the shim carries the full MIME list, answers `TARGETS`, serves `image/png`/`text/uri-list` both ways, and bridges `PRIMARY` (select-to-paste) via primary-selection v1 (`xlib-wayland/docs/CLIPBOARD-STATUS.md`). Remaining: `SECONDARY`, format-32 targets. |
| 3 | **XEmbed** | `GtkPlug`/`GtkSocket` cross-process embedding (reparent + XFixes + `XSendEvent`) is not bridged. |
| 4 | **Optional extensions** | **Xfixes and Xcursor are now provided** (shim `libXfixes`/`libXcursor` facades), so GDK's clipboard owner-change tracking and themed cursors work. Still absent: XSync, XDamage, XComposite, XShm, Xinerama and XInput2 (tablets/touch/hotplug); GDK degrades. We build `--with-xinput=no` and `--disable-xinerama`. Multi-monitor via RandR is single-output. |
| 5 | **Accessibility** | GTK2's ATK/AT-SPI bridge (DBus) is not addressed. |
| 6 | **Printing** | Built `--disable-cups`; `GtkPrint` is unavailable. |
| 7 | **Session management (XSMP)** | Partial `_DT_SM_*` property sharing only; cross-process save/restore/logout coordination is incomplete. |
| 8 | **Minor** | XIM `delete_surrounding_text` ignored; Xft Render-level entry points are no-ops (inert — GTK2 uses pangocairo). |

**XSettings caveats.** The shim publishes a *config file*, so a session has to
provide it (and a MATE-settings bridge would generate one, or relay the daemon's
`_XSETTINGS_SETTINGS` through the broker). Reload is event-driven rather than
woken by a timer. See `xlib-wayland/docs/XSETTINGS-STATUS.md`.

### Inherent to the in-process design (documented non-goals)

No cross-process `XSendEvent`; no shared window tree or global root properties
except what the broker/`smprops` republishes; each process is its own window
manager and the compositor (or CoW) provides the real WM role. These are not
"bugs to fix" — they are why the broker exists.

### App-level blockers (not GTK2 port limits)

Remaining MATE components need era `libnotify`/`upower`/`polkit`, Python 2
(`mozo`, `python-caja`) or proprietary code (`caja-dropbox`). See
[MATE-STATUS.md](MATE-STATUS.md).
