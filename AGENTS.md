# Agent Instructions

This repository builds RIPE Atlas `.ipk` packages for GL.iNet OpenWrt-based routers.

## Constraints

- Keep shell scripts POSIX `sh` compatible.
- Do not require Bash-specific syntax.
- Do not use `opkg --force-depends` or `--force-overwrite` in default workflows.
- Do not commit generated OpenWrt build trees, toolchains, or `.ipk` files.
- Treat `dist/` output as generated artifacts.
- Preserve dry-run gates before destructive router changes.
- Default validated router target is GL.iNet GL-XE3000 / Puli AX.
- Default package architecture is `aarch64_cortex-a53`.
- Default OpenWrt build version is `v22.03.5`.
- Default RIPE Atlas tag is `5120`.

## Important build findings

- Debian 13 uses Python 3.13. OpenWrt 22.03/23.05 bundled Ninja imports the removed Python `pipes` module.
- Patch Ninja's `configure.py` with `import shlex as pipes`.
- OpenWrt 23.05 produces RIPE packages that depend on `libopenssl3`, which does not match GL.iNet 4.x firmware tested on GL-XE3000.
- OpenWrt 22.03.5 produces `libopenssl1.1` dependencies, matching the tested router.
- The GL-XE3000 is MT7981, but this repo uses OpenWrt 22.03.5 `mediatek/mt7622` only to build userspace packages for `aarch64_cortex-a53`. It must not be used to flash firmware.
- GL.iNet firmware may have `chrony-nts` installed instead of plain `chrony`; the build repacks `ripe-atlas-common` dependency metadata accordingly.

## Test commands

Run from repo root:

```sh
sh -n scripts/build-ripe-atlas-glinet.sh
sh -n scripts/router-install-ripe-atlas-5120.sh
sh -n scripts/router-debug-ripe-atlas.sh
```

If available:

```sh
shellcheck scripts/*.sh
```
