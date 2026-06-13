#!/bin/sh
# Install RIPE Atlas 5120 packages on a GL.iNet/OpenWrt router.
# POSIX sh. Run on the router after copying the two .ipk files to /tmp.

set -u

COMMON_IPK="${COMMON_IPK:-/tmp/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk}"
PROBE_IPK="${PROBE_IPK:-/tmp/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk}"
BACKUP_DIR="${BACKUP_DIR:-/root/ripe-atlas-backup-$(date +%Y%m%d-%H%M%S)}"
ASSUME_YES="${ASSUME_YES:-0}"

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

fail() {
    printf '\nERROR: %s\n' "$1" >&2
    exit 1
}

run() {
    printf '+ %s\n' "$*"
    "$@"
}

section "Preflight"

[ "$(id -u)" = "0" ] || fail "Run as root on the router."
command -v opkg >/dev/null 2>&1 || fail "opkg not found."

[ -f "$COMMON_IPK" ] || fail "Missing $COMMON_IPK"
[ -f "$PROBE_IPK" ] || fail "Missing $PROBE_IPK"

printf 'Package files:\n'
ls -lh "$COMMON_IPK" "$PROBE_IPK"

printf '\nArchitecture:\n'
opkg print-architecture

printf '\nRelated installed packages:\n'
opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|openssh|bzip2' || true

section "Backup current Atlas/RIPE state"

mkdir -p "$BACKUP_DIR" || fail "Could not create $BACKUP_DIR"

date > "$BACKUP_DIR/backup-time.txt"
uname -a > "$BACKUP_DIR/uname.txt" 2>&1 || true
cat /etc/openwrt_release > "$BACKUP_DIR/openwrt_release.txt" 2>&1 || true
cat /etc/os-release > "$BACKUP_DIR/os-release.txt" 2>&1 || true
opkg print-architecture > "$BACKUP_DIR/opkg-architectures.txt" 2>&1 || true
opkg list-installed > "$BACKUP_DIR/packages-before-all.txt" 2>&1 || true
opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|openssh|bzip2' > "$BACKUP_DIR/packages-before-related.txt" 2>&1 || true
opkg files atlas-sw-probe > "$BACKUP_DIR/atlas-sw-probe-files.txt" 2>&1 || true
opkg info atlas-sw-probe > "$BACKUP_DIR/atlas-sw-probe-info.txt" 2>&1 || true

cp -a /etc/atlas "$BACKUP_DIR/etc-atlas" 2>/dev/null || true
cp -a /etc/ripe-atlas "$BACKUP_DIR/etc-ripe-atlas" 2>/dev/null || true
cp -a /var/atlas-probe "$BACKUP_DIR/var-atlas-probe" 2>/dev/null || true
cp -a /var/lib/ripe-atlas "$BACKUP_DIR/var-lib-ripe-atlas" 2>/dev/null || true
cp -a /usr/libexec/atlas-probe-scripts/data "$BACKUP_DIR/atlas-probe-scripts-data" 2>/dev/null || true

find /etc /var /usr/libexec \( -iname '*atlas*' -o -iname '*ripe*' \) > "$BACKUP_DIR/atlas-ripe-paths.txt" 2>/dev/null || true

printf 'Backup created: %s\n' "$BACKUP_DIR"

section "Update package lists and install harmless prerequisites"

run opkg update || fail "opkg update failed."
run opkg install openssh-keygen bzip2 || fail "Failed to install openssh-keygen/bzip2."

section "Dry-run install before removing old package"

opkg --noaction install "$COMMON_IPK" "$PROBE_IPK" > /tmp/ripe-atlas-5120-dryrun-before-remove.log 2>&1
cat /tmp/ripe-atlas-5120-dryrun-before-remove.log

if grep -q 'libopenssl3' /tmp/ripe-atlas-5120-dryrun-before-remove.log; then
    fail "Package wants libopenssl3. Wrong build for this firmware."
fi

