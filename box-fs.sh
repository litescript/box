# ~/src/box/box-fs.sh
#!/bin/bash
set -euo pipefail
export LC_ALL=C

stage_dir() {
  DESTDIR="/tmp/box-stage/$PKGID"
  rm -rf -- "$DESTDIR"
  command install -d -- "$DESTDIR"
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
    [ -n "${SRC:-}" ]  && echo "SRC=$SRC"
    [ -n "${DESC:-}" ] && echo "DESC=$DESC"
  } > "$meta_file"
}

make_manifest() {
  command install -d -- "$MAN"

  local all payload dirs
  all="$MAN/$PKGID.files"
  payload="$MAN/$PKGID.payload"
  dirs="$MAN/$PKGID.dirs"

  # all paths (dirs, files, symlinks) — audit view
  (
    cd "$DESTDIR"
    find . -mindepth 1 \
      ! -path './usr/share/info/dir' \
      -print | sort
  ) > "$all"

  # payload only (files + symlinks) — collisions/removal/upgrade
  (
    cd "$DESTDIR"
    find . -mindepth 1 \( -type f -o -type l \) \
      ! -path './usr/share/info/dir' \
      -print | sort
  ) > "$payload"

  # dirs only, deepest-first — cleanup on remove
  (
    cd "$DESTDIR"
    find . -mindepth 1 -type d -print | sort -r
  ) > "$dirs"
}

# --- Owners DB (path -> PKGID) ---

owners_db() {
  : "${DB:?}"
  OWNERS="$DB/owners.tsv"

  # ensure DB exists with sane perms (root-owned)
  command install -d -m 0755 -- "$DB"
  if [ ! -f "$OWNERS" ]; then
    : > "$OWNERS"
    chmod 0644 "$OWNERS" 2>/dev/null || true
  fi
}

owners_get() {
  local path="$1"
  [ -n "${OWNERS:-}" ] || owners_db
  awk -F'\t' -v p="$path" '$1==p {print $2; exit}' "$OWNERS" 2>/dev/null || true
}

owners_set() {
  # set owner for abs path to current PKGID (idempotent)
  local path="$1" tmp=""
  owners_db

  tmp="$(mktemp -p "$DB" "box-owners.XXXXXX")"
  trap 'rm -f -- "${tmp:-}"' RETURN
  
  awk -F'\t' -v p="$path" '$1!=p {print}' "$OWNERS" > "$tmp" || true
  printf "%s\t%s\n" "$path" "$PKGID" >> "$tmp"
  mv -f -- "$tmp" "$OWNERS"
}

owners_del_if_owned() {
  # delete ownership entry for abs path only if owned by given pkgid
  local path="$1" pkgid="$2" tmp=""
  owners_db

  tmp="$(mktemp -p "$DB" "box-owners.XXXXXX")"
  trap 'rm -f -- "${tmp:-}"' RETURN
  
  awk -F'\t' -v p="$path" -v k="$pkgid" '!( $1==p && $2==k ) {print}' "$OWNERS" > "$tmp" || true
  mv -f -- "$tmp" "$OWNERS"
}

owners_prune_pkgid() {
  # remove all ownership entries for a PKGID (defensive cleanup on rm)
  local pkgid="$1" tmp=""
  owners_db

  tmp="$(mktemp -p "$DB" "box-owners.XXXXXX")"
  trap 'rm -f -- "${tmp:-}"' RETURN

  awk -F'\t' -v k="$pkgid" '$2!=k {print}' "$OWNERS" > "$tmp" || true
  mv -f -- "$tmp" "$OWNERS"
}

owners_register_payload() {
  local payload
  payload="$MAN/$PKGID.payload"
  [ -s "$payload" ] || die "missing payload manifest: $payload"
  owners_db

  while IFS= read -r p; do
    local rel target
    rel="${p#./}"
    [ -n "$rel" ] || continue
    target="/$rel"

    case "$target" in
      /usr/share/info/dir) continue ;;
    esac

    owners_set "$target"
  done < "$payload"
}

owners_unregister_payload_from_file() {
  local pkgid="$1" payload_file="$2"
  [ -s "$payload_file" ] || die "missing payload manifest: $payload_file"
  owners_db

  while IFS= read -r p; do
    local rel target
    rel="${p#./}"
    [ -n "$rel" ] || continue
    target="/$rel"

    case "$target" in
      /usr/share/info/dir) continue ;;
    esac

    owners_del_if_owned "$target" "$pkgid"
  done < "$payload_file"
}

# --- Collision checking ---

check_collisions() {
  local force payload collisions
  force="${1:-no}"
  payload="$MAN/$PKGID.payload"

  [ -s "$payload" ] || die "missing payload manifest: $payload"
  owners_db

  local collisions=""
  collisions="$(mktemp -p "$DB" "box-collisions-${PKGID}.XXXXXX")"
  trap 'rm -f -- "${collisions:-}"' RETURN

  while IFS= read -r p; do
    local rel target owner
    rel="${p#./}"
    [ -n "$rel" ] || continue
    target="/$rel"

    case "$target" in
      /usr/share/info/dir) continue ;;
    esac

    # payload should be only files/symlinks, but stay defensive
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      continue
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
      owner="$(owners_get "$target")"

      # owned by someone else -> always collision
      if [ -n "$owner" ] && [ "$owner" != "$PKGID" ]; then
        printf "%s\towned-by:%s\n" "$target" "$owner" >> "$collisions"
        continue
      fi

      # unowned existing file -> collision unless forced
      if [ -z "$owner" ]; then
        printf "%s\tunowned\n" "$target" >> "$collisions"
        continue
      fi

      # owned by self -> OK (upgrade path)
    fi
  done < "$payload"

  if [ -s "$collisions" ] && [ "$force" != "yes" ]; then
    echo "box: collisions detected; refusing to overwrite." >&2
    echo "box: re-run with --force to allow overwrites." >&2
    echo "---- collisions ----" >&2
    cat "$collisions" >&2
    exit 1
  fi
}

# --- Commit staged DESTDIR into / ---

commit_stage() {
  [ -d "$DESTDIR" ] || die "no DESTDIR: $DESTDIR"
  : "${DB:?}"

  command install -d -m 0755 -- "$DB"

  local tmp=""
  tmp="$(mktemp -p "$DB" "box-stage.XXXXXX.tar")"
  trap 'rm -f -- "${tmp:-}"' RETURN

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
