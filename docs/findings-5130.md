# Findings: RIPE Atlas 5130 build for GL.iNet GL-XE3000 / Puli AX

This document records source, package-build, and GL-XE3000 runtime evidence collected on 2026-08-16.

## Upstream release

The build uses the signed RIPE Atlas tag `5130` at commit:

```text
9eba070abb1db98890b45e5e531765ac8a11ed97
```

Upstream states that RIPE Atlas 5120 reported incorrect NTP clock offsets: it reported half the round-trip time rather than the clock offset. Release 5130 computes the RFC 5905 offset and delay in 64-bit fixed point. Upstream says 5120 RTT values are unaffected.

Other relevant changes include new registration servers with Ed25519 host keys, a default 4000 ms gap between NTP requests, default-route-interface MAC selection, environment-specific SOS hosts, reduced OpenWrt configuration writes, fixed account IDs, and a new hardware-probe package.

The GL.iNet installation remains a software probe. Build and install only `ripe-atlas-common` and `ripe-atlas-probe`, not `ripe-atlas-hwprobe`.

## Build result

OpenWrt `v22.03.5` successfully built RIPE Atlas 5130 for:

```text
aarch64_cortex-a53
```

Final generated artifacts:

```text
ripe-atlas-common_5130-1_chrony-nts_aarch64_cortex-a53.ipk
ripe-atlas-probe_5130-1_aarch64_cortex-a53.ipk
```

The final common package metadata was:

```text
Version: 5130-1
Architecture: aarch64_cortex-a53
Depends: libc, jsonfilter, openssh-client, openssh-keygen, libopenssl1.1, chrony-nts, bzip2
Require-User: ripe-atlas=3333:ripe-atlas=3333 ripe-atlas-measurement=3334:ripe-atlas=3333
```

The package has no `libopenssl3`, plain `chrony`, or `e2fsprogs` dependency. This preserves compatibility with the validated GL.iNet firmware's OpenSSL 1.1 and `chrony-nts` packages.

OpenWrt 22.03.5 emits a recursive Kconfig dependency warning because the 5130 hardware probe and software probe conflict with each other. Configuration still completes with only `ripe-atlas-common=m` and `ripe-atlas-probe=m`; both `ripe-atlas-hwprobe` and `ripe-atlas-anchor` remain disabled. The build script asserts those selections before compiling.

RIPE Atlas 5130 also requires BusyBox `tee`. OpenWrt 22.03.5 supplies it through the default BusyBox configuration as `CONFIG_BUSYBOX_DEFAULT_TEE=y`; enabling custom BusyBox configuration is not required.

## Payload verification

The built packages contain:

- The generic software-probe configuration, not the hardware-probe configuration.
- Production registration hosts `reg-05.prod.atlas.ripe.net` and `reg-06.prod.atlas.ripe.net`.
- Ed25519 known-host entries for the new registration servers.
- UCI option `http_post_port` and a range check for ports 0 through 65535.
- Configuration synchronization that treats `config.txt` as data rather than sourcing it as root, normalizes duplicate managed entries, preserves unrelated entries, and avoids rewriting the file when managed values have not changed.
- Setuid setup for the bundled measurement BusyBox, installed as `root:ripe-atlas` mode `4750` by the UCI-defaults script.
- Root effective privileges for `eooqd`, `eperd`, `evping`, and `evtraceroute` in `measurement.conf`.
- Telnetd PID cleanup for both the runtime PID and status directories, with numeric PID and process-name checks before signaling.
- Preservation lists for `/etc/config/ripe-atlas`, `/etc/ripe-atlas/probe_key`, and `/etc/ripe-atlas/probe_key.pub`.

The patched init configuration was also exercised with a temporary root. It preserved unrelated and shell-like literal settings without executing them, normalized duplicate stale managed values, and left the file modification time unchanged on a second start with identical UCI values.

## Upgrade handling

RIPE Atlas 5130 only removes `/etc/ripe-atlas/reg_servers.sh` when UCI mode changes. A 5120-to-5130 upgrade normally keeps mode `prod`, so the old generated registration-server list could otherwise survive alongside the new Ed25519 known-host file.

The router installer therefore:

1. Backs up RIPE Atlas state and package metadata.
2. Checks UID/GID 3333 and UID 3334 for unrelated collisions.
3. Checksums an existing private probe key.
4. Runs an initial package dry-run.
5. Prompts before destructive changes.
6. Refuses legacy `atlas-sw-probe` migration because its conflict prevents a conclusive dry-run.
7. Removes the generated registration-server cache.
8. Runs a second package dry-run.
9. Upgrades existing `ripe-atlas-*` packages in place.
10. Verifies the private key checksum, package payload, service startup, and regenerated 5130 registration-server cache.

## Router validation

The guarded installer upgraded the validated GL-XE3000 from `ripe-atlas-common` and `ripe-atlas-probe` 5120-1 to 5130-1 on GL.iNet firmware 4.8.4.

Both `opkg --noaction` gates completed successfully and showed an in-place package upgrade. The actual transaction completed without dependency or file conflicts. Opkg printed `Command failed: Not found` during its extra service stop/start cycle after the installer had already stopped the service; package configuration continued, the package database updated, and no related runtime failure remained.

The router retained its existing dynamically allocated Atlas accounts rather than changing them to the new reserved IDs:

```text
ripe-atlas              UID/GID 65538
ripe-atlas-measurement  UID 65539, GID 65538
```

This is expected from OpenWrt's name-based account creation logic. The preflight confirmed that reserved IDs 3333 and 3334 had no unrelated collisions.

The private probe key's SHA-256 hash matched before installation, after installation, after an explicit service restart, and after a full router reboot.

The generated production registration-server cache changed to:

```text
REG_1_HOST=reg-05.prod.atlas.ripe.net
REG_4_HOST=reg-06.prod.atlas.ripe.net
```

The packaged known-host file contains the matching Ed25519 keys. The controller SSH connection became established after both restart and reboot.

The UCI and generated configuration remained:

```text
rxtx_report='1'
http_post_port='8081'

RXTXRPT=yes
HTTP_POST_PORT=8081
```

Observed listener separation:

```text
127.0.0.1:2023  telnetd
127.0.0.1:8080  uhttpd
127.0.0.1:8081  ssh
```

An explicit service restart replaced the telnetd PID and restored all listeners. After a full router reboot, packages remained at 5130-1, the service returned to `running`, privilege-separated measurement processes returned, and the same listener/configuration state persisted.

The public RIPE Atlas API reported software probe `1015938` as connected on firmware 5130, with both IPv4 and IPv6 working, after installation and again after reboot.

A direct 5130 NTP query completed successfully and returned:

```text
"fw":5130
"rtt":0.027461
"offset":0.000195
```

No post-upgrade `socket failed`, `Operation not permitted`, HTTP reply mismatch, or local address-in-use errors were found. `ssh_err.txt` contained a host-key warning for one controller IPv6 literal, but the controller SSH process had an established TCP session and the probe remained connected through the public API.
