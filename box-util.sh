# ~/src/box/box-util.sh
#!/bin/bash
set -euo pipefail
export LC_ALL=C

die(){ echo "box: $*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "run as root (or via sudo)."
}

usage() {
  cat <<USAGE
box - ls-box source package tool

Usage:
  box init
  box new (creates recipe for package)
  box add <recipe> [--force]
  box install [--dry-run|-n] <pkg> [--force]
  box rm <name-ver>
  box deps <pkg>
  box own <absolute-path>
  box list
  box available
  box search <term>
  box info <name-ver>
  box world <listfile> [--force]
  box adopt <name> <ver> <absolute-path> [--src <path>] [--desc <text>]

Recipe conventions:
  A recipe is a shell file that defines:
    PKG=name
    VER=version
    SRC=/sources/pkg-ver.tar.xz
    configure() { ... }           (optional)
    build() { ... }               (optional)
    pkg_install() { ... }         (required; must install into "\$DESTDIR")
USAGE
}
