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

**Early.** The harness and the gap analysis come first; the toolkit follows.

| M | Scope | State |
|---|---|---|
| **M0** | repo, docs, version pinning, nested-labwc test harness | ✅ done |
| **M1** | GTK+ 2.24.33 configures, builds and installs against the shim, unmodified | ✅ done |
| **M2** | a GTK2 window opens, draws and takes real input under the shim | ✅ done |
| **M3** | GTK2's own GTest suite runs under `gtester` in nested labwc | 🚧 12/14 programs pass; the 2 failures are the synthetic-input tests, explained in [docs/TEST-RESULTS.md](docs/TEST-RESULTS.md) |
| **M4** | MATE 1.10 applications build unmodified and run in labwc | 🚧 caja, eom, engrampa, pluma, mate-terminal and the wider set build and render; see [docs/MATE-STATUS.md](docs/MATE-STATUS.md) |
| **M5** | GIMP 2.10 builds unmodified and runs in labwc | ⬜ |

The shim now provides the full **Render** extension and it is on by default
(text renders pixel-correctly); `MW_RENDER=0` selects cairo's core-protocol
fallback. See [docs/RENDER-STATUS.md](docs/RENDER-STATUS.md).

GTK2 is built **unmodified** against the MATE 1.10-era supporting stack (GLib
2.48, ATK 2.18, Pango 1.38, gdk-pixbuf 2.34), the common era for GTK2, MATE 1.10
and GIMP 2.10, so that the only non-period-correct component in the process is
our `libX11` shim. The shim's own status (libXt, Open Motif, XV and NEdit
running unmodified) is recorded in
[`xlib-wayland/README.md`](https://github.com/jmalcolm137/xlib-wayland).

## Quick start

```sh
# 0. one-time: fetch sources, and stage a nested labwc (no root needed)
scripts/fetch-sources.sh

# 1. build & install the shim (xlib-wayland) into the prefix
scripts/build-shim.sh

# 2. build the MATE 1.10-era supporting stack (GLib 2.48, ATK, Pango,
#    gdk-pixbuf) into the prefix, so GTK2 sees period-correct libraries
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
│   └── run-tests-labwc.sh    # gtester inside nested labwc
└── docs/                     # findings and gap reports (as they accumulate)
```

## License

MIT — see [LICENSE](LICENSE). Upstream GTK+ 2 and `xlib-wayland` keep their own
licenses; this tree contains only build orchestration, configuration and
documentation.
