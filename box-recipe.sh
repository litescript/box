# ~/src/box/box-recipe.sh
#!/bin/bash
set -euo pipefail
export LC_ALL=C

resolve_recipe() {
  # Usage: resolve_recipe <arg>
  # Prints resolved recipe path on stdout, or dies.
  local arg="$1"

  # Expand "~/" safely (tilde doesn't expand from variables).
  if [[ "$arg" == "~/"* ]]; then
    arg="${USER_HOME:-$HOME}/${arg#~/}"
  fi

  # Path-like? leave it alone.
  case "$arg" in
    */*|.|..|./*|../*)
      [ -f "$arg" ] || die "recipe not found: $arg"
      printf '%s\n' "$arg"
      return 0
      ;;
  esac

  # Try default directory
  if [ -f "$RECIPE_DIR/$arg" ]; then
    printf '%s\n' "$RECIPE_DIR/$arg"
    return 0
  fi

  # Allow omitting .sh
  if [[ "$arg" != *.sh ]] && [ -f "$RECIPE_DIR/$arg.sh" ]; then
    printf '%s\n' "$RECIPE_DIR/$arg.sh"
    return 0
  fi

  # Allow PKG-VER naming: arg-*.sh
  local -a vers=()
  shopt -s nullglob
  vers=( "$RECIPE_DIR/$arg"-*.sh )
  shopt -u nullglob

  if ((${#vers[@]} == 1)); then
    printf '%s\n' "${vers[0]}"
    return 0
  fi

  if ((${#vers[@]} > 1)); then
    # Deterministic: pick the "highest" by version-like sort on basename
    local pick=""
    pick="$(
      printf '%s\n' "${vers[@]##*/}" \
        | sort -V \
        | tail -n 1
    )"
    printf '%s\n' "$RECIPE_DIR/$pick"
    return 0
  fi

  die "recipe not found: $arg (tried: $RECIPE_DIR/$arg, $RECIPE_DIR/$arg.sh, $RECIPE_DIR/$arg-*.sh). Set RECIPE_DIR or pass a path."
}

load_recipe() {
  RECIPE="$(resolve_recipe "$1")"
  [ -f "$RECIPE" ] || die "recipe not found: $RECIPE"
  # shellcheck disable=SC1090
  . "$RECIPE"
  : "${PKG:?recipe must set PKG=...}"
  : "${VER:?recipe must set VER=...}"
  type pkg_install >/dev/null 2>&1 || die "recipe must define pkg_install() { ... }"
  PKGID="${PKG}-${VER}"
}

guess_src() {
  # Usage: guess_src <PKG> <VER>
  # Prints the chosen default SRC path on stdout.
  local pkg="$1" ver="$2"
  local fallback="/sources/${pkg}-${ver}.tar.xz"
  local -a matches=()
  local pat

  # Patterns in order of preference
  for pat in \
    "/sources/${pkg}-${ver}."* \
    "/sources/${pkg}_${ver}."* \
    "/sources/${pkg}-${ver}"* \
  ; do
    shopt -s nullglob
    matches+=( $pat )
    shopt -u nullglob

    if ((${#matches[@]} > 0)); then
      break
    fi
  done

  if ((${#matches[@]} == 1)); then
    printf '%s\n' "${matches[0]}"
    return 0
  fi

  if ((${#matches[@]} > 1)); then
    # Interactive selection if possible
    if command -v fzf >/dev/null 2>&1 && [ -t 0 ] && [ -r /dev/tty ]; then
      local choice=""
      choice="$(printf '%s\n' "${matches[@]}" \
        | fzf --prompt="Select SRC for ${pkg}-${ver}> " </dev/tty
      )" || choice=""

      if [ -n "${choice:-}" ]; then
        printf '%s\n' "$choice"
        return 0
      fi

      # If user cancels fzf, fall back quietly
      printf '%s\n' "$fallback"
      return 0
    fi

    # Non-interactive / no fzf: warn and fall back
    echo "note: multiple /sources matches for ${pkg}-${ver}; using fallback and you should pick one:" >&2
    local m
    for m in "${matches[@]}"; do
      echo "  - ${m##*/}" >&2
    done
  fi

  printf '%s\n' "$fallback"
}
