#!/bin/sh
# Build RIPE Atlas 5120 OpenWrt packages for GL.iNet routers.
#
# Validated target:
#   GL.iNet GL-XE3000 / Puli AX
#   GL.iNet 4.x / OpenWrt 21.02-SNAPSHOT-derived firmware
#   aarch64_cortex-a53
#   OpenSSL 1.1 generation
#
# This script is POSIX sh. It builds packages only; it does not touch a router.

set -eu

OPENWRT_VERSION="${OPENWRT_VERSION:-v22.03.5}"
RIPE_TAG="${RIPE_TAG:-5120}"
BUILD_ROOT="${BUILD_ROOT:-$(pwd)/.build}"
TREE_DIR="${TREE_DIR:-$BUILD_ROOT/openwrt-22-ripe}"
DIST_DIR="${DIST_DIR:-$(pwd)/dist}"
JOBS="${JOBS:-1}"
ASSUME_YES="${ASSUME_YES:-0}"
SCRIPT_DIR="$(CDPATH=; cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

RIPE_FEED_LINE="src-git ripeatlas https://github.com/RIPE-NCC/ripe-atlas-software-probe.git;$RIPE_TAG"

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

fail() {
    printf '\nERROR: %s\n' "$1" >&2
    exit 1
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

check_cmd() {
    have_cmd "$1" || fail "Missing command: $1"
}

dpkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

need_apt_package() {
    pkg="$1"
    if ! dpkg_installed "$pkg"; then
        MISSING_PKGS="${MISSING_PKGS}${pkg}
"
    fi
}

install_missing_packages() {
    if [ -z "$MISSING_PKGS" ]; then
        printf 'All checked apt packages are already installed.\n'
        return 0
    fi

    section "Missing apt packages"
    printf '%s' "$MISSING_PKGS"

    if [ "$ASSUME_YES" != "1" ]; then
        printf '\nInstall missing packages with apt now? [y/N] '
        read -r ans
        case "$ans" in
            y|Y|yes|YES) ;;
            *) fail "Missing build dependencies. Re-run with ASSUME_YES=1 to install automatically." ;;
        esac
    fi

    set --
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        set -- "$@" "$pkg"
    done <<EOF
$MISSING_PKGS
EOF

    if [ "$(id -u)" = "0" ]; then
        apt-get update
        apt-get install -y "$@"
    else
        if ! have_cmd sudo; then
            fail "sudo missing. Install packages manually or run as root."
        fi
        sudo apt-get update
        sudo apt-get install -y "$@"
    fi
}

show_control() {
    pkg="$1"
    tmp="$(mktemp -d)"
    cwd="$(pwd)"

    if ar t "$pkg" >/dev/null 2>&1; then
        (
            cd "$tmp"
            ar x "$cwd/$pkg"
            if [ -f control.tar.gz ]; then
                tar -xzf control.tar.gz -O ./control
            elif [ -f control.tar.xz ]; then
                tar -xJf control.tar.xz -O ./control
            elif [ -f control.tar.zst ]; then
                tar --zstd -xf control.tar.zst -O ./control
            else
                echo "ERROR: no control archive found in $pkg" >&2
                exit 1
            fi
        )
    else
        (
            cd "$tmp"
            tar -xf "$cwd/$pkg"
            if [ -f control.tar.gz ]; then
                tar -xzf control.tar.gz -O ./control
            elif [ -f control.tar.xz ]; then
                tar -xJf control.tar.xz -O ./control
            elif [ -f control.tar.zst ]; then
                tar --zstd -xf control.tar.zst -O ./control
            else
                echo "ERROR: no control archive found in $pkg" >&2
                exit 1
            fi
        )
    fi

    rm -rf "$tmp"
}

section "Host preflight"

[ "$(uname -s)" = "Linux" ] || fail "This script expects Linux."

if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf 'Detected OS: %s\n' "${PRETTY_NAME:-unknown}"
fi

for c in sh awk sed grep cut sort tail head tee find xargs mktemp tar gzip file python3 git make; do
    check_cmd "$c"
done

have_cmd apt-get || fail "apt-get not found. This script is intended for Debian 13."

section "Check apt build dependencies"

MISSING_PKGS=""

for pkg in \
    build-essential \
    g++ \
    gawk \
    gettext \
    git \
    libncurses-dev \
    libssl-dev \
    python3 \
    python3-dev \
    python3-setuptools \
    python3-venv \
    rsync \
    unzip \
    zlib1g-dev \
    file \
    wget \
    curl \
    ca-certificates \
    perl \
    patch \
    tar \
    gzip \
    xz-utils \
    zstd \
    binutils \
    make
do
    need_apt_package "$pkg"
done

