#!/usr/bin/env bash
# lib.sh — shared environment and logging for gtk2-wayland scripts.
#
# Source this; do not execute it:
#     . "$(dirname "$0")/lib.sh"
#
# Every path is overridable from the environment.  Nothing here requires root.

# shellcheck shell=bash

GTK2_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GTK2_ROOT

: "${GTK2_PREFIX:=$HOME/.local/gtk2-wayland}"
: "${GTK2_CACHE:=$HOME/.cache/gtk2-wayland}"
: "${GTK2_DL:=$GTK2_CACHE/dl}"

# --- the toolkit under test --------------------------------------------------
: "${GTK2_VERSION:=2.24.33}"
: "${GTK2_TARBALL:=gtk+-${GTK2_VERSION}.tar.xz}"
: "${GTK2_URL:=https://download.gnome.org/sources/gtk+/2.24/${GTK2_TARBALL}}"
: "${GTK2_SRC:=$GTK2_CACHE/src/gtk+-${GTK2_VERSION}}"
: "${GTK2_BUILD:=$GTK2_PREFIX/build/gtk+-${GTK2_VERSION}}"

# --- the shim ----------------------------------------------------------------
: "${XLIB_WAYLAND:=$GTK2_ROOT/../xlib-wayland}"
: "${XLIB_WAYLAND_REPO:=https://github.com/jmalcolm137/xlib-wayland.git}"
: "${XLIB_WAYLAND_REF:=main}"

# --- the nested compositor ---------------------------------------------------
: "${LABWC_PREFIX:=$HOME/.local/labwc-wayland}"
: "${LABWC_VERSION:=0.20.2}"
: "${LABWC_SRC:=$LABWC_PREFIX/src/labwc-${LABWC_VERSION}}"
: "${LABWC_BUILD:=$LABWC_PREFIX/build/labwc}"

: "${JOBS:=$(nproc 2>/dev/null || echo 4)}"
: "${RUNTIME_DIR:=$HOME/.local/gtk2-wayland/run}"

export GTK2_PREFIX GTK2_CACHE GTK2_DL GTK2_VERSION GTK2_SRC GTK2_BUILD
export XLIB_WAYLAND XLIB_WAYLAND_REPO XLIB_WAYLAND_REF
export LABWC_PREFIX LABWC_VERSION LABWC_SRC LABWC_BUILD
export JOBS RUNTIME_DIR

# ------------------------------------------------------------------ logging --

if [ -t 2 ]; then
    _c_ok=$'\033[1;32m'; _c_warn=$'\033[1;33m'; _c_err=$'\033[1;31m'
    _c_dim=$'\033[2m'; _c_off=$'\033[0m'
else
    _c_ok=; _c_warn=; _c_err=; _c_dim=; _c_off=
fi

log()  { printf '%s==>%s %s\n' "$_c_ok"   "$_c_off" "$*" >&2; }
step() { printf '\n%s==> %s%s\n' "$_c_ok" "$*" "$_c_off" >&2; }
warn() { printf '%s!!%s %s\n'  "$_c_warn" "$_c_off" "$*" >&2; }
die()  { printf '%sxx%s %s\n'  "$_c_err"  "$_c_off" "$*" >&2; exit 1; }
dim()  { printf '%s%s%s\n' "$_c_dim" "$*" "$_c_off" >&2; }

have() { command -v "$1" >/dev/null 2>&1; }

# run_dir — create and enter a private runtime dir, returning its path.
# Nested Wayland compositors need an XDG_RUNTIME_DIR that is theirs.
make_runtime_dir() {
    mkdir -p "$RUNTIME_DIR"
    chmod 700 "$RUNTIME_DIR"
    printf '%s' "$RUNTIME_DIR"
}

# load_versions — source versions.lock (repository pins).
load_versions() {
    local f="$GTK2_ROOT/versions.lock"
    [ -f "$f" ] && . "$f"
    export XLIB_WAYLAND_REPO XLIB_WAYLAND_REF GTK2_VERSION
}

