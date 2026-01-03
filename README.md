# box

Minimal package/install helper.

- Installs into a staging root (DESTDIR), generates a manifest, checks collisions, then commits into /.
- Metadata lives in /var/lib/box/{manifests,meta,logs,state}.
- Supports adopt for retroactive tracking of manually installed files.