install_missing_packages

section "Check Python distutils compatibility"

if python3 -c 'import distutils' >/dev/null 2>&1; then
    printf 'python3 import distutils: ok\n'
else
    fail "python3 cannot import distutils. Install setuptools/distutils compatibility packages and retry."
fi

section "Prepare OpenWrt tree"

mkdir -p "$BUILD_ROOT" "$DIST_DIR"

if [ ! -d "$TREE_DIR/.git" ]; then
    git clone https://git.openwrt.org/openwrt/openwrt.git "$TREE_DIR"
fi

cd "$TREE_DIR"

section "Checkout OpenWrt $OPENWRT_VERSION"

git fetch --tags
git checkout "$OPENWRT_VERSION"

section "Configure feeds"

if [ -f feeds.conf.default ]; then
    cp feeds.conf.default feeds.conf
else
    : > feeds.conf
fi

if ! grep -q 'RIPE-NCC/ripe-atlas-software-probe' feeds.conf; then
    printf '%s\n' "$RIPE_FEED_LINE" >> feeds.conf
fi

grep 'RIPE-NCC/ripe-atlas-software-probe' feeds.conf

section "Patch Ninja for Python 3.13"

mkdir -p tools/ninja/patches
cp "$REPO_ROOT/patches/openwrt-22.03.5/ninja/101-python313-shlex-instead-of-pipes.patch" \
   tools/ninja/patches/

section "Update/install feeds"

./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds update ripeatlas
./scripts/feeds install -p ripeatlas -a

section "Patch RIPE Atlas OpenWrt UCI config"

if patch -d feeds/ripeatlas -p1 --forward \
    < "$REPO_ROOT/patches/ripe-atlas-software-probe/100-openwrt-uci-http-post-port.patch"; then
    printf 'Applied RIPE Atlas HTTP_POST_PORT UCI patch.\n'
elif grep -q 'http_post_port:uinteger:0' feeds/ripeatlas/openwrt/files/ripe-atlas.init; then
    printf 'RIPE Atlas HTTP_POST_PORT UCI patch already applied.\n'
else
    fail "Could not apply RIPE Atlas HTTP_POST_PORT UCI patch."
fi

[ -f package/feeds/ripeatlas/openwrt/Makefile ] || {
    find package/feeds/ripeatlas -maxdepth 5 -name Makefile -print 2>/dev/null || true
    fail "RIPE OpenWrt package Makefile not found."
}

section "Create OpenWrt .config"

cp "$REPO_ROOT/configs/openwrt-22.03.5/mediatek-mt7622-ripe-atlas.config" .config

make defconfig

ARCH_PACKAGES="$(grep '^CONFIG_TARGET_ARCH_PACKAGES=' .config | cut -d '"' -f 2 || true)"
printf 'CONFIG_TARGET_ARCH_PACKAGES=%s\n' "$ARCH_PACKAGES"

[ "$ARCH_PACKAGES" = "aarch64_cortex-a53" ] || fail "Expected aarch64_cortex-a53 package architecture."

section "Build tools"

make -j"$JOBS" tools/install V=s

section "Build toolchain"

make -j"$JOBS" toolchain/install V=s

section "Build RIPE Atlas packages"

make -j"$JOBS" package/feeds/ripeatlas/openwrt/compile V=s

section "Find output packages"

PKG_DIR="bin/packages/aarch64_cortex-a53/ripeatlas"
COMMON_ORIG="$PKG_DIR/ripe-atlas-common_5120-1_aarch64_cortex-a53.ipk"
PROBE_ORIG="$PKG_DIR/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk"
COMMON_REPACK="$PKG_DIR/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk"

find bin -type f -name '*ripe*atlas*.ipk' -print

[ -f "$COMMON_ORIG" ] || fail "Missing $COMMON_ORIG"
[ -f "$PROBE_ORIG" ] || fail "Missing $PROBE_ORIG"

section "Verify package metadata"

printf '\n=== ripe-atlas-common original control ===\n'
show_control "$COMMON_ORIG"

printf '\n=== ripe-atlas-probe control ===\n'
show_control "$PROBE_ORIG"

if show_control "$COMMON_ORIG" | grep -q 'libopenssl3'; then
    fail "ripe-atlas-common depends on libopenssl3; wrong generation for tested GL.iNet firmware."
fi

if show_control "$COMMON_ORIG" | grep -q 'libopenssl1.1'; then
    printf 'OpenSSL dependency: libopenssl1.1 ok\n'
else
    printf 'WARNING: libopenssl1.1 not found in dependency metadata.\n' >&2
fi

section "Repack ripe-atlas-common: chrony -> chrony-nts"

