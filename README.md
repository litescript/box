# box

box is a minimal, explicit source-based package manager for an LFS-style system.

It builds packages from simple shell “recipes”, installs into a staging root (DESTDIR),
generates file manifests, checks for collisions, and commits the result into `/`.

A higher-level index layer allows dependency-aware installs similar to `apt` or `pacman`,
while keeping the underlying behavior fully transparent.

---

## DESIGN GOALS

- **Correctness over convenience**  
  No partial installs. Fail loudly.

- **Explicit lifecycle**  
  build → stage → manifest → collision check → commit

- **Auditable state**  
  Every installed file is tracked.

- **Simple primitives**  
  Plain bash recipes. No hidden magic.

---

## INSTALL LIFECYCLE

Every install follows:

```
build()
→ pkg_install() into DESTDIR
→ manifest generation
→ collision check
→ commit into /
→ ownership registration
```

If any step fails, nothing is installed.

---

## STATE LAYOUT

All state lives under:

```
/var/lib/box
```

Structure:

```
installed/    per-package records
manifests/    generated file lists
meta/         package metadata
logs/         build/install logs
state/        world runs, etc
owners.tsv    path → package ownership
```

---

## RECIPES

A recipe is a shell script:

```sh
PKG=zlib
VER=1.3.1
SRC=/sources/zlib-1.3.1.tar.xz
DESC="compression library"

DEPENDS=(...)

build() {
  ./configure --prefix=/usr
  make
}

pkg_install() {
  make DESTDIR="$DESTDIR" install
}
```

Rules:

- pkg_install() is required
- must install into $DESTDIR
- must be deterministic
- runs with set -euo pipefail

---

## COMMANDS

### Low-level

```
box add <recipe> [--force]
```

Build and install a specific recipe file.

---

### High-level (index-backed)

```
box install <pkg> [--force]
```

- resolves dependencies recursively
- installs missing packages
- skips already-installed package names
- uses the local index

---

### Removal

```
box rm <PKG>-<VER>
```

- removes files via manifest
- refuses if other packages depend on it

---

### Inspection

```
box list
box info <PKG>-<VER>
box own <absolute-path>
```

---

### Batch install

```
box world <file> [--force]
```

Installs a list of recipes.

---

### Recipe creation

```
box new
```

Interactive recipe generator.

---

## INDEX

Default location:

```
~/ls-box/index.tsv
```

Override:

```
BOX_INDEX=/path/to/index.tsv
```

Format:

```
name<TAB>version<TAB>recipe_path<TAB>deps
```

Example:

```
zlib    1.3.1  zlib-1.3.1.sh
openssl 3.5.0  openssl-3.5.0.sh   zlib
```

Notes:

- deps are space-separated
- only one version per package (for now)
- no version solving yet

---

## DEPENDENCY MODEL

- dependencies must be listed in the index
- install order is resolved recursively
- already-installed packages satisfy deps by name
- cycles are detected and rejected
- removal is blocked by reverse dependencies

---

## COLLISIONS

box refuses to overwrite:

- files owned by another package
- unowned existing files

Override:

```
box add ... --force
box install ... --force
```

---

## ADOPTION

```
box adopt <name> <ver> <path>
```

Tracks existing files into box ownership.

---

## WHAT THIS IS (AND ISN’T)

box **is**:

- deterministic
- auditable
- minimal
- source-based

box is **not yet**:

- a binary package manager
- a remote repo client
- a version solver
- a dependency SAT engine

---

## LICENSE

See LICENSE.
