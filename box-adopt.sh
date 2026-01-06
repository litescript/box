# ~/src/box/box-adopt.sh
#!/bin/bash
set -euo pipefail
export LC_ALL=C

box_own() {
  [ $# -eq 1 ] || die "own requires an absolute path"
  local path="$1"
  case "$path" in
    /*) ;;
    *) die "path must be absolute: $path" ;;
  esac

  local found="no" mf
  for mf in "$MAN"/*.files; do
    [ -f "$mf" ] || continue
    if grep -qx "./${path#/}" "$mf"; then
      echo "$(basename "$mf" .files)"
      found="yes"
    fi
  done
  [ "$found" = "yes" ] || exit 1
}

box_adopt() {
  need_root
  [ $# -ge 3 ] || die "usage: box adopt <name> <ver> <absolute-path> [--src <path>] [--desc <text>]"
  local PKG="$1" VER="$2" path="$3"; shift 3
  local PKGID="${PKG}-${VER}"

  case "$path" in
    /*) ;;
    *) die "path must be absolute: $path" ;;
  esac
  [ -e "$path" ] || die "path not found: $path"

  # parse optional flags
  local SRC="" DESC=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --src)
        [ $# -ge 2 ] || die "--src requires a value"
        SRC="$2"; shift 2
        ;;
      --desc)
        [ $# -ge 2 ] || die "--desc requires a value"
        DESC="$2"; shift 2
        ;;
      *)
        die "unknown option for adopt: $1"
        ;;
    esac
  done

  # refuse if already adopted/installed
  [ ! -f "$MAN/$PKGID.files" ] || die "manifest already exists: $MAN/$PKGID.files"
  [ ! -f "$META/$PKGID.meta" ] || die "meta already exists: $META/$PKGID.meta"

  # refuse if some other package already "owns" this path (direct call; single scan)
  local owner=""
  if owner="$(box_own "$path" 2>/dev/null)"; then
    die "path is already owned by: $owner"
  fi

  # Write manifest: include parent dirs + the path itself, all as ./-prefixed relpaths
  local mf tmp rel d
  mf="$MAN/$PKGID.files"
  tmp="/tmp/box-adopt.$PKGID.$$"
  : > "$tmp"

  rel="${path#/}"   # drop leading /
  # add parent directories, stopping before empty
  d="$rel"
  while :; do
    d="$(dirname "$d")"
    [ "$d" = "." ] && break
    echo "./$d" >> "$tmp"
  done

  # add the exact path entry
  echo "./$rel" >> "$tmp"

  # de-dupe and sort like other manifests
  LC_ALL=C sort -u "$tmp" > "$mf"
  rm -f "$tmp"

  # Write meta (reusing same format)
  local ts meta_file
  ts="$(date -Is 2>/dev/null || date)"
  meta_file="$META/$PKGID.meta"
  {
    echo "PKG=$PKG"
    echo "VER=$VER"
    echo "PKGID=$PKGID"
    echo "DATE=$ts"
    [ -n "$SRC" ] && echo "SRC=$SRC"
    [ -n "$DESC" ] && echo "DESC=$DESC"
  } > "$meta_file"

  echo "box: ok: adopted $PKGID ($path)"
}
