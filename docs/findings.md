# Findings: RIPE Atlas 5120 on GL.iNet GL-XE3000 / Puli AX

This document summarizes the practical findings from building RIPE Atlas 5120 for a GL.iNet GL-XE3000.

## Router facts

The router reported:

```text
DISTRIB_RELEASE='21.02-SNAPSHOT'
DISTRIB_TARGET='mediatek/mt7981'
DISTRIB_ARCH='aarch64_cortex-a53'
glversion: 4.8.4
```

`opkg print-architecture`:

```text
arch all 1
arch noarch 1
arch aarch64_cortex-a53 10
```

Installed crypto/time packages included:

```text
chrony-nts - 4.1-2
libopenssl-conf - 1.1.1q-1
libopenssl1.1 - 1.1.1q-1
```

The router facts match this repo's expected package compatibility target: OpenWrt 21.02-SNAPSHOT-derived GL.iNet firmware, `aarch64_cortex-a53`, OpenSSL 1.1, and `chrony-nts`.

## Build target

OpenWrt 22.03.5 did not expose an MT7981/Filogic target in the same way as newer OpenWrt trees. It did expose MediaTek ARM subtargets including MT7622.

For package builds only, MT7622 was acceptable because it produced:

```text
CONFIG_TARGET_ARCH_PACKAGES="aarch64_cortex-a53"
```

Do not flash firmware from this target to a GL-XE3000.

## OpenWrt 23.05 issue

OpenWrt 23.05 built packages for the right CPU architecture but the wrong dependency generation:

```text
libopenssl3
```

The GL.iNet router did not have `libopenssl3` available. Its configured feeds only offered OpenSSL 1.1 packages.

Conclusion: OpenWrt 23.05 output was not installable on this stock GL.iNet firmware without mixing in newer libraries.

## OpenWrt 22.03.5 result

OpenWrt 22.03.5 built packages with OpenSSL 1.1 dependencies, which matched the router.

Output packages:

```text
ripe-atlas-common_5120-1_aarch64_cortex-a53.ipk
ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk
ripe-atlas-anchor_5120-1_aarch64_cortex-a53.ipk
```

Install only `common` and `probe` for a normal software probe.

## Ninja / Python 3.13 issue

On Debian 13, OpenWrt's host Ninja build failed with:

```text
ModuleNotFoundError: No module named 'pipes'
```

Python 3.13 removed the old `pipes` module.

Working patch:

```diff
--- a/configure.py
+++ b/configure.py
@@ -26 +26 @@
-import pipes
+import shlex as pipes
```

## RIPE feed target

The output packages are named `ripe-atlas-common` and `ripe-atlas-probe`, but the OpenWrt package build target is:

```sh
make package/feeds/ripeatlas/openwrt/compile
```

not:

```sh
make package/ripe-atlas-common/compile
```

## Chrony vs chrony-nts

The router already had `chrony-nts`, but the package depended on `chrony`. A dry-run install showed file clashes because `chrony` wanted files already owned by `chrony-nts`.

The fix was to repack only `ripe-atlas-common` metadata:

```text
chrony -> chrony-nts
```

Final desired dependency line:

```text
Depends: libc, e2fsprogs, jsonfilter, openssh-client, openssh-keygen, libopenssl1.1, chrony-nts, bzip2
```

## HTTP post port conflict

GL.iNet firmware may run `uhttpd` on IPv4 localhost port `8080`:

```text
127.0.0.1:8080  uhttpd
```

RIPE Atlas' keepalive SSH tunnel defaults to binding the same local port for HTTP post traffic:

```text
-L 8080:127.0.0.1:8080
```

When `uhttpd` already owns `127.0.0.1:8080`, the Atlas SSH tunnel can fail to bind IPv4 and Atlas `httppost` traffic may hit the router web UI instead of the RIPE Atlas controller tunnel.

Observed symptoms:

```text
bind [127.0.0.1]:8080: Address in use
httppost: reply text was not equal to OK
httppost: chunk data '<html><head><title>Index of /</title>...'
```

RIPE Atlas already supports `HTTP_POST_PORT` in `/etc/ripe-atlas/config.txt`, and `/usr/sbin/ripe-atlas` exports it as `HTTPPOST_PORT`. The OpenWrt init script regenerates `config.txt` from UCI at startup, so direct edits to `config.txt` are not persistent.

This repo applies a build-time patch to the RIPE Atlas OpenWrt package to add UCI option:

```text
ripe-atlas.@ripe-atlas[0].http_post_port
```

Set it to move the local bind port while preserving the controller-side destination:

```sh
uci set ripe-atlas.@ripe-atlas[0].http_post_port='8081'
uci commit ripe-atlas
/etc/init.d/ripe-atlas restart
```

Expected generated config:

```text
HTTP_POST_PORT=8081
```

Expected listener pattern:

```text
127.0.0.1:8080  uhttpd
127.0.0.1:8081  ssh
```

## Traffic reporting

The RIPE Atlas OpenWrt package already supports UCI option:

```text
ripe-atlas.@ripe-atlas[0].rxtx_report
```

Set it to enable interface traffic reporting:

```sh
uci set ripe-atlas.@ripe-atlas[0].rxtx_report='1'
uci commit ripe-atlas
/etc/init.d/ripe-atlas restart
```

Expected generated config:

```text
RXTXRPT=yes
```

## Old GL.iNet package conflict

The old package was:

```text
atlas-sw-probe - 5040-1
```

The new package conflicts with it. Remove `atlas-sw-probe` only after backing up keys/state and doing a dry-run.

If both an old Atlas package and the new `ripe-atlas-*` packages are installed, inspect ownership and runtime state before making changes.

## Final service state

After installation, the router showed:

```text
ripe-atlas-common - 5120-1
ripe-atlas-probe - 5120-1
```

The service was enabled and running under procd:

```text
/etc/init.d/ripe-atlas status
running
```

The procd service command was:

```text
/usr/sbin/ripe-atlas
```

## Identity/key handling

Old GL.iNet key path:

```text
/etc/atlas/probe_key
/etc/atlas/probe_key.pub
```

New RIPE Atlas package key path:

```text
/etc/ripe-atlas/probe_key
/etc/ripe-atlas/probe_key.pub
```

Either migrate the old keypair or update the RIPE Atlas probe settings page with the new public key.
