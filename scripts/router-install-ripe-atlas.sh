#!/bin/sh
# Install or upgrade RIPE Atlas packages on a GL.iNet/OpenWrt router.
# POSIX sh. Run on the router after copying the two .ipk files to /tmp.

set -u

RIPE_VERSION="${RIPE_VERSION:-5130}"
PACKAGE_RELEASE="${PACKAGE_RELEASE:-1}"
PACKAGE_ARCH="${PACKAGE_ARCH:-aarch64_cortex-a53}"
COMMON_IPK="${COMMON_IPK:-/tmp/ripe-atlas-common_${RIPE_VERSION}-${PACKAGE_RELEASE}_chrony-nts_${PACKAGE_ARCH}.ipk}"
PROBE_IPK="${PROBE_IPK:-/tmp/ripe-atlas-probe_${RIPE_VERSION}-${PACKAGE_RELEASE}_${PACKAGE_ARCH}.ipk}"
BACKUP_DIR="${BACKUP_DIR:-/root/ripe-atlas-backup-$(date +%Y%m%d-%H%M%S)}"
ASSUME_YES="${ASSUME_YES:-0}"
DRYRUN_BEFORE="$BACKUP_DIR/dryrun-before-remove.log"
DRYRUN_AFTER="$BACKUP_DIR/dryrun-after-remove.log"
KEY_HASH_BEFORE=""

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

user_name_for_id() {
    awk -F: -v id="$1" '$3 == id { print $1; exit }' /etc/passwd
}

user_id_for_name() {
    awk -F: -v name="$1" '$1 == name { print $3; exit }' /etc/passwd
}

group_name_for_id() {
    awk -F: -v id="$1" '$3 == id { print $1; exit }' /etc/group
}

group_id_for_name() {
    awk -F: -v name="$1" '$1 == name { print $3; exit }' /etc/group
}

check_user_id() {
    expected_name="$1"
    expected_id="$2"
    actual_name="$(user_name_for_id "$expected_id")"
    actual_id="$(user_id_for_name "$expected_name")"

    if [ -n "$actual_name" ] && [ "$actual_name" != "$expected_name" ]; then
        fail "UID $expected_id belongs to unrelated user $actual_name."
    fi
    if [ -n "$actual_id" ] && [ "$actual_id" != "$expected_id" ]; then
        printf 'WARNING: existing user %s has UID %s; it will be preserved.\n' "$expected_name" "$actual_id" >&2
    fi
}

check_group_id() {
    expected_name="$1"
    expected_id="$2"
    actual_name="$(group_name_for_id "$expected_id")"
    actual_id="$(group_id_for_name "$expected_name")"

    if [ -n "$actual_name" ] && [ "$actual_name" != "$expected_name" ]; then
        fail "GID $expected_id belongs to unrelated group $actual_name."
    fi
    if [ -n "$actual_id" ] && [ "$actual_id" != "$expected_id" ]; then
        printf 'WARNING: existing group %s has GID %s; it will be preserved.\n' "$expected_name" "$actual_id" >&2
    fi
}

section "Preflight"

[ "$(id -u)" = "0" ] || fail "Run as root on the router."
command -v opkg >/dev/null 2>&1 || fail "opkg not found."
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum not found."
command -v readlink >/dev/null 2>&1 || fail "readlink not found."

[ -f "$COMMON_IPK" ] || fail "Missing $COMMON_IPK"
[ -f "$PROBE_IPK" ] || fail "Missing $PROBE_IPK"

printf 'Package files:\n'
ls -lh "$COMMON_IPK" "$PROBE_IPK"

printf '\nArchitecture:\n'
opkg print-architecture
opkg print-architecture | awk '{ print $2 }' | grep -qx "$PACKAGE_ARCH" || {
    fail "Router does not advertise package architecture $PACKAGE_ARCH."
}

