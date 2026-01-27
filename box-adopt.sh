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

  # 1) Fast path: owners db (files/symlinks tracked here)
  if type owners_db >/dev/null 2>&1 && type owners_get >/dev/null 2>&1; then
    owners_db
    local o=""
    o="$(owners_get "$path")" || true
    if [ -n "${o:-}" ]; then
      printf "%s\n" "$o"
      return 0
    fi
  fi

  # 2) Scan installed records' files manifests (covers dirs too)
  local rel mf pkgid
  rel="./${path#/}"

  if [ -d "${DB:-}/installed" ]; then
    for mf in "$DB/installed"/*/files; do
      [ -f "$mf" ] || continue
      if grep -qxF "$rel" "$mf"; then
        pkgid="$(basename "$(dirname "$mf")")"
        printf "%s\n" "$pkgid"
        return 0
      fi
    done
  fi

  # 3) Legacy fallback (old layout)
  if [ -d "${MAN:-}" ]; then
    for mf in "$MAN"/*.files; do
      [ -f "$mf" ] || continue
      if grep -qxF "$rel" "$mf"; then
        printf "%s\n" "$(basename "$mf" .files)"
        return 0
      fi
    done
  fi

  return 1
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

  # refuse if already adopted/installed (new layout)
  local inst="$DB/installed/$PKGID"
  [ ! -d "$inst" ] || die "already installed/adopted: $PKGID"

  # refuse if some other package already owns this path
  local owner=""
  if owner="$(box_own "$path" 2>/dev/null)"; then
    die "path is already owned by: $owner"
  fi

  # create install record dir
  command install -d -- "$DB/installed" "$inst"

  local rel d

  rel="${path#/}"  # drop leading /

  # temp files
  local tmp_files tmp_payload tmp_dirs
  tmp_files="$(mktemp -p "${TMPDIR:-/tmp}" "box-adopt.${PKGID}.files.XXXXXX")"
  tmp_payload="$(mktemp -p "${TMPDIR:-/tmp}" "box-adopt.${PKGID}.payload.XXXXXX")"
  tmp_dirs="$(mktemp -p "${TMPDIR:-/tmp}" "box-adopt.${PKGID}.dirs.XXXXXX")"
  trap 'rm -f -- "$tmp_files" "$tmp_payload" "$tmp_dirs" 2>/dev/null || true' RETURN

  : > "$tmp_files"
  : > "$tmp_payload"
  : > "$tmp_dirs"

  # Build files list: parent dirs + the path itself (./-prefixed)
  d="$rel"
  while :; do
    d="$(dirname "$d")"
    [ "$d" = "." ] && break
    printf "./%s\n" "$d" >> "$tmp_files"
  done
  printf "./%s\n" "$rel" >> "$tmp_files"
  LC_ALL=C sort -u "$tmp_files" > "$inst/files"

  # Build payload: only if the target is a file or symlink (not directory)
  # (We also skip info dir, same as everywhere else.)
  if [ "$path" != "/usr/share/info/dir" ]; then
    if [ -L "$path" ] || [ -f "$path" ]; then
      printf "./%s\n" "$rel" > "$tmp_payload"
    fi
  fi
  # ensure payload file exists even if empty
  : > "$inst/payload"
  if [ -s "$tmp_payload" ]; then
    LC_ALL=C sort -u "$tmp_payload" > "$inst/payload"
  fi

  # Build dirs: include only entries that are real dirs on disk, deepest-first
  # We derive from files manifest to keep behavior consistent.
  while IFS= read -r p; do
    p="${p#./}"
    [ -n "$p" ] || continue
    # abs path
    if [ -d "/$p" ] && [ ! -L "/$p" ]; then
      printf "./%s\n" "$p" >> "$tmp_dirs"
    fi
  done < "$inst/files"
  # sort deepest-first
  : > "$inst/dirs"
  if [ -s "$tmp_dirs" ]; then
    LC_ALL=C sort -u "$tmp_dirs" | LC_ALL=C sort -r > "$inst/dirs"
  fi

  # Write meta
  local ts meta_file
  ts="$(date -Is 2>/dev/null || date)"
  meta_file="$inst/meta"
  {
    echo "PKG=$PKG"
    echo "VER=$VER"
    echo "PKGID=$PKGID"
    echo "DATE=$ts"
    [ -n "$SRC" ] && echo "SRC=$SRC"
    [ -n "$DESC" ] && echo "DESC=$DESC"
  } > "$meta_file"

  # Register ownership for payload (files/symlinks) so future upgrades/removals are sane
  if type owners_db >/dev/null 2>&1 && type owners_set >/dev/null 2>&1; then
    owners_db
    if [ -s "$inst/payload" ]; then
      while IFS= read -r p; do
        p="${p#./}"
        [ -n "$p" ] || continue
        [ "/$p" = "/usr/share/info/dir" ] && continue
        owners_set "/$p"
      done < "$inst/payload"
    fi
  fi

  echo "box: ok: adopted $PKGID ($path)"
}
