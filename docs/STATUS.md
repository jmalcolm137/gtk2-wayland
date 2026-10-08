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
| SHAPE / MIT-SHM / Sync | ✅ | shim `libXext` facade (with faithful `extutil` for libXi/libXtst): shaped windows, shared-memory images, frame-sync counters — shim's `docs/XEXT-STATUS.md` |
| Transparency / RGBA windows | ✅ | shim stands in as the X compositor (`_NET_WM_CM_S0`) with a depth-32 ARGB visual and alpha-preserving presentation — shim's `docs/COMPOSITE-STATUS.md` |
| XInput2 touch | ✅ | shim reports devices/classes from the Wayland seat and bridges touch to `XI_TouchBegin/Update/End` (GTK2 itself uses core input) — shim's `docs/XI2-STATUS.md` |
| Session management | ✅ | X11 session protocol (`WM_SAVE_YOURSELF`/`WM_DELETE_WINDOW`) relayed across processes + CDE `_DT_SM_*` sharing; XSMP itself is ICE/libSM — shim's `docs/SESSION-STATUS.md` |
| Accessibility (ATK/AT-SPI) | ✅ | GAIL + an era-matched at-spi2 bridge; the tree is published over D-Bus and found by an AT-SPI client — [A11Y-STATUS.md](A11Y-STATUS.md). Input synthesis is Wayland's. |
| Printing (GtkPrint/CUPS) | ✅ | GTK2 built with CUPS; `GtkPrint` renders through cairo and the `file`/`lpr`/`cups` backends do the I/O (CUPS is IPP, display-server-independent). `scripts/test-print.sh` |
| Xinerama | ✅ | shim `libXinerama` facade reports the Wayland output; GTK2 is built with Xinerama so GDK enumerates monitors through it |
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
| 3 | **XEmbed** | Cross-process embedding is impossible under Wayland (no cross-client surface embedding) and GTK2's `GtkPlug` refuses same-process embedding, so `GtkPlug`/`GtkSocket` are a **documented non-goal**. The shim's primitives (`XReparentWindow` + `ReparentNotify`, `_XEMBED` delivery, `_XEMBED_INFO`) work for same-process embedders — shim's `docs/XEMBED-STATUS.md`. |
| 4 | **Optional extensions** | **Xfixes, Xcursor, SHAPE, MIT-SHM, Sync, XDamage, XComposite, XInput2 device classes + pointer/keyboard/touch events, and Xinerama** are provided (shim facades/backends), so clipboard owner-change tracking, themed cursors, shaped windows, shared-memory images, frame-sync counters, RGBA/transparent composited windows, Wayland touch and pointer/keyboard XI2 events, and monitor enumeration work. Still absent: XInput2 tablet/tool classes (Wayland exposes tablets only via `zwp_tablet`). GTK2 uses core input (built `--with-xinput=no`). |
| 5 | **Accessibility** | **Done** (ATK/AT-SPI over D-Bus): `scripts/build-a11y.sh` builds an era-matched at-spi2 against the GTK2 stack (the host's needs glib ≥ 2.78) and installs the GTK2 bridge module; `scripts/test-a11y.sh` verifies an AT-SPI client finds a widget. Input synthesis is the compositor's (Wayland). See [A11Y-STATUS.md](A11Y-STATUS.md). |
| 6 | **Printing** | **Done**: GTK2 is built with CUPS (`--enable-cups`), so `GtkPrint` works and the `file` (PDF/PS), `lpr` and `cups` backends are all present. Printing is CUPS/IPP over a socket, not a display-server protocol — there is no Wayland integration to do (the modern `xdg-desktop-portal` Print portal is GTK3/4). `scripts/test-print.sh` exports a PDF and checks the CUPS backend. |
| 7 | **Session management (XSMP)** | The **X11 session protocol** is now relayed across processes (`WM_SAVE_YOURSELF`/`WM_DELETE_WINDOW` via `mw-session`), and the CDE `_DT_SM_*` properties are shared. XSMP itself is an ICE/libSM protocol outside libX11; `SESSION_MANAGER`/libSM are the app/session-manager's side. |
| 8 | **Minor** | **Done**: XIM `delete_surrounding_text` is realised as Backspace/Delete key events to the focused widget (XIM has no such request); the Xft Render-level entry points (`XftGlyphSpecRender`/`CharSpecRender`/…FontSpecRender) now draw through the destination Picture instead of being no-ops (verified by the shim's `tests/xftrender_x.c`). |

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
