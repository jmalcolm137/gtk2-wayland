# Printing (GtkPrint / CUPS)

Printing is **not a Wayland (or X11) protocol**.  `GtkPrint` is a normal GTK
subsystem: it renders pages through **cairo** and hands them to a **print
backend** that does the I/O itself.

## Backends

| Backend | Talks to | Notes |
|---|---|---|
| `file` | the filesystem | "Print to File" — PDF/PS via cairo, no server |
| `lpr` | `lp`/`lpr` | BSD printing |
| `cups` | **CUPS over IPP/HTTP** | printer discovery/queues; `CUPS_SERVER`, default `/run/cups/cups.sock` |

None of these goes through the shim, Xlib or Wayland.  The print dialog is an
ordinary GTK window, so it renders through the shim/compositor like any other;
the job itself is a network/socket operation to CUPS.

## In this port

GTK2 is configured with `--enable-cups` (libcups 2.4.x), so all three backends
are built and installed under
`$GTK2_PREFIX/lib/gtk-2.0/2.10.0/printbackends/` — including
`libprintbackend-cups.so`, which links `libcups`.

With a CUPS server reachable the dialog lists its printers; with none it still
offers "Print to File".  Nothing here needs a Wayland protocol, and the
`xdg-desktop-portal` Print portal (the modern sandboxed path) is GTK3/4 — GTK2
predates portals and uses CUPS directly.

## Test

`scripts/test-print.sh` builds `tests/printtest.c`, runs it under the headless
compositor with `GtkPrintOperation` in **EXPORT** mode, and checks the PDF it
writes (no print server needed); it also verifies the CUPS backend is installed
and links libcups.

## Not covered

* A live CUPS queue round-trip (submit job, check `lpstat`) — needs a running
  CUPS server in the test environment.