# fetch_tar — download (once) and extract an archive into $GTK2_CACHE/src;
# echoes the source directory.  The cached copy is named <name> (the URL's
# extension is not preserved).  The archive's top-level directory must be
# <name>.
fetch_tar() { # name url
    local name="$1" url="$2" tar="$GTK2_DL/$1"
    mkdir -p "$GTK2_DL" "$GTK2_CACHE/src"
    [ -f "$tar" ] || { log "downloading $(basename "$url")"; curl -fsSL -o "$tar" "$url" || die "download failed: $url"; }
    rm -rf "$GTK2_CACHE/src/$name"
    tar xf "$tar" -C "$GTK2_CACHE/src"
    printf '%s' "$GTK2_CACHE/src/$name"
}

# fetch_tar_named — like fetch_tar, but tolerates an archive whose top-level
# directory is not exactly <name> (GNOME GitLab's generated archives are
# <project>-<TAG>).  The single extracted directory is renamed to <name>.
fetch_tar_named() { # name url
    local name="$1" url="$2" tar="$GTK2_DL/$1" inner tmp="$GTK2_CACHE/src/.$1.extract"
    mkdir -p "$GTK2_DL" "$GTK2_CACHE/src"
    [ -f "$tar" ] || { log "downloading $(basename "$url")"; curl -fsSL -o "$tar" "$url" || die "download failed: $url"; }
    rm -rf "$GTK2_CACHE/src/$name" "$tmp"
    mkdir -p "$tmp"
    tar xf "$tar" -C "$tmp"
    inner="$(find "$tmp" -mindepth 1 -maxdepth 1 | head -1)"
    [ -n "$inner" ] || { rm -rf "$tmp"; die "empty archive: $url"; }
    mv "$inner" "$GTK2_CACHE/src/$name"
    rm -rf "$tmp"
    printf '%s' "$GTK2_CACHE/src/$name"
}

# gitify dir — turn an extracted archive into a one-commit git checkout.  Some
# projects (babl) run `git describe` unconditionally in their meson.build and
# error when the source is not a repository; the release tarball ships the
# generated git-version.h instead, which GNOME's GitLab archives omit.
gitify() {
    local dir="$1"
    [ -d "$dir/.git" ] && return 0
    ( cd "$dir" && git init -q && git add -A >/dev/null 2>&1 && \
      git -c user.name=build -c user.email=build@localhost \
          commit -qm import >/dev/null 2>&1 ) || die "gitify failed: $dir"
}

# Prefer the system automake py-compile: the older in-tree copies use the `imp`
# module, removed in Python 3.12.
SYS_PY_COMPILE=""
for _p in /usr/share/automake-*/py-compile; do [ -x "$_p" ] && SYS_PY_COMPILE="$_p"; done
export SYS_PY_COMPILE

# use_prefix — put the built dependency stack (glib/atk/pango/gdk-pixbuf) and
# the shim first on the search paths, so builds and runs resolve against the
# prefix rather than the host.
use_prefix() {
    export PATH="$GTK2_PREFIX/bin:$PATH"
    export PKG_CONFIG_PATH="$GTK2_PREFIX/lib/pkgconfig:$GTK2_PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
    export LD_LIBRARY_PATH="$GTK2_PREFIX/lib:${LD_LIBRARY_PATH:-}"
}

