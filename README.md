# GTK+ 2 on Wayland

Run **GTK+ 2** — and, after it, the **MATE 1.10** desktop and **GIMP 2.10** —
as native Wayland applications, by building the stock, unmodified GTK+ 2
sources against [`xlib-wayland`](https://github.com/jmalcolm137/xlib-wayland):
a Wayland-native, ABI-compatible implementation of `libX11`.

```
   GTK+ 2 application        (unmodified)
   libgtk-x11-2.0 · libgdk-x11-2.0 · cairo-xlib · libXft · libXrender · libXi …
   libX11  ← xlib-wayland    (the only platform-specific layer)
   Wayland  (wl_surface · xdg_toplevel · xdg_popup · wl_shm · wl_seat …)
```

This is **not** Xwayland. A GTK2 program built and run this way is a real
Wayland client: no X server, no X11 wire protocol, no `:0` socket.

The project follows the same pattern the shim already proves for the
Xt/Motif stack (XV, NEdit): *the platform is the only layer that changes.*
GTK2 stays pristine; every shim accommodation is made in `xlib-wayland` and
pushed there.

## Where changes live

`xlib-wayland` is a **separate upstream project** and is where every shim
accommodation for GTK2 belongs. This repository only:

* orchestrates building GTK2 against the shim,
* carries the **test harness** — GTK2's own GTest suite driven by `gtester`
  inside a nested **labwc** compositor,
* documents the design, the gap analysis, and the milestone plan,
* pins the tested shim revision in [`versions.lock`](versions.lock).

Do not fork or patch GTK2. Do not patch the shim from this tree. If a change is
needed, reproduce it against the shim, fix it in `xlib-wayland`, push it, and
record the revision here.

## Status

| M | Scope | State |
|---|---|---|
| **M0** | repo, docs, version pinning, nested-labwc test harness | ✅ done |
| **M1** | GTK+ 2.24.33 configures, builds and installs against the shim, unmodified | ✅ done |
| **M2** | a GTK2 window opens, draws and takes real input under the shim | ✅ done |
| **M3** | GTK2's own GTest suite runs under `gtester` in nested labwc | ✅ 14/14 |
| **M4** | MATE 1.10 applications build unmodified and run in labwc | 🚧 29 components build and run; the rest are blocked on era libraries, Python 2 or proprietary code — [docs/MATE-STATUS.md](docs/MATE-STATUS.md) |
| **M5** | GIMP 2.10 builds unmodified and runs with no XWayland | ✅ GIMP 2.10.24 builds, runs and renders — [docs/GIMP-STATUS.md](docs/GIMP-STATUS.md) |

The shim provides the full **Render** extension, on by default (text renders
pixel-correctly); `MW_RENDER=0` selects cairo's core-protocol fallback. GTK2
gtester is 14/14 and gtk-demo matches the core fallback with Render on.

GTK2's input method works as well: with `GTK_IM_MODULE=xim`, `im-xim` drives the
shim's XIM, which is a real bridge to the compositor's `zwp_text_input_v3`.
`scripts/test-ime.sh` commits text into a real `GtkEntry` through that path
(using the headless compositor's scripted input method). Dead-key and multi-key
compose sequences are handled by the shim's keymap.

**The current state and the gap list live in [docs/STATUS.md](docs/STATUS.md).**
Notable shim work landed along the way, each with its own note:

* the Render path's ruler-tick clip bug — [docs/RENDER-STATUS.md](docs/RENDER-STATUS.md)
* nested-popup / menu focus handling — [docs/INPUT-STATUS.md](docs/INPUT-STATUS.md)
* EWMH `_NET_WM_STATE` fullscreen and maximize — [docs/INPUT-STATUS.md](docs/INPUT-STATUS.md)
* XIM as a real input-method bridge — the shim's `docs/IME-STATUS.md`
* dead-key/compose sequences — the shim's keymap
* XSETTINGS as a shim-side manager (theme/font/Xft from a config file) — the
  shim's `docs/XSETTINGS-STATUS.md`, exercised by `scripts/test-settings.sh`
* cross-process X selections and session-manager properties — the shim's
  `broker.c` / `smprops.c` (`XLIB_WAYLAND_SHARE_SELECTIONS` /
  `XLIB_WAYLAND_SHARE_PROPERTIES`); without them, an in-process X server cannot
  see another process's selection or `_DT_SM_*` state

The input and bridge items above let a GTK2 application's own submenus and
window-state commands behave normally rather than only the compositor chrome;
the broker items let the MATE/CDE pieces that expect a shared server (clipboard,
session state) work across processes.

GTK2 is built **unmodified** against a single supporting stack shared with
MATE 1.10 and GIMP 2.10: **GLib 2.56.2** (GIMP 2.10.20+ needs ≥ 2.56.2; MATE
1.10 defines compatibility functions GLib added in 2.60, so it must stay
< 2.60), with ATK 2.18, Pango 1.38 and gdk-pixbuf 2.34. That is the common era
for the three, so the only non-period-correct component in the process is our
`libX11` shim. The shim's own status (libXt, Open Motif, XV and NEdit running
unmodified) is recorded in
[`xlib-wayland/README.md`](https://github.com/jmalcolm137/xlib-wayland).

## Quick start

```sh
# 0. one-time: fetch sources, and stage a nested labwc (no root needed)
scripts/fetch-sources.sh

# 1. build & install the shim (xlib-wayland) into the prefix
scripts/build-shim.sh

# 2. build the GTK2/MATE/GIMP common supporting stack (GLib 2.56.2, ATK,
#    Pango, gdk-pixbuf) into the prefix, so GTK2 sees period-correct libraries
scripts/build-deps.sh

# 3. build stock GTK+ 2.24.33 against the prefix
scripts/build-gtk2.sh

# 4. run GTK2's GTest suite under gtester inside nested labwc
scripts/run-tests-labwc.sh
```

Everything installs relocatably under `$GTK2_PREFIX`
(default `$HOME/.local/gtk2-wayland`), so **no root is required**.

## The test harness

GTK2's test suite is a set of GTest binaries under `tests/`, normally driven by
`gtester`. We run them inside a **nested labwc** session so that the whole
GDK→libX11-shim→Wayland path is exercised, not just the toolkit in isolation:

```
your desktop session (KWin, sway, …)
   └─ labwc            (nested, WLR_BACKENDS=wayland; XWayland disabled)
        └─ gtester …   (WAYLAND_DISPLAY = labwc's socket)
             └─ GTK2 test binaries
```

* `scripts/setup-labwc.sh` stages `labwc` + `libsfdo` from distro packages into
  a local prefix — no root. labwc's XWayland is turned off: the point is to run
  natively.
* `scripts/run-tests-labwc.sh` starts the nested compositor with
  `labwc -S '<gtester command>'`, so the compositor lives exactly as long as the
  test run.
* `scripts/gtester` is a small, MIT-licensed `gtester`-compatible driver for
  GTest binaries, used when the host GLib no longer ships the original (it was
  removed upstream after GLib 2.60). A real `gtester` is used if one is present.

## Environment

| Variable | Default | Meaning |
|---|---|---|
| `GTK2_PREFIX` | `$HOME/.local/gtk2-wayland` | install prefix (shim + GTK2) |
| `GTK2_CACHE` | `$HOME/.cache/gtk2-wayland` | downloaded / cloned sources |
| `GTK2_SRC` | `$GTK2_CACHE/src/gtk+-2.24.33` | pristine GTK2 tree |
| `GTK2_BUILD` | `$GTK2_PREFIX/build/gtk+-2.24.33` | out-of-tree GTK2 build |
| `XLIB_WAYLAND` | sibling `../xlib-wayland` | shim checkout |
| `XLIB_WAYLAND_REPO` | `github.com/jmalcolm137/xlib-wayland` | shim upstream |
| `XLIB_WAYLAND_REF` | `main` | shim revision to build |
| `LABWC_PREFIX` | `$HOME/.local/labwc-wayland` | local labwc staging prefix |
| `JOBS` | `nproc` | parallel build jobs |

## Repository layout

```
gtk2-wayland/
├── DESIGN.md                 # architecture, gap analysis, milestones
├── README.md                 # this file
├── LICENSE                   # MIT
├── versions.lock             # pinned upstream revisions
├── config/labwc/             # nested-compositor configuration
├── scripts/
│   ├── lib.sh                # shared env + logging
│   ├── fetch-sources.sh      # GTK2 tarball + labwc packages (+ shim checkout)
│   ├── setup-labwc.sh        # stage a nested labwc, no root
│   ├── build-shim.sh         # build & install xlib-wayland
│   ├── build-gtk2.sh         # build stock GTK+ 2.24.33 against the shim
│   ├── gtester               # gtester-compatible GTest driver (MIT)
│   ├── run-tests-labwc.sh    # gtester inside nested labwc
│   ├── test-ime.sh           # GTK2 im-xim end-to-end under the headless compositor
│   └── test-settings.sh      # GTK2 reads the shim's XSETTINGS
└── docs/                     # findings, status and gap reports
    ├── STATUS.md             # consolidated status + gap list
    ├── GTK2-GAP-ANALYSIS.md  # the authoritative X11 requirement inventory
    ├── TEST-RESULTS.md       # gtester results
    ├── RENDER-STATUS.md      # Render path
    ├── INPUT-STATUS.md       # pointer/popup/EWMH input
    ├── GTK-DEMO-STATUS.md    # gtk-demo render-vs-fallback
    ├── MATE-STATUS.md
    └── GIMP-STATUS.md
```

## License

MIT — see [LICENSE](LICENSE). Upstream GTK+ 2 and `xlib-wayland` keep their own
licenses; this tree contains only build orchestration, configuration and
documentation.
