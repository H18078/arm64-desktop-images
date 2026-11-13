#!/bin/bash
# Debian 13 (trixie) with KDE Plasma.
#
#     build/debian-kde.sh OUT
set -euo pipefail
. "$(dirname "$0")/lib.sh"

out="$1"
work=/var/tmp/debian-kde
root="$work/rootfs"
mirror=http://deb.debian.org/debian
rm -rf "$work"
mkdir -p "$work"

mmdebstrap --arch=arm64 --variant=important --mode=root \
    --include=linux-image-arm64,systemd-sysv,systemd-resolved,dbus,sudo,locales,ca-certificates,cloud-init,network-manager,openssh-server \
    trixie "$root" \
    "deb $mirror trixie main contrib non-free-firmware" \
    "deb $mirror trixie-updates main contrib non-free-firmware" \
    "deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware"

# Plasma with what it recommends, but no software centre: its update checks
# and Flatpak are slow to start and of no use here.
cat > "$root/etc/apt/preferences.d/no-software-centre" <<'EOF'
Package: plasma-discover* packagekit* flatpak* apper*
Pin: release *
Pin-Priority: -1
EOF
in_root "$root" apt-get update
in_root "$root" env DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends \
    kde-plasma-desktop sddm konsole dolphin firefox-esr fonts-noto-core mesa-utils

in_root "$root" systemctl set-default graphical.target
in_root "$root" apt-mark hold linux-image-arm64 "$(basename "$(ls -d "$root"/lib/modules/* | head -1)" | sed 's/^/linux-image-/')"
echo 'LANG=C.UTF-8' > "$root/etc/default/locale"
common_rootfs "$root"
in_root "$root" apt-get clean
rm -rf "$root"/var/lib/apt/lists/*

normalize_kernel "$(ls "$root"/boot/vmlinuz-* | head -1)" "$work/vmlinuz"
cp "$(ls "$root"/boot/initrd.img-* | head -1)" "$work/initrd.img"
make_ext4_disk "$root" "$work/disk.img"
rm -rf "$root"

package_image "$work" "$out" debian-kde "Debian" "13" "KDE Plasma" "console=ttyAMA0 root=/dev/vda rw"
