#!/bin/sh
# Collect RIPE Atlas debug information from a GL.iNet/OpenWrt router.
# Read-only. Does not print private key contents.

OUT="${OUT:-/tmp/ripe-atlas-debug-$(date +%Y%m%d-%H%M%S).txt}"

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

run() {
    printf '\n+ %s\n' "$*"
    "$@" 2>&1 || true
}

{
section "System info"
run uname -a
run date
run uptime

section "OpenWrt / GL.iNet release"
run cat /etc/openwrt_release
run cat /etc/os-release
run cat /etc/glversion
run cat /etc/board.json

section "opkg architecture"
run opkg print-architecture

section "Installed RIPE / Atlas / time / crypto packages"
opkg list-installed 2>/dev/null | grep -Ei 'ripe|atlas|chrony|openssl|openssh|bzip2|ca-bundle|ca-certificates' || true

section "RIPE package metadata"
run opkg info ripe-atlas-common
run opkg info ripe-atlas-probe
run opkg info atlas-sw-probe

section "RIPE package files"
run opkg files ripe-atlas-common
run opkg files ripe-atlas-probe

section "RIPE account IDs"
awk -F: '$1 == "ripe-atlas" || $1 == "ripe-atlas-measurement" || $3 == 3333 || $3 == 3334 { print FILENAME ":" $0 }' /etc/passwd /etc/group 2>/dev/null || true

section "RIPE configuration and registration servers"
run uci show ripe-atlas
run cat /etc/ripe-atlas/mode
run cat /etc/ripe-atlas/config.txt
run cat /etc/ripe-atlas/reg_servers.sh
run cat /usr/share/ripe-atlas/known_hosts.reg
run ls -l /usr/lib/ripe-atlas/measurement/busybox
run cat /usr/share/ripe-atlas/measurement.conf

section "Init scripts"
for init_script in /etc/init.d/*; do
    [ -e "$init_script" ] || continue
    init_name="${init_script##*/}"
    case "$init_name" in
        *[Rr][Ii][Pp][Ee]*|*[Aa][Tt][Ll][Aa][Ss]*|*[Cc][Hh][Rr][Oo][Nn][Yy]*)
            ls -l "$init_script"
            ;;
    esac
done

section "RIPE init status"
if [ -x /etc/init.d/ripe-atlas ]; then
    run /etc/init.d/ripe-atlas status
    /etc/init.d/ripe-atlas enabled >/dev/null 2>&1 && echo "ripe-atlas enabled: yes" || echo "ripe-atlas enabled: no"
else
    echo "/etc/init.d/ripe-atlas not found"
fi

section "procd service detail"
run ubus call service list '{"name":"ripe-atlas","verbose":true}'

section "Processes"
ps w | awk '/[r]ipe|[a]tlas|[c]hrony|[c]hronyd/ { print }' || true

section "Recent logs: RIPE / Atlas / probe"
logread 2>/dev/null | grep -Ei 'ripe|atlas|probe' | tail -250 || true

section "Recent logs: errors/warnings"
logread 2>/dev/null | grep -Ei 'ripe|atlas|probe|error|failed|fail|cannot|missing|permission|denied|not found|segfault|crash' | tail -300 || true

section "Controller SSH status"
run cat /var/run/ripe-atlas/status/ssh_err.txt

section "Chrony"
if [ -x /etc/init.d/chronyd ]; then
    run /etc/init.d/chronyd status
fi
run chronyc tracking
run chronyc sources -v

section "RIPE/Atlas paths"
find /etc /var /usr /tmp \( -iname '*ripe*' -o -iname '*atlas*' \) 2>/dev/null | sort || true

section "Data dirs"
for d in \
    /etc/ripe-atlas \
    /etc/atlas \
    /var/atlas-probe \
    /var/lib/ripe-atlas \
    /var/spool/ripe-atlas \
    /var/spool/ripe-atlas/data \
    /var/spool/ripe-atlas/data/new \
    /var/spool/ripe-atlas/data/out \
    /usr/libexec/atlas-probe-scripts \
    /usr/libexec/atlas-probe-scripts/data \
    /usr/libexec/atlas-probe-scripts/data/out \
    /tmp/log
do
    printf '\n--- %s ---\n' "$d"
    ls -lah "$d" 2>/dev/null || true
done

section "Key/state files without private key contents"
find /etc /var /usr/libexec /tmp \( -iname '*key*' -o -iname '*.pub' -o -iname '*status*' -o -iname '*probe*' \) 2>/dev/null | sort || true

printf '\n--- public key previews only ---\n'
for f in /etc/ripe-atlas/probe_key.pub /etc/atlas/probe_key.pub; do
    printf '\n%s\n' "$f"
    ls -l "$f" 2>/dev/null || true
    cat "$f" 2>/dev/null || true
done

section "Executable/linking check"
for f in $(find /usr /bin /sbin -type f \( -iname '*ripe*' -o -iname '*atlas*' \) 2>/dev/null | sort); do
    printf '\n--- %s ---\n' "$f"
    ls -l "$f" 2>/dev/null || true
    file "$f" 2>/dev/null || true
    ldd "$f" 2>&1 || true
done

section "Network basics"
run ip addr
run ip route
run ip -6 route
run cat /etc/resolv.conf
run nslookup atlas.ripe.net
run nslookup ctr-atlas.ripe.net

section "Disk and memory"
run df -h
run free

section "Last 300 raw log lines"
logread 2>/dev/null | tail -300 || true

section "Done"
echo "Output file: $OUT"
} 2>&1 | tee "$OUT"

printf '\nSaved debug output to:\n%s\n' "$OUT"
