# Input — pointer, popups and menus

The shim (in `xlib-wayland`) turns Wayland `wl_pointer`/`wl_keyboard` events
into X events. Two areas need care: how a `wl_pointer` leave/enter burst is
folded into X crossing events, and how pointer grabs are reported.

## Popup / menu focus bursts

While the pointer is inside a nested popup (a menu's submenu) the compositor
reports the whole chain — *application toplevel → parent menu → submenu* — as
a leave/enter burst on essentially every motion, and the ancestor enters carry
stale coordinates (the parent menu's land on its **first item**). Acting on
each event independently made GTK re-select that item, which deselected the
item whose submenu was open and popped the submenu down: the "moving the mouse
in a submenu changes the selection in the parent menu" symptom.

The shim buffers the burst while a menu is open (`open_menu`) and, once the
Wayland dispatch settles, moves the pointer focus **only to the deepest popup
entered** (`mw_input_settle`, called after each dispatch in `wl.c` and from
`XSync`). The last event of a burst is not reliable; the deepest popup is. A
burst that enters only an ancestor (the pointer really moving back to the
parent menu) focuses that ancestor, and a burst that leaves everything clears
the focus. Ordinary window focus behaviour is untouched: the deferral applies
only while `open_menu` is set.

Crossing-event coordinates are computed in the coordinate space of the window
the event is delivered to (`ptr_in_win_space`), not reused from whatever
toplevel the pointer happens to be over — a grab leaving a menu, or a menu
leaving for its submenu, otherwise reports the leave at a bogus position.

Commit: `xlib-wayland` `d139912`.

## Window-manager messages (EWMH)

The shim is also the window manager for its X clients. A client asking to
change a window state sends an EWMH `_NET_WM_STATE` ClientMessage to the root
window; `XSendEvent` consumes it and applies it. **Fullscreen** is translated
straight to `xdg_toplevel_set_fullscreen`/`unset_fullscreen` — the compositor
does the real work — and the shim drops/restores its client-side titlebar,
resizes to the screen or back to the saved size, and mirrors the state into the
window's `_NET_WM_STATE` property so GDK (`gdk_window_get_state`) and the
application can read it. **Maximize** works the same way
(`xdg_toplevel_set_maximized`/`unset_maximized`); xdg-shell has only a full
maximize and GDK sends both `MAXIMIZED_VERT`/`HORZ`, so either atom maximises.
The states the compositor reports in `xdg_toplevel.configure` drive the same
tracking, so a maximize from the window chrome keeps the X property in sync
too. The remaining states (above, sticky, …) are accepted and ignored rather
than left half-applied. Commits: `fd859db`, `9e09b04`.

## Grabs

`XGrabPointer`/`XUngrabPointer` are modelled faithfully, including the
`NotifyGrab`/`NotifyUngrab` crossing pairs and `owner_events` delivery, which
Motif's menu buttons and `XmMenuButton` arming depend on.

## Verifying

GTK2's gtester suite (14/14) and gtk-demo (`scripts/test-gtk-demo.sh`) cover
the input paths; the menu behaviour itself is checked by hand against a
submenu with several items (`File → Open Recent`, etc.).