printf '\nRIPE Atlas package account IDs:\n'
check_user_id ripe-atlas 3333
check_user_id ripe-atlas-measurement 3334
check_group_id ripe-atlas 3333

printf '\nRelated installed packages:\n'
opkg list-installed | grep -Ei 'ripe|atlas|chrony|openssl|openssh|bzip2' || true

if opkg list-installed | grep -q '^atlas-sw-probe '; then
    fail "Legacy atlas-sw-probe migration is not automated because its package conflict prevents a conclusive pre-removal dry-run. Upgrade to ripe-atlas-* 5120 first."
fi

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
opkg files ripe-atlas-common > "$BACKUP_DIR/ripe-atlas-common-files.txt" 2>&1 || true
opkg info ripe-atlas-common > "$BACKUP_DIR/ripe-atlas-common-info.txt" 2>&1 || true
opkg files ripe-atlas-probe > "$BACKUP_DIR/ripe-atlas-probe-files.txt" 2>&1 || true
opkg info ripe-atlas-probe > "$BACKUP_DIR/ripe-atlas-probe-info.txt" 2>&1 || true

cp -a /etc/atlas "$BACKUP_DIR/etc-atlas" 2>/dev/null || true
cp -a /etc/ripe-atlas "$BACKUP_DIR/etc-ripe-atlas" 2>/dev/null || true
cp -a /etc/config/ripe-atlas "$BACKUP_DIR/ripe-atlas.uci" 2>/dev/null || true
cp -a /var/atlas-probe "$BACKUP_DIR/var-atlas-probe" 2>/dev/null || true
cp -a /var/lib/ripe-atlas "$BACKUP_DIR/var-lib-ripe-atlas" 2>/dev/null || true
cp -a /usr/libexec/atlas-probe-scripts/data "$BACKUP_DIR/atlas-probe-scripts-data" 2>/dev/null || true

find /etc /var /usr/libexec \( -iname '*atlas*' -o -iname '*ripe*' \) > "$BACKUP_DIR/atlas-ripe-paths.txt" 2>/dev/null || true

if [ -f /etc/ripe-atlas/probe_key ]; then
    KEY_HASH_BEFORE="$(sha256sum /etc/ripe-atlas/probe_key)"
    printf '%s\n' "$KEY_HASH_BEFORE" > "$BACKUP_DIR/probe-key-sha256-before.txt"
fi

printf 'Backup created: %s\n' "$BACKUP_DIR"

section "Update package lists"

run opkg update || fail "opkg update failed."

section "Dry-run install before removing old package"

if ! opkg --noaction install "$COMMON_IPK" "$PROBE_IPK" > "$DRYRUN_BEFORE" 2>&1; then
    cat "$DRYRUN_BEFORE"
    fail "Initial dry-run install failed."
fi
cat "$DRYRUN_BEFORE"

if grep -q 'libopenssl3' "$DRYRUN_BEFORE"; then
    fail "Package wants libopenssl3. Wrong build for this firmware."
fi

if grep -q 'chrony wants to install file' "$DRYRUN_BEFORE"; then
    fail "Package still clashes with chrony-nts. Use repacked common package."
fi

section "Confirmation"

cat <<EOF
About to:
  1. Stop Atlas/RIPE services if present.
  2. Remove the generated registration-server cache if present.
  3. Dry-run install RIPE Atlas $RIPE_VERSION again.
  4. Install or upgrade RIPE Atlas $RIPE_VERSION.
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

section "Remove generated registration-server cache"

if [ -f /etc/ripe-atlas/reg_servers.sh ]; then
    run rm -f /etc/ripe-atlas/reg_servers.sh || fail "Could not remove stale registration-server cache."
else
    printf 'No generated registration-server cache present.\n'
fi

section "Dry-run install after service stop"

if ! opkg --noaction install "$COMMON_IPK" "$PROBE_IPK" > "$DRYRUN_AFTER" 2>&1; then
    cat "$DRYRUN_AFTER"
    fail "Dry-run install command failed after service stop."
