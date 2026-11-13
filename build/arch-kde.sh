#!/bin/bash
# Arch Linux ARM with KDE Plasma.
#
#     build/arch-kde.sh OUT
set -euo pipefail
. "$(dirname "$0")/lib.sh"

out="$1"
work=/var/tmp/arch-kde
root="$work/rootfs"
rm -rf "$work"
mkdir -p "$root"

arch_base "$root" "$work"
in_root "$root" pacman -S --noconfirm --needed \
    plasma-desktop sddm sddm-kcm plasma-nm kscreen breeze breeze-gtk kde-gtk-config \
    konsole dolphin firefox noto-fonts mesa-utils
in_root "$root" systemctl enable sddm
in_root "$root" systemctl set-default graphical.target
arch_finish "$root"
common_rootfs "$root"

normalize_kernel "$root/boot/Image" "$work/vmlinuz"
cp "$root/boot/initramfs-linux.img" "$work/initrd.img"
make_ext4_disk "$root" "$work/disk.img"
rm -rf "$root"

package_image "$work" "$out" arch-kde "Arch Linux" "$(date -u +%Y.%m.%d)" "KDE Plasma" "console=ttyAMA0 root=/dev/vda rw"