if grep -q 'chrony wants to install file' /tmp/ripe-atlas-5120-dryrun-before-remove.log; then
    fail "Package still clashes with chrony-nts. Use repacked common package."
fi

section "Dry-run remove atlas-sw-probe"

if opkg list-installed | grep -q '^atlas-sw-probe '; then
    run opkg --noaction remove atlas-sw-probe || fail "Dry-run remove failed."
else
    printf 'atlas-sw-probe not installed.\n'
fi

section "Confirmation"

cat <<EOF
About to:
  1. Stop Atlas/RIPE services if present.
  2. Remove old atlas-sw-probe if installed.
  3. Dry-run install RIPE Atlas 5120 again.
  4. Install RIPE Atlas 5120.
  5. Enable/restart /etc/init.d/ripe-atlas.

Backup directory:
  $BACKUP_DIR
EOF

if [ "$ASSUME_YES" != "1" ]; then
    printf 'Type YES to continue: '
    read -r answer
    [ "$answer" = "YES" ] || fail "Aborted before destructive changes."
fi

section "Stop services"

/etc/init.d/atlas stop 2>/dev/null || true
/etc/init.d/ripe-atlas stop 2>/dev/null || true

section "Remove old package"

if opkg list-installed | grep -q '^atlas-sw-probe '; then
    run opkg remove atlas-sw-probe || fail "Failed to remove atlas-sw-probe."
else
    printf 'atlas-sw-probe already absent.\n'
fi

section "Dry-run install after old package removal"

opkg --noaction install "$COMMON_IPK" "$PROBE_IPK" > /tmp/ripe-atlas-5120-dryrun-after-remove.log 2>&1
cat /tmp/ripe-atlas-5120-dryrun-after-remove.log

if grep -q 'Collected errors' /tmp/ripe-atlas-5120-dryrun-after-remove.log; then
    fail "Dry-run still has errors. Aborting."
fi

if grep -q 'Cannot install package' /tmp/ripe-atlas-5120-dryrun-after-remove.log; then
    fail "Dry-run cannot install package. Aborting."
fi

if grep -q 'libopenssl3' /tmp/ripe-atlas-5120-dryrun-after-remove.log; then
    fail "Dry-run wants libopenssl3. Aborting."
fi

if grep -q 'chrony wants to install file' /tmp/ripe-atlas-5120-dryrun-after-remove.log; then
    fail "Dry-run has chrony file clash. Aborting."
fi

section "Install RIPE Atlas 5120"

run opkg install "$COMMON_IPK" "$PROBE_IPK" || fail "Install failed."

section "Enable/restart service"

if [ -x /etc/init.d/ripe-atlas ]; then
    /etc/init.d/ripe-atlas enable || true
    /etc/init.d/ripe-atlas restart || /etc/init.d/ripe-atlas start || true
else
    printf 'WARNING: /etc/init.d/ripe-atlas not found.\n'
fi

section "Post-install status"

opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|openssh|bzip2' || true

printf '\nInit script status:\n'
/etc/init.d/ripe-atlas status 2>&1 || true

printf '\nProcesses:\n'
ps w | awk '/[r]ipe|[a]tlas/ { print }' || true

printf '\nRecent logs:\n'
logread | grep -Ei 'ripe|atlas|probe|error|fail|cannot|denied|not found' | tail -200 || true

printf '\nPublic key path for RIPE Atlas UI, if needed:\n'
ls -l /etc/ripe-atlas/probe_key.pub 2>/dev/null || true

section "Done"

cat <<EOF
Install attempt complete.

Backup:
  $BACKUP_DIR

Next checks:
  /etc/init.d/ripe-atlas status
  ubus call service list '{"name":"ripe-atlas","verbose":true}'
  ps w | grep -Ei '[r]ipe|[a]tlas'
  logread -f

If the service is running but the existing probe does not come online, update the
public key on the RIPE Atlas probe settings page using:

  cat /etc/ripe-atlas/probe_key.pub
EOF
