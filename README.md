# box

Minimal source package manager / install helper for my LFS system.

box builds packages from simple shell “recipes”, installs into a staging root (DESTDIR), generates a file manifest,
checks for collisions, then commits the staged files into /. It is intentionally explicit and predictable.

## Design goals

- Correctness over cleverness: failures are loud; partial installs are unacceptable.
- Explicit layering: build → stage → manifest/collision-check → commit.
- Simple, auditable recipes: plain bash with build() and pkg_install() functions.
- Deterministic output: locale forced to LC_ALL=C for stable sorting/manifests.

## Failure semantics (important)

box runs in strict mode and enforces pipeline failures:

- Uses /bin/bash
- Runs with set -euo pipefail
- Pipelines logged with tee still propagate failures (tee does not mask errors)

If a build, install, manifest, collision check, or commit fails, box add fails with a non-zero exit code.

## Layout

By default, state is stored under:

- /var/lib/box/logs       — build/install logs per run
- /var/lib/box/manifests — file lists for each installed package
- /var/lib/box/meta      — package metadata (PKG/VER/SRC/DESC, etc.)
- /var/lib/box/state     — staging/working directories (implementation detail)

## Recipes

A recipe is a bash script defining package metadata and two functions:

```bash
PKG=foo
VER=1.2.3
SRC=/sources/foo-1.2.3.tar.xz
DESC="Optional description"

build() {
  ./configure --prefix=/usr
  make
  # optionally: make check
}

pkg_install() {
  make DESTDIR="$DESTDIR" install
}
```

Notes:

- SRC is required for box add (source-based installs).
- Tests are optional; if enabled and they fail, the package build fails.

## Commands

- box new `<name>`          — start recipe creation tool for package `<name>`, fuzzy searching of /sources for tarball
- box add `<recipe>`        — build + stage + install a package from a recipe
- box rm `<PKG> <VER>`      — remove an installed package using its manifest
- box list                — list installed packages
- box world `<listfile>`    — install a list of recipes; stops on first failure
- box adopt `<name> <path>` — retroactively track already-installed files

## License

See LICENSE.
