#!/bin/bash
# Arch Linux ARM with Xfce, on X11 with LightDM.
#
#     build/arch-xfce.sh OUT
set -euo pipefail
. "$(dirname "$0")/lib.sh"

out="$1"
work=/var/tmp/arch-xfce
root="$work/rootfs"
rm -rf "$work"
mkdir -p "$root"

arch_base "$root" "$work"
in_root "$root" pacman -S --noconfirm --needed \
    xfce4 mousepad network-manager-applet lightdm lightdm-gtk-greeter \
    xorg-server xorg-xrandr xf86-input-libinput firefox noto-fonts mesa-utils
in_root "$root" systemctl enable lightdm
in_root "$root" systemctl set-default graphical.target
# Arch's LightDM logs in automatically only users in an "autologin" group,
# which the owner, made by cloud-init on the first boot, isn't: the owner is
# the one user it's set up for (vendor-data/arch-xfce.yaml), so it's dropped.
sed -i '/pam_succeed_if.so user ingroup autologin/d' "$root/etc/pam.d/lightdm-autologin"
x11_follows_display "$root"
arch_finish "$root"
common_rootfs "$root"

normalize_kernel "$root/boot/Image" "$work/vmlinuz"
cp "$root/boot/initramfs-linux.img" "$work/initrd.img"
make_ext4_disk "$root" "$work/disk.img"
rm -rf "$root"

package_image "$work" "$out" arch-xfce "Arch Linux" "$(date -u +%Y.%m.%d)" "Xfce" "console=ttyAMA0 root=/dev/vda rw"
