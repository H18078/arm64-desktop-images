#!/bin/bash
# Ubuntu 26.04 LTS (resolute) with GNOME, Ubuntu's own session.
#
#     build/ubuntu-gnome.sh OUT
set -euo pipefail
. "$(dirname "$0")/lib.sh"

out="$1"
work=/var/tmp/ubuntu-gnome
root="$work/rootfs"
mirror=http://ports.ubuntu.com/ubuntu-ports
rm -rf "$work"
mkdir -p "$work"

# No snaps: snapd wants a kernel and confinement this machine doesn't give it,
# and Ubuntu's Firefox and Thunderbird debs only install the snaps.
no_snaps='mkdir -p "$1/etc/apt/preferences.d" && printf "Package: snapd firefox thunderbird chromium-browser\nPin: release *\nPin-Priority: -1\n" > "$1/etc/apt/preferences.d/no-snaps"'

# The virtual kernel: the generic one without its firmware, which a VM has no
# use for. initramfs-tools rather than dracut, whose host-only images would
# fit the machine building this one.
mmdebstrap --arch=arm64 --variant=important --mode=root \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    --setup-hook="$no_snaps" \
    --include=initramfs-tools,linux-image-virtual,systemd-sysv,dbus,sudo,locales,ca-certificates,cloud-init,network-manager,openssh-server \
    resolute "$root" \
    "deb $mirror resolute main restricted universe" \
    "deb $mirror resolute-updates main restricted universe" \
    "deb $mirror resolute-security main restricted universe"

# The minimal desktop's dependencies, and of what it recommends, the parts
# that make it Ubuntu's GNOME (theme, fonts, terminal, viewers), not printing,
# Bluetooth, crash reporting or the first-login wizard.
in_root "$root" apt-get update
in_root "$root" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ubuntu-desktop-minimal \
    ptyxis gnome-text-editor loupe gnome-calculator gnome-keyring libpam-gnome-keyring \
    xdg-desktop-portal-gnome xdg-utils libglib2.0-bin gsettings-ubuntu-schemas \
    yaru-theme-gnome-shell yaru-theme-gtk yaru-theme-icon yaru-theme-sound ubuntu-wallpapers \
    fonts-ubuntu fonts-noto-core fonts-noto-color-emoji policykit-desktop-privileges \
    mesa-utils

in_root "$root" systemctl set-default graphical.target
kernel=$(basename "$(ls -d "$root"/usr/lib/modules/* | head -1)")
in_root "$root" apt-mark hold linux-image-virtual "linux-image-$kernel" "linux-modules-$kernel"
# The desktop needs virtio-gpu, a module here (virtio-gpu.ko.zst).
if ! find "$root/usr/lib/modules/$kernel" -name 'virtio-gpu.ko*' | grep -q . \
    && ! grep -q 'virtio-gpu' "$root/usr/lib/modules/$kernel/modules.builtin"; then
    echo "ubuntu-gnome: $kernel has no virtio_gpu" >&2
    exit 1
fi
echo 'LANG=C.UTF-8' > "$root/etc/default/locale"
common_rootfs "$root"
in_root "$root" apt-get clean
rm -rf "$root"/var/lib/apt/lists/*

normalize_kernel "$(ls "$root"/boot/vmlinuz-* | head -1)" "$work/vmlinuz"
cp "$(ls "$root"/boot/initrd.img-* | head -1)" "$work/initrd.img"
make_ext4_disk "$root" "$work/disk.img"
rm -rf "$root"

package_image "$work" "$out" ubuntu-gnome "Ubuntu" "26.04 LTS" "GNOME" "console=ttyAMA0 root=/dev/vda rw"
