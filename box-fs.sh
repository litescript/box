# ~/src/box/box-fs.sh
#!/bin/bash
set -euo pipefail
export LC_ALL=C

stage_dir() {
  DESTDIR="/tmp/box-stage/$PKGID"
  rm -rf "$DESTDIR"
  command install -d "$DESTDIR"
}

write_meta() {
  local ts meta_file
  ts="$(date -Is 2>/dev/null || date)"
  meta_file="$META/$PKGID.meta"
  {
    echo "PKG=$PKG"
    echo "VER=$VER"
    echo "PKGID=$PKGID"
    echo "DATE=$ts"
    [ "${SRC:-}" ] && echo "SRC=$SRC"
    [ "${DESC:-}" ] && echo "DESC=$DESC"
  } > "$meta_file"
}

make_manifest() {
  local mf
  mf="$MAN/$PKGID.files"
  (
    cd "$DESTDIR"
    find . -mindepth 1 \
      ! -path './usr/share/info/dir' \
      -print | sort
  ) > "$mf"
}

check_collisions() {
  local force mf collisions
  force="${1:-no}"
  mf="$MAN/$PKGID.files"
  collisions="/tmp/box-collisions.$PKGID.$$"
  : > "$collisions"

  # For each staged path, check if it would overwrite something on /
  while IFS= read -r p; do
    local rel target
    rel="${p#./}"
    [ -n "$rel" ] || continue
    target="/$rel"

    case "$target" in
      /usr/share/info/dir) continue ;;
    esac

    if [ -e "$target" ] || [ -L "$target" ]; then
      # allow if target is a directory and we're also a directory
      if [ -d "$target" ] && [ -d "$DESTDIR/$rel" ]; then
        continue
      fi
      echo "$target" >> "$collisions"
    fi
  done < "$mf"

  if [ -s "$collisions" ] && [ "$force" != "yes" ]; then
    echo "box: collisions detected; refusing to overwrite." >&2
    echo "box: re-run with --force to allow overwrites." >&2
    echo "---- collisions ----" >&2
    cat "$collisions" >&2
    rm -f "$collisions"
    exit 1
  fi
  rm -f "$collisions"
}

commit_stage() {
  [ -d "$DESTDIR" ] || die "no DESTDIR: $DESTDIR"

  local tmp=""
  tmp="$(mktemp -p "${TMPDIR:-/tmp}" "box-stage.XXXXXX.tar")"
  trap 'rm -f "$tmp"' RETURN

  ( cd "$DESTDIR" && tar cpf "$tmp" . ) || die "tar pack failed"
  ( cd / && tar xpf "$tmp" ) || die "tar extract failed"
}

box_cleanup() {
  # Called via trap in box_add; respects keep flags.
  if [ "${BOX_KEEP_STAGE:-0}" -eq 0 ] && [ -n "${DESTDIR:-}" ] && [[ "$DESTDIR" == /tmp/box-stage/* ]]; then
    [ -d "$DESTDIR" ] && rm -rf -- "$DESTDIR" 2>/dev/null || true
  fi

  if [ "${BOX_KEEP_WORK:-0}" -eq 0 ] && [ -n "${WORKDIR:-}" ] && [[ "$WORKDIR" == /tmp/box-work/* ]]; then
    [ -d "$WORKDIR" ] && rm -rf -- "$WORKDIR" 2>/dev/null || true
  fi
}
