# box

box is a minimal, explicit source-based package manager and install helper for an LFS-style system.

It builds packages from simple shell “recipes”, installs into a staging root (DESTDIR), generates file manifests,
checks for collisions, and then commits the staged files into /.

The design favors correctness, auditability, and predictable behavior over convenience.

------------------------------------------------------------------------------

DESIGN GOALS

- Correctness over cleverness
  Fail loudly. Partial installs are unacceptable.

- Explicit lifecycle
  build → stage → manifest → collision check → commit

- Simple, auditable recipes
  Plain bash with build() and pkg_install() functions.

- Deterministic output
  LC_ALL=C is enforced for stable sorting and manifests.

------------------------------------------------------------------------------

FAILURE SEMANTICS

box runs in strict shell mode:

- /bin/bash
- set -euo pipefail
- Pipelines logged with tee still propagate failures

If any step fails (build, install, manifest generation, collision check, or commit),
box add exits non-zero and no partial install is committed.

------------------------------------------------------------------------------

INSTALL SEMANTICS

Fresh install:

  box: installing <PKG>-<VER>
  box: ok: installed <PKG>-<VER>

Reinstall (same PKG and VER):

  box: reinstalling <PKG>-<VER>
  box: ok: reinstalled <PKG>-<VER>

Reinstalling is intentional and performs a clean rebuild and reinstall of the package.
This supports repair and rebuild workflows without requiring a version bump.

------------------------------------------------------------------------------

STATE LAYOUT

All state lives under /var/lib/box:

- installed/
  Per-package install records:
    files        All tracked paths (audit view)
    payload      Files and symlinks (ownership, removal, collisions)
    dirs         Directories, deepest-first (cleanup order)
    meta         Package metadata
    install.log  Install log for the run

- owners.tsv
  Ownership database mapping absolute paths to PKGID

- logs/
  Build and install logs per run

------------------------------------------------------------------------------

RECIPES

A recipe is a bash script defining metadata and two functions:

PKG=foo
VER=1.2.3
SRC=/sources/foo-1.2.3.tar.xz
DESC="Optional description"

build() {
  ./configure --prefix=/usr
  make
}

pkg_install() {
  make DESTDIR="$DESTDIR" install
}

Notes:
- SRC is optional; box does not fetch sources automatically
- Tests are optional; if enabled and they fail, the build fails
- Recipes are executed with strict error handling

------------------------------------------------------------------------------

DEPENDENCIES

Recipes may declare dependencies:

DEPENDS=(zlib openssl)

Rules:
- Dependencies must already be installed
- Removal is blocked if another package depends on it
- Reverse dependencies are reported on failure

------------------------------------------------------------------------------

COMMANDS

box add <recipe> [--force]
  Build, stage, and install a package

box rm <PKG>-<VER>
  Remove an installed package using its manifest

box list
  List installed packages

box world <file>
  Install a list of recipes; stops on first failure

box adopt <PKG> <VER> <absolute-path>
  Retroactively track already-installed files

------------------------------------------------------------------------------

LICENSE

See LICENSE.
