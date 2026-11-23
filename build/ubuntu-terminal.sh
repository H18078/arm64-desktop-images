#!/bin/bash
# Ubuntu 26.04 LTS (resolute), terminal only: no desktop, no display manager.
#
#     build/ubuntu-terminal.sh OUT
#
# The same base as the desktop images, and nothing on top of it: the machine
# boots to a login prompt on the serial console (ttyAMA0), cloud-init reads
# the seed crate writes (the owner's account, hostname and time zone), and
# NetworkManager runs the network. linux-image-virtual is the kernel crate
# boots from outside the disk, so its packages are held at this version.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

out="$1"
work=/var/tmp/ubuntu-terminal
root="$work/rootfs"
mirror=http://ports.ubuntu.com/ubuntu-ports
rm -rf "$work"
mkdir -p "$work"

mmdebstrap --arch=arm64 --variant=important --mode=root \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    --include=initramfs-tools,linux-image-virtual,systemd-sysv,dbus,sudo,locales,ca-certificates,cloud-init,network-manager,openssh-server \
    resolute "$root" \
    "deb $mirror resolute main restricted universe" \
    "deb $mirror resolute-updates main restricted universe" \
    "deb $mirror resolute-security main restricted universe"

# No desktop: the console is where a user lands.
in_root "$root" systemctl set-default multi-user.target
kernel=$(basename "$(ls -d "$root"/usr/lib/modules/* | head -1)")
in_root "$root" apt-mark hold linux-image-virtual "linux-image-$kernel" "linux-modules-$kernel"
echo 'LANG=C.UTF-8' > "$root/etc/default/locale"
common_rootfs "$root"
in_root "$root" apt-get clean
rm -rf "$root"/var/lib/apt/lists/*

normalize_kernel "$(ls "$root"/boot/vmlinuz-* | head -1)" "$work/vmlinuz"
cp "$(ls "$root"/boot/initrd.img-* | head -1)" "$work/initrd.img"
make_ext4_disk "$root" "$work/disk.img"
rm -rf "$root"

# No vendor-data: a terminal needs nothing from cloud-init beyond the account
# crate's seed already gives it.
package_image "$work" "$out" ubuntu-terminal "Ubuntu" "26.04 LTS" "Terminal" "console=ttyAMA0 root=/dev/vda rw"