fi
cat "$DRYRUN_AFTER"

if grep -q 'Collected errors' "$DRYRUN_AFTER"; then
    fail "Dry-run still has errors. Aborting."
fi

if grep -q 'Cannot install package' "$DRYRUN_AFTER"; then
    fail "Dry-run cannot install package. Aborting."
fi

if grep -q 'libopenssl3' "$DRYRUN_AFTER"; then
    fail "Dry-run wants libopenssl3. Aborting."
fi

if grep -q 'chrony wants to install file' "$DRYRUN_AFTER"; then
    fail "Dry-run has chrony file clash. Aborting."
fi

section "Install RIPE Atlas $RIPE_VERSION"

run opkg install "$COMMON_IPK" "$PROBE_IPK" || fail "Install failed."

opkg list-installed | grep -q "^ripe-atlas-common - ${RIPE_VERSION}-${PACKAGE_RELEASE}$" || {
    fail "ripe-atlas-common $RIPE_VERSION-$PACKAGE_RELEASE is not installed."
}
opkg list-installed | grep -q "^ripe-atlas-probe - ${RIPE_VERSION}-${PACKAGE_RELEASE}$" || {
    fail "ripe-atlas-probe $RIPE_VERSION-$PACKAGE_RELEASE is not installed."
}

if [ -n "$KEY_HASH_BEFORE" ]; then
    [ -f /etc/ripe-atlas/probe_key ] || fail "Existing probe private key disappeared during upgrade."
    [ "$(sha256sum /etc/ripe-atlas/probe_key)" = "$KEY_HASH_BEFORE" ] || {
        fail "Existing probe private key changed during upgrade."
    }
fi

grep -q '^reg-05\.prod\.atlas\.ripe\.net ssh-ed25519 ' /usr/share/ripe-atlas/known_hosts.reg || {
    fail "RIPE Atlas 5130 registration host keys are missing."
}
grep -q '^evping[[:space:]]*= ssx root\.ripe-atlas$' /usr/share/ripe-atlas/measurement.conf || {
    fail "Raw-socket measurement privilege configuration is missing."
}
[ -u /usr/lib/ripe-atlas/measurement/busybox ] || fail "Measurement busybox is not setuid."

section "Enable/restart service"

if [ -x /etc/init.d/ripe-atlas ]; then
    /etc/init.d/ripe-atlas enable || true
    /etc/init.d/ripe-atlas restart || /etc/init.d/ripe-atlas start || fail "RIPE Atlas service did not start."
else
    fail "/etc/init.d/ripe-atlas not found."
fi

configured_mode="$(uci -q get ripe-atlas.@ripe-atlas[0].mode 2>/dev/null || true)"
case "$configured_mode" in
    dev|test) expected_reg_host="reg-03.${configured_mode}.atlas.ripe.net" ;;
    prod|'') expected_reg_host="reg-05.prod.atlas.ripe.net" ;;
    *) fail "Unexpected RIPE Atlas mode after installation: $configured_mode" ;;
esac

tries=0
while [ "$tries" -lt 10 ] && ! grep -Fqx "REG_1_HOST=${expected_reg_host}" /etc/ripe-atlas/reg_servers.sh 2>/dev/null; do
    tries=$((tries + 1))
    sleep 1
done
grep -Fqx "REG_1_HOST=${expected_reg_host}" /etc/ripe-atlas/reg_servers.sh || {
    fail "RIPE Atlas did not generate the 5130 registration-server cache for mode $configured_mode."
}

configured_http_port="$(uci -q get ripe-atlas.@ripe-atlas[0].http_post_port 2>/dev/null || true)"
case "$configured_http_port" in
    ''|0) ;;
    *)
        grep -q "^HTTP_POST_PORT=${configured_http_port}$" /etc/ripe-atlas/config.txt || {
            fail "Generated RIPE Atlas config does not contain the configured HTTP post port."
        }
        ;;
esac

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
