# Router install notes

This is the manual install flow for the GL-XE3000 once packages are copied to `/tmp`.

## Files expected on router

```text
/tmp/ripe-atlas-common_5130-1_chrony-nts_aarch64_cortex-a53.ipk
/tmp/ripe-atlas-probe_5130-1_aarch64_cortex-a53.ipk
```

## Preflight

```sh
opkg print-architecture
opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|bzip2|openssh'
awk -F: '$3 == 3333 || $3 == 3334 { print }' /etc/passwd /etc/group
```

## Dry-run

```sh
opkg --noaction install \
  /tmp/ripe-atlas-common_5130-1_chrony-nts_aarch64_cortex-a53.ipk \
  /tmp/ripe-atlas-probe_5130-1_aarch64_cortex-a53.ipk
```

When `ripe-atlas-common` and `ripe-atlas-probe` 5120 are already installed, the dry-run should show an in-place upgrade to 5130. Do not remove those packages. The probe keys are generated runtime state listed for sysupgrade preservation, and the guarded installer verifies that an existing private key remains unchanged.

If `atlas-sw-probe` is still installed, stop. Its declared conflict makes `opkg` return before it completes the remaining installability checks. The guarded 5130 installer intentionally refuses that legacy migration rather than removing a working probe after an inconclusive dry-run.

Unexpected blockers:

- `libopenssl3`: wrong build generation.
- `chrony wants to install file`: common package was not repacked to `chrony-nts`.

## Backup

```sh
mkdir -p /root/ripe-atlas-backup

cp -a /etc/atlas /root/ripe-atlas-backup/etc-atlas 2>/dev/null || true
cp -a /etc/ripe-atlas /root/ripe-atlas-backup/etc-ripe-atlas 2>/dev/null || true
cp -a /var/atlas-probe /root/ripe-atlas-backup/var-atlas-probe 2>/dev/null || true
cp -a /var/lib/ripe-atlas /root/ripe-atlas-backup/var-lib-ripe-atlas 2>/dev/null || true
cp -a /etc/config/ripe-atlas /root/ripe-atlas-backup/ripe-atlas.uci 2>/dev/null || true
sha256sum /etc/ripe-atlas/probe_key \
  > /root/ripe-atlas-backup/probe-key-sha256-before.txt 2>/dev/null || true

opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|bzip2|openssh' \
  > /root/ripe-atlas-backup/packages-before.txt
```

## Install

```sh
opkg update

opkg --noaction install \
  /tmp/ripe-atlas-common_5130-1_chrony-nts_aarch64_cortex-a53.ipk \
  /tmp/ripe-atlas-probe_5130-1_aarch64_cortex-a53.ipk

/etc/init.d/ripe-atlas stop 2>/dev/null || true
rm -f /etc/ripe-atlas/reg_servers.sh

opkg --noaction install \
  /tmp/ripe-atlas-common_5130-1_chrony-nts_aarch64_cortex-a53.ipk \
  /tmp/ripe-atlas-probe_5130-1_aarch64_cortex-a53.ipk

opkg install \
  /tmp/ripe-atlas-common_5130-1_chrony-nts_aarch64_cortex-a53.ipk \
  /tmp/ripe-atlas-probe_5130-1_aarch64_cortex-a53.ipk

/etc/init.d/ripe-atlas enable
/etc/init.d/ripe-atlas restart
```

Removing `/etc/ripe-atlas/reg_servers.sh` is required for an upgrade from 5120. It is generated state, and otherwise the 5130 startup logic can retain the old registration hosts while using the new Ed25519 known-host file.

## Post-install config

The patched RIPE Atlas init script synchronizes `RXTXRPT` and `HTTP_POST_PORT` from UCI only when their values change. It preserves unrelated entries in `/etc/ripe-atlas/config.txt`.

Recommended settings on GL.iNet firmware:

```sh
uci set ripe-atlas.@ripe-atlas[0].http_post_port='8081'
uci set ripe-atlas.@ripe-atlas[0].rxtx_report='1'
uci commit ripe-atlas
/etc/init.d/ripe-atlas restart
```

This should generate:

```text
RXTXRPT=yes
HTTP_POST_PORT=8081
```

Verify the HTTP post tunnel is not colliding with `uhttpd`:

```sh
netstat -lntp | grep -E ':(8080|8081)[[:space:]]'
cat /var/run/ripe-atlas/status/ssh_err.txt
logread | grep -Ei 'ripe|atlas|httppost|probe' | tail -200
```

Problem indicators:

```text
bind [127.0.0.1]:8080: Address in use
httppost: reply text was not equal to OK
```

## 5130 checks

Verify the package version and registration-server migration:

```sh
opkg list-installed | grep '^ripe-atlas-'
grep '^REG_[1-6]_HOST=' /etc/ripe-atlas/reg_servers.sh
grep '^reg-05\.prod\.atlas\.ripe\.net ssh-ed25519 ' \
  /usr/share/ripe-atlas/known_hosts.reg
```

For production mode, `REG_1_HOST` should be `reg-05.prod.atlas.ripe.net`. Confirm the private key checksum still matches the backup before judging probe connectivity.

RIPE Atlas 5120 NTP offset values are incorrect according to upstream. Release 5130 fixes the offset calculation; RTT values from 5120 are unaffected.
