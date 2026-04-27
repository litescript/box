index_require() {
  [ -f "$BOX_INDEX" ] || die "index not found: $BOX_INDEX"
}

index_lookup_line() {
  # prints the full line for a package
  local pkg="$1"
  index_require

  awk -F'\t' -v p="$pkg" '$1==p {print; exit}' "$BOX_INDEX"
}

index_recipe_for() {
  local line
  line="$(index_lookup_line "$1")" || true
  [ -n "$line" ] || die "package not found in index: $1"

  # field 3 = recipe
  printf "%s\n" "$line" | awk -F'\t' '{print $3}'
}

index_deps_for() {
  local line
  line="$(index_lookup_line "$1")" || true
  [ -n "$line" ] || die "package not found in index: $1"

  # field 4 = deps (space separated)
  printf "%s\n" "$line" | awk -F'\t' '{print $4}'
}

box_resolve_install() {
  local pkg="$1"
  local force="${2:-no}"

  # visited + stack for cycle detection
  declare -gA _box_seen
  declare -gA _box_stack

  _box_resolve "$pkg" "$force"
}

_box_resolve() {
  local pkg="$1"
  local force="$2"

  # already installed → skip
  if installed_has_pkg "$pkg"; then
    return 0
  fi

  # cycle detection
  if [ "${_box_stack[$pkg]:-0}" -eq 1 ]; then
    die "dependency cycle detected at: $pkg"
  fi

  # already processed
  if [ "${_box_seen[$pkg]:-0}" -eq 1 ]; then
    return 0
  fi

  _box_stack[$pkg]=1

  local deps dep
  deps="$(index_deps_for "$pkg")"

  for dep in $deps; do
    [ -n "$dep" ] || continue
    _box_resolve "$dep" "$force"
  done

  _box_stack[$pkg]=0
  _box_seen[$pkg]=1

  # now install this pkg
  local recipe
  recipe="$(index_recipe_for "$pkg")"

  if [ "$force" = "yes" ]; then
    box_add "$recipe" --force
  else
    box_add "$recipe"
  fi
}

box_search() {
  [ $# -ge 1 ] || die "usage: box search <term>"

  local term="$1"
  index_require

  awk -F'\t' -v q="$term" '
    BEGIN {
      found = 0
    }

    $0 ~ /^[[:space:]]*$/ { next }
    $1 ~ /^#/ { next }

    index($1, q) || index($3, q) {
      found = 1
      printf "%-24s %-14s %s", $1, $2, $3

      if ($4 != "") {
        printf "  deps: %s", $4
      }

      printf "\n"
    }

    END {
      if (!found) {
        exit 1
      }
    }
  ' "$BOX_INDEX" || die "no packages found matching: $term"
}
