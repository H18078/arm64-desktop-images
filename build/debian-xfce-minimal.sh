#!/bin/bash
# Debian 13 (trixie) with Xfce, as debian-xfce but without what a virtual
# machine has no use for, so its desktop comes up sooner: no screen locker,
# colour management, network applet, sound server or Bonjour, and no
# handlers for other architectures' programs.
#
#     build/debian-xfce-minimal.sh OUT
set -euo pipefail
. "$(dirname "$0")/lib.sh"

out="$1"
work=/var/tmp/debian-xfce-minimal
root="$work/rootfs"
rm -rf "$work"
mkdir -p "$work"

debian_xfce_rootfs "$root"
# Switched off rather than removed, so each one comes back with a systemctl
# unmask, or by deleting its Hidden line.
in_root "$root" systemctl mask systemd-binfmt.service avahi-daemon.service avahi-daemon.socket colord.service
in_root "$root" systemctl --global mask pulseaudio.service pulseaudio.socket
for entry in light-locker xiccd nm-applet polkit-ukui-authentication-agent-1 xdg-user-dirs-kde \
        gnome-keyring-pkcs11 gnome-keyring-ssh pulseaudio; do
    file="$root/etc/xdg/autostart/$entry.desktop"
    if [ -e "$file" ]; then
        sed -i '/^\[Desktop Entry\]/a Hidden=true' "$file"
    fi
done
common_rootfs "$root"
in_root "$root" apt-get clean
rm -rf "$root"/var/lib/apt/lists/*

normalize_kernel "$(ls "$root"/boot/vmlinuz-* | head -1)" "$work/vmlinuz"
cp "$(ls "$root"/boot/initrd.img-* | head -1)" "$work/initrd.img"
make_ext4_disk "$root" "$work/disk.img"
rm -rf "$root"

package_image "$work" "$out" debian-xfce-minimal "Debian Minimal" "13" "Xfce" "console=ttyAMA0 root=/dev/vda rw"