WORK="$(mktemp -d)"
PKGWORK="$WORK/pkg"
CONTROL_DIR="$WORK/control"
mkdir -p "$PKGWORK" "$CONTROL_DIR"

if ar t "$COMMON_ORIG" >/dev/null 2>&1; then
    PKG_FORMAT="ar"
    (
        cd "$PKGWORK"
        ar x "$TREE_DIR/$COMMON_ORIG"
    )
else
    PKG_FORMAT="tar"
    (
        cd "$PKGWORK"
        tar -xf "$TREE_DIR/$COMMON_ORIG"
    )
fi

CONTROL_TAR=""
for candidate in control.tar.gz control.tar.xz control.tar.zst control.tar; do
    if [ -f "$PKGWORK/$candidate" ]; then
        CONTROL_TAR="$candidate"
        break
    fi
done

DATA_TAR=""
for candidate in data.tar.gz data.tar.xz data.tar.zst data.tar; do
    if [ -f "$PKGWORK/$candidate" ]; then
        DATA_TAR="$candidate"
        break
    fi
done

[ -n "$CONTROL_TAR" ] || fail "No control.tar.* found."
[ -n "$DATA_TAR" ] || fail "No data.tar.* found."
[ -f "$PKGWORK/debian-binary" ] || fail "No debian-binary found."

case "$CONTROL_TAR" in
    control.tar.gz)  tar -xzf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" ;;
    control.tar.xz)  tar -xJf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" ;;
    control.tar.zst) tar --zstd -xf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" ;;
    control.tar)     tar -xf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" ;;
    *) fail "Unsupported control archive: $CONTROL_TAR" ;;
esac

[ -f "$CONTROL_DIR/control" ] || fail "control file not found."

printf 'Original Depends:\n'
grep '^Depends:' "$CONTROL_DIR/control" || true

python3 "$REPO_ROOT/scripts/rewrite-control-dependency.py" \
    "$CONTROL_DIR/control" chrony chrony-nts

printf 'Modified Depends:\n'
grep '^Depends:' "$CONTROL_DIR/control" || true

if grep '^Depends:' "$CONTROL_DIR/control" | grep -Eq '(^|[,[:space:]])chrony([,[:space:]]|$)'; then
    fail "plain chrony still appears in Depends."
fi

if ! grep '^Depends:' "$CONTROL_DIR/control" | grep -q 'chrony-nts'; then
    fail "chrony-nts not found in Depends."
fi

rm -f "$PKGWORK/$CONTROL_TAR"

case "$CONTROL_TAR" in
    control.tar.gz)  tar --numeric-owner --owner=0 --group=0 -czf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" . ;;
    control.tar.xz)  tar --numeric-owner --owner=0 --group=0 -cJf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" . ;;
    control.tar.zst) tar --numeric-owner --owner=0 --group=0 --zstd -cf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" . ;;
    control.tar)     tar --numeric-owner --owner=0 --group=0 -cf "$PKGWORK/$CONTROL_TAR" -C "$CONTROL_DIR" . ;;
    *) fail "Unsupported control archive: $CONTROL_TAR" ;;
esac

rm -f "$COMMON_REPACK"

(
    cd "$PKGWORK"
    if [ "$PKG_FORMAT" = "ar" ]; then
        ar rc "$TREE_DIR/$COMMON_REPACK" debian-binary "$CONTROL_TAR" "$DATA_TAR"
    else
        tar -czf "$TREE_DIR/$COMMON_REPACK" debian-binary "$CONTROL_TAR" "$DATA_TAR"
    fi
)

rm -rf "$WORK"

section "Copy final packages to dist"

mkdir -p "$DIST_DIR"

cp "$COMMON_REPACK" "$DIST_DIR/"
cp "$PROBE_ORIG" "$DIST_DIR/"

printf 'Final package files:\n'
ls -lh "$DIST_DIR"/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk \
       "$DIST_DIR"/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk

section "Final metadata"

printf '\n=== repacked common ===\n'
show_control "$COMMON_REPACK"

printf '\n=== probe ===\n'
show_control "$PROBE_ORIG"

section "Done"

cat <<EOF
Build complete.

Copy to router:

  scp -O \\
    "$DIST_DIR/ripe-atlas-common_5120-1_chrony-nts_aarch64_cortex-a53.ipk" \\
    "$DIST_DIR/ripe-atlas-probe_5120-1_aarch64_cortex-a53.ipk" \\
    root@192.168.8.1:/tmp/

Then run the router installer from this repository:

  scp -O scripts/router-install-ripe-atlas-5120.sh root@192.168.8.1:/tmp/
  ssh root@192.168.8.1 'sh /tmp/router-install-ripe-atlas-5120.sh'
EOF
