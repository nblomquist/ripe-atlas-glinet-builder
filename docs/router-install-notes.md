# Router install notes

This is the manual install flow for the GL-XE3000 once packages are copied to `/tmp`.

## Files expected on router

```text
/tmp/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk
/tmp/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk
```

## Preflight

```sh
opkg print-architecture
opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|bzip2|openssh'
```

## Dry-run

```sh
opkg --noaction install \
  /tmp/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk \
  /tmp/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk
```

Expected before old package removal: a conflict with `atlas-sw-probe`.

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

opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|bzip2|openssh' \
  > /root/ripe-atlas-backup/packages-before.txt
```

## Install

```sh
opkg update
opkg install openssh-keygen bzip2

/etc/init.d/ripe-atlas stop 2>/dev/null || true
opkg remove atlas-sw-probe

opkg --noaction install \
  /tmp/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk \
  /tmp/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk

opkg install \
  /tmp/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk \
  /tmp/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk

/etc/init.d/ripe-atlas enable
/etc/init.d/ripe-atlas restart
```
