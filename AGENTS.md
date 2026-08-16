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
- Default RIPE Atlas tag is `5130` at commit `9eba070abb1db98890b45e5e531765ac8a11ed97`.

## Important build findings

- Debian 13 uses Python 3.13. OpenWrt 22.03/23.05 bundled Ninja imports the removed Python `pipes` module.
- Patch Ninja's `configure.py` with `import shlex as pipes`.
- OpenWrt 23.05 produces RIPE packages that depend on `libopenssl3`, which does not match GL.iNet 4.x firmware tested on GL-XE3000.
- OpenWrt 22.03.5 produces `libopenssl1.1` dependencies, matching the tested router.
- The GL-XE3000 is MT7981, but this repo uses OpenWrt 22.03.5 `mediatek/mt7622` only to build userspace packages for `aarch64_cortex-a53`. It must not be used to flash firmware.
- GL.iNet firmware may have `chrony-nts` installed instead of plain `chrony`; the build repacks `ripe-atlas-common` dependency metadata accordingly.
- GL.iNet firmware may run `uhttpd` on `127.0.0.1:8080`, which conflicts with RIPE Atlas' default local HTTP post tunnel. Symptoms include `bind [127.0.0.1]:8080: Address in use` in `ssh_err.txt` and `httppost` receiving GL.iNet web UI HTML instead of `OK`.
- RIPE Atlas supports `HTTP_POST_PORT` in `/etc/ripe-atlas/config.txt`; this repo patches the OpenWrt package at build time to expose it as UCI option `ripe-atlas.@ripe-atlas[0].http_post_port`.
- RIPE Atlas' local `telnetd` must listen on `127.0.0.1:2023` for the controller `ssh -R` tunnel. On GL.iNet firmware, the generic OpenWrt package runs the main service as `ripe-atlas`; the bundled BusyBox `telnetd` needs setuid-root behavior or it exits with `setresuid: Operation not permitted` and SSH logs `connect_to 127.0.0.1 port 2023: failed`.
- RIPE Atlas IPv4/IPv6 ICMP measurements can fail with `socket failed: Operation not permitted` even when router IPv4/IPv6 connectivity works. On GL.iNet firmware without `ujail`/`setcap`, raw-socket applets (`eperd`, `eooqd`, `evping`, `evtraceroute`) need root effective privileges via `measurement.conf`.
- Traffic reporting is controlled by existing UCI option `ripe-atlas.@ripe-atlas[0].rxtx_report`; it generates `RXTXRPT=yes` in `/etc/ripe-atlas/config.txt`.
- RIPE Atlas 5120 reports incorrect NTP clock offsets. Release 5130 corrects the offset calculation; 5120 RTT values are unaffected.
- RIPE Atlas 5130 uses new registration servers with Ed25519 host keys. Upgrades must remove the generated `/etc/ripe-atlas/reg_servers.sh` cache after backing it up.
- RIPE Atlas 5130 reserves UID/GID 3333 for `ripe-atlas` and UID 3334 for `ripe-atlas-measurement`; reject unrelated account collisions before installation.

## Test commands

Run from repo root:

```sh
sh -n scripts/build-ripe-atlas-glinet.sh
sh -n scripts/router-install-ripe-atlas.sh
sh -n scripts/router-debug-ripe-atlas.sh
```

```sh
shellcheck scripts/*.sh
```

ShellCheck is expected to pass cleanly for `scripts/*.sh`.