# stage_host_pkg — download one distro package by name and extract it into the
# host-tools prefix ($GTK2_CACHE/hosttools).  Returns 1 on failure.
stage_host_pkg() {
    local name="$1" dir="$GTK2_CACHE/hosttools"
    local pkg="$GTK2_DL/$name.pkg.tar.zst" url
    mkdir -p "$dir" "$GTK2_DL"
    # Reuse the cache only if it really is this package.
    if [ -f "$pkg" ] && ! tar --zstd -xOf "$pkg" .PKGINFO 2>/dev/null \
            | grep -q "^pkgname = $name$"; then
        rm -f "$pkg"
    fi
    if [ ! -f "$pkg" ]; then
        # `pacman -Sp` lists dependencies too; select the requested package.
        url="$(pacman -Sp --print-format '%n %l' "$name" 2>/dev/null \
               | awk -v n="$name" '$1==n {print $2}' | head -1)"
        [ -n "$url" ] || return 1
        case "$url" in
            file://*) cp "${url#file://}" "$pkg";;
            *) curl -fsSL -o "$pkg" "$url" || return 1;;
        esac
        tar --zstd -xOf "$pkg" .PKGINFO 2>/dev/null \
            | grep -q "^pkgname = $name$" || { rm -f "$pkg"; return 1; }
    fi
    tar --zstd -xf "$pkg" -C "$dir" 2>/dev/null || tar -xf "$pkg" -C "$dir"
}

# stage_doc_tools — itstool (and the docbook DTD it uses) for MATE's translated
# XML documentation.  MATE's configure scripts treat it as mandatory even when
# we build no user guide.  Echoes the bin directory to add to PATH.
stage_doc_tools() {
    have itstool && return 0
    local dir="$GTK2_CACHE/hosttools"
    if [ ! -x "$dir/usr/bin/itstool" ]; then
        have pacman || die "itstool missing and no pacman to stage it"
        step "Staging itstool"
        stage_host_pkg itstool || die "could not stage itstool"
        stage_host_pkg docbook-xml >/dev/null 2>&1 || true
    fi
    printf '%s' "$dir/usr/bin"
}

# stage_glib_tools — some distributions (Arch among them) ship glib-mkenums,
# glib-genmarshal, gtester and gtester-report in a separate `glib2-devel`
# package rather than in glib2 itself.  GTK2's build and test harness need all
# four.  Stage that package into the cache and echo the bin directory to add to
# PATH, or echo nothing if the tools are already present.
stage_glib_tools() {
    if have glib-mkenums && have glib-genmarshal && have gtester; then
        return 0
    fi
    local dir="$GTK2_CACHE/hosttools"
    if [ ! -x "$dir/usr/bin/glib-mkenums" ]; then
        have pacman || die "glib-mkenums/gtester missing and no pacman to stage glib2-devel"
        step "Staging glib2-devel host tools (glib-mkenums, glib-genmarshal, gtester)"
        stage_host_pkg glib2-devel || die "could not stage glib2-devel"
    fi
    printf '%s' "$dir/usr/bin"
}

# stage_era_mkenums — MATE 1.10's enum-type sources were generated with the
# Perl glib-mkenums of its era, which processes the header list in the order
# given.  GLib 2.56's Python rewrite sorts its inputs, so a header that relies
# on an earlier one being included first (mate-utils' gdict-client-context.h
# needs GdictContext from gdict-context.h) is emitted out of order and the
# generated gdict-enum-types.c does not compile.  Extract the era tool from
# the pinned GLib 2.48 tarball and echo its directory.
stage_era_mkenums() {
    local dir="$GTK2_CACHE/hosttools/era-glib-tools"
    if [ ! -x "$dir/glib-mkenums" ]; then
        local tar="$GTK2_DL/glib-2.48.2"
        mkdir -p "$dir" "$GTK2_DL"
        [ -f "$tar" ] || curl -fsSL -o "$tar" \
            "https://download.gnome.org/sources/glib/2.48/glib-2.48.2.tar.xz" \
            || return 1
        tar xOf "$tar" glib-2.48.2/gobject/glib-mkenums.in 2>/dev/null \
            | sed -e "s|@PERL_PATH@|$(command -v perl)|" \
                  -e 's|@GLIB_VERSION@|2.48.2|' > "$dir/glib-mkenums" || return 1
        chmod +x "$dir/glib-mkenums"
    fi
    printf '%s' "$dir"
}
