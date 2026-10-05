# GIMP 2.10 on Wayland — status

GIMP 2.10 (the last GTK2 GIMP) is the final target: build it unmodified against
the `xlib-wayland` shim and run it with no XWayland, both nested in labwc and
directly on the host compositor.

## The GLib bump GIMP forces

GIMP 2.10 requires **GLib >= 2.54.2** (2.10.20+ requires 2.56.2).  That is
incompatible with the MATE 1.10-era stack this tree originally pinned (GLib
2.48.2).  MATE 1.10 sets the other bound: it defines compatibility functions
GLib added in 2.60 (`g_strv_equal`), so GLib must stay **< 2.60**.  The common
denominator — and GIMP 2.10's own era — is **GLib 2.56.2**, now pinned in
`versions.lock`.

The whole era stack, GTK+ 2.24.33 and the gtkmm stack rebuild against it
unchanged, and the GTK2 gtester suite is still 14/14.

## The GIMP dependency stack

Built by `scripts/build-deps.sh` into `$GTK2_PREFIX`, on top of the existing
era stack (table in `docs/MATE-STATUS.md`):

| Library | Version | Why |
|---|---|---|
| babl | 0.1.94 | GIMP's pixel-format conversion |
| GEGL | 0.4.30 | GIMP 2.10's processing engine |
| json-glib | 1.4.4 | GEGL/GIMP hard dependency |
| libmypaint | 1.6.1 | the MyPaint brush tool |
| mypaint-brushes | 1.3.0 | MyPaint brush preset data |
| gexiv2 | 0.14.3 | the metadata editor |
| glib-networking | 2.56.1 | GIO TLS backend (GIMP configures a live TLS check) |
| poppler-glib | 0.50.0 | raised from 0.42 for GIMP's PDF import (atril is fine) |

Host libraries with no GLib dependency are used directly: Exiv2 (0.28),
libtiff, libjpeg, libpng, lcms2, the CL headers.

## Building and running

```sh
scripts/build-deps.sh               # includes babl/GEGL/.../glib-networking
scripts/build-gtk2.sh
scripts/build-gimp.sh               # GIMP 2.10.24 -> $GTK2_PREFIX
scripts/run-app.sh gimp             # nested labwc
env -u DISPLAY tests/out/run-gimp.sh   # directly on the host compositor
```

`scripts/run-app.sh` grew `APP_RUN_TIMEOUT` (capture mode) so large, slow
applications like GIMP can be given enough time to map their window.

## Dependency-source accommodations

These are build-system mismatches between 2018-2021 sources and 2026 tooling,
not shim changes.  Each is documented where it is applied in
`scripts/build-deps.sh` / `scripts/lib.sh`:

* **Archive sources.** GNOME's release tarballs for babl, GEGL and GIMP are not
  being served right now (`download.gnome.org`'s `babl/` and `gegl/`
  directories 404).  GIMP comes from `download.gimp.org`; babl/GEGL come from
  GNOME GitLab's generated archives via `fetch_tar_named`, which renames the
  extracted `project-TAG` directory.
* **babl and git.** babl's `meson.build` runs `git describe` unconditionally
  and errors outside a repository; `gitify` gives the extracted archive a
  one-commit repository (the release tarball would ship a generated
  `git-version.h` instead).
* **GEGL's OpenCL headers.** The GitLab archive omits the generated
  `opencl/*.cl.h` kernels that the release tarball ships; they are regenerated
  with GEGL's own `opencl/cltostring.py`.
* **libmypaint's config.h.** The 1.6.1 tarball ships a release-time `config.h`
  with `MYPAINT_CONFIG_USE_GLIB 1`; in an out-of-tree build
  `#include "config.h"` finds it (the includer's directory is searched first)
  instead of the generated one, so it is removed first.
* **json-glib.** 1.4's autotools build insists on the `mesontest` program
  (meson's pre-1.0 `meson test`); build it with meson.
* **compiler dialect.** GCC 16 defaults to C23, where `bool` is a keyword, and
  GIMP 2.10 still uses `bool` as an identifier — so GIMP's C is built with
  `-std=gnu11`.  It also needs `-D_GNU_SOURCE` for `Dl_info`.

## Verified

* GIMP 2.10.24 builds and installs into `$GTK2_PREFIX` (`build-gimp.sh`).
* It runs in nested labwc and directly against the host Wayland compositor
  (the shim speaking xdg-shell/decoration to the real compositor), renders its
  UI, and was exercised interactively.
* GIMP's startup warnings are understood: `bogus monitor resolution ... using
  96 dpi` (the shim does not report a real DPI) and `gdk_window_set_icon_list:
  icons too large` are cosmetic.

## Not yet looked at

* GIMP's X11-native paths that the current stack has not exercised: cross-
  process clipboard/DnD, XDND, and XSM session management (in-process Xlib is a
  stated non-goal).
* A real screenshot of GIMP under the headless compositor (the capture path
  needs a longer budget than the default; nested/host runs are the primary
  verification).
