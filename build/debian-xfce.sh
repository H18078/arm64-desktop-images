#!/bin/bash
# Debian 13 (trixie) with Xfce, on X11 with LightDM.
#
#     build/debian-xfce.sh OUT
set -euo pipefail
. "$(dirname "$0")/lib.sh"

out="$1"
work=/var/tmp/debian-xfce
root="$work/rootfs"
rm -rf "$work"
mkdir -p "$work"

debian_xfce_rootfs "$root"
common_rootfs "$root"
in_root "$root" apt-get clean
rm -rf "$root"/var/lib/apt/lists/*

normalize_kernel "$(ls "$root"/boot/vmlinuz-* | head -1)" "$work/vmlinuz"
cp "$(ls "$root"/boot/initrd.img-* | head -1)" "$work/initrd.img"
make_ext4_disk "$root" "$work/disk.img"
rm -rf "$root"

package_image "$work" "$out" debian-xfce "Debian" "13" "Xfce" "console=ttyAMA0 root=/dev/vda rw"
