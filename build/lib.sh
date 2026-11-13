# Steps every image shares, sourced by the image scripts.
#
# An image is three files: a kernel, an initrd and a raw disk holding a single
# filesystem (no partition table, the root at /dev/vda). The machine boots the
# kernel directly with the command line in image.json; there is no boot loader.
set -euo pipefail
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The settings each image gets in its root filesystem, whatever the distro.
#   ROOT  the root filesystem, being built
common_rootfs() {
    local root="$1"

    # cloud-init reads only a NoCloud seed: a small disk labelled CIDATA,
    # attached on the first boot, holding the user, password and hostname.
    # Nothing is probed over the network, and NetworkManager runs the network.
    mkdir -p "$root/etc/cloud/cloud.cfg.d"
    cat > "$root/etc/cloud/cloud.cfg.d/90-nocloud.cfg" <<'EOF'
datasource_list: [ NoCloud, None ]
network: {config: disabled}
EOF
    # The seed stays attached; the desktop doesn't show it as a drive.
    mkdir -p "$root/etc/udev/rules.d"
    cat > "$root/etc/udev/rules.d/90-hide-cidata.rules" <<'EOF'
ENV{ID_FS_LABEL}=="CIDATA|cidata", ENV{UDISKS_IGNORE}="1"
EOF

    # A login prompt on the serial console, advertising xterm-256color: what
    # the other end of the console emulates.
    mkdir -p "$root/etc/systemd/system/serial-getty@ttyAMA0.service.d"
    cat > "$root/etc/systemd/system/serial-getty@ttyAMA0.service.d/term.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear %I 115200 xterm-256color
EOF

    # The display manager starts after cloud-init has written the settings it
    # reads, such as the owner's autologin.
    mkdir -p "$root/etc/systemd/system/display-manager.service.d"
    cat > "$root/etc/systemd/system/display-manager.service.d/after-cloud-init.conf" <<'EOF'
[Unit]
After=cloud-config.service
EOF

    # Each machine makes its own identity on its first boot.
    : > "$root/etc/machine-id"
    rm -f "$root/var/lib/dbus/machine-id" "$root"/etc/ssh/ssh_host_*
    rm -rf "$root/var/lib/cloud"
}

# Runs a command inside ROOT, with /proc, /sys, /dev and DNS as a chroot needs
# them for package installs, and takes them away again.
#   ROOT CMD...
in_root() {
    local root="$1"; shift
    # The root a mount point of its own, as pacman needs to measure free space.
    mount --bind "$root" "$root"
    mount -t proc proc "$root/proc"
    mount -t sysfs sys "$root/sys"
    mount --rbind /dev "$root/dev"
    mount --make-rslave "$root/dev"
    local resolv="$root/etc/resolv.conf" saved=""
    if [ -e "$resolv" ] || [ -L "$resolv" ]; then
        saved="$root/etc/resolv.conf.build"
        mv "$resolv" "$saved"
    fi
    cp /etc/resolv.conf "$resolv"
    local status=0 pid
    chroot "$root" "$@" || status=$?
    # Daemons the command left running there (pacman-key's gpg-agent) would
    # keep /dev busy.
    for pid in $(ls /proc | grep -E '^[0-9]+$'); do
        [ "$(readlink "/proc/$pid/root" 2>/dev/null)" = "$(readlink -f "$root")" ] && kill "$pid" 2>/dev/null || true
    done
    sleep 0.2
    rm -f "$resolv"
    [ -z "$saved" ] || mv "$saved" "$resolv"
    umount -R "$root/dev" "$root/sys" "$root/proc" 2>/dev/null || umount -lR "$root/dev" "$root/sys" "$root/proc"
    umount "$root" 2>/dev/null || umount -l "$root"
    return $status
}

# An ext4 disk with ROOT's contents, a little larger than they are. The disk
# is grown on install, and cloud-init grows the filesystem into it.
#   ROOT  the root filesystem
#   DISK  the disk image to write
make_ext4_disk() {
    local root="$1" disk="$2" used_mib size_mib
    used_mib=$(du -sxm "$root" | cut -f1)
    size_mib=$(( (used_mib * 115 / 100 + 512 + 255) / 256 * 256 ))
    rm -f "$disk"
    truncate -s "${size_mib}M" "$disk"
    mkfs.ext4 -q -F -L root -d "$root" "$disk"
    e2fsck -fy "$disk" >/dev/null || [ $? -le 1 ]
    echo "disk: ${used_mib} MiB of files in a ${size_mib} MiB ext4 disk"
}

# The kernel as a plain arm64 Image: unwrapped from gzip or from an EFI zboot
# image, which the machine can't boot.
#   IN   the distro's kernel
#   OUT  the Image to write
normalize_kernel() {
    python3 - "$1" "$2" <<'EOF'
import gzip, struct, subprocess, sys, lzma
src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()

def unpack(payload, kind):
    if kind == "gzip":
        return gzip.decompress(payload)
    if kind in ("lzma", "xzkern"):
        return lzma.decompress(payload)
    if kind == "zstd":
        return subprocess.run(["zstd", "-dc"], input=payload, check=True, capture_output=True).stdout
    raise SystemExit(f"kernel: unknown compression {kind}")

def pe_section(data, wanted):
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        return None
    count = struct.unpack_from("<H", data, pe + 6)[0]
    table = pe + 24 + struct.unpack_from("<H", data, pe + 20)[0]
    for i in range(count):
        name, _, _, size, offset = struct.unpack_from("<8sIIII", data, table + 40 * i)
        if name.rstrip(b"\0") == wanted:
            return data[offset:offset + size]
    return None

# An EFI stub wrapping the kernel with device trees (Ubuntu's): the kernel is
# its .linux section.
if data[:2] == b"MZ" and data[4:8] != b"zimg" and data[0x38:0x3c] != b"ARM\x64":
    inner = pe_section(data, b".linux")
    if inner is not None:
        data = inner
if data[:2] == b"\x1f\x8b":
    data = gzip.decompress(data)
elif data[:2] == b"MZ" and data[4:8] == b"zimg":
    # EFI zboot: a stub, then the compressed Image at the header's offset.
    offset, size = struct.unpack_from("<II", data, 8)
    kind = data[24:56].split(b"\0")[0].decode()
    data = unpack(data[offset:offset + size], kind)
if data[0x38:0x3c] != b"ARM\x64":
    raise SystemExit("kernel: not an arm64 Image")
open(dst, "wb").write(data)
EOF
}

# The release files for one image, and ID.json describing them. The image's
# cloud-init vendor-data, from build/vendor-data/ID.yaml, goes in ID.json for
# the seed's vendor-data file, with {{user}} standing for the owner's name.
#   WORK    holding vmlinuz, initrd.img and disk.img
#   OUT     where the release files go
#   ID NAME VERSION DESKTOP CMDLINE
package_image() {
    local work="$1" out="$2" id="$3" name="$4" version="$5" desktop="$6" cmdline="$7"
    local vendor_data="$LIB_DIR/vendor-data/$id.yaml"
    local disk_size disk_sha
    disk_size=$(stat -c %s "$work/disk.img")
    disk_sha=$(sha256sum "$work/disk.img" | cut -d' ' -f1)
    mkdir -p "$out"
    cd "$out"
    rm -f "$id"-*
    # Compressed, then cut into parts a release can hold (2 GiB each at most).
    xz -T0 -6 --stdout "$work/disk.img" | split -b 1900M -d -a 2 - "$id-disk.img.xz.part"
    rm "$work/disk.img"
    cp "$work/vmlinuz" "$id-vmlinuz"
    cp "$work/initrd.img" "$id-initrd.img"
    python3 - "$id" "$name" "$version" "$desktop" "$cmdline" "$disk_size" "$disk_sha" "$vendor_data" <<'EOF'
import hashlib, json, os, sys
id_, name, version, desktop, cmdline, disk_size, disk_sha, vendor_data = sys.argv[1:]

def describe(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return {"file": path, "size": os.path.getsize(path), "sha256": h.hexdigest()}

parts = sorted(p for p in os.listdir(".") if p.startswith(f"{id_}-disk.img.xz.part"))
image = {
    "id": id_, "name": name, "version": version, "desktop": desktop,
    "cmdline": cmdline,
    "kernel": describe(f"{id_}-vmlinuz"),
    "initrd": describe(f"{id_}-initrd.img"),
    "disk": {"size": int(disk_size), "sha256": disk_sha, "compression": "xz",
             "parts": [describe(p) for p in parts]},
}
if os.path.exists(vendor_data):
    image["vendorData"] = open(vendor_data).read()
json.dump(image, open(f"{id_}.json", "w"), indent=2)
# Readable by the runner's user, which attests and uploads them.
for path in os.listdir("."):
    if path.startswith(id_):
        os.chmod(path, 0o644)
print(json.dumps(image, indent=2))
EOF
}

# Arch Linux ARM's generic aarch64 root filesystem, its keyring set up and
# its packages up to date.
#   ROOT  the root filesystem to make (empty)
#   WORK  where the download goes
arch_rootfs() {
    local root="$1" work="$2" tarball="ArchLinuxARM-aarch64-latest.tar.gz"
    # Over HTTP, the only way the download host serves it, and checked against
    # its signature by Arch Linux ARM's build key, from the keyring package at
    # a pinned commit.
    local keyring=https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/0b5418fc3f62860b191cd872cb2f933f9fc77841/core/archlinuxarm-keyring/archlinuxarm.gpg
    curl -fsSL -o "$work/archlinuxarm.gpg" "$keyring"
    echo "6ce771e853f04a38a5b533cb33e61f877b9b06b58b6db051eb8a15d737a2332f  $work/archlinuxarm.gpg" | sha256sum -c --quiet
    gpg --dearmor < "$work/archlinuxarm.gpg" > "$work/archlinuxarm.kbx"
    curl -fsSL -o "$work/$tarball" "http://os.archlinuxarm.org/os/$tarball"
    curl -fsSL -o "$work/$tarball.sig" "http://os.archlinuxarm.org/os/$tarball.sig"
    gpgv --keyring "$work/archlinuxarm.kbx" "$work/$tarball.sig" "$work/$tarball"
    bsdtar -xpf "$work/$tarball" -C "$root"
    rm "$work/$tarball"
    in_root "$root" pacman-key --init
    in_root "$root" pacman-key --populate archlinuxarm
    in_root "$root" pacman -Syu --noconfirm
}

# arch_rootfs, with what every Arch image needs on top.
#   ROOT  the root filesystem to make (empty)
#   WORK  where the download goes
arch_base() {
    local root="$1" work="$2"
    arch_rootfs "$root" "$work"

    # The tarball's own accounts have well-known passwords: no alarm user,
    # and root can't log in. cloud-init makes the owner's account.
    in_root "$root" userdel -r alarm
    in_root "$root" usermod -p '!' root
    sed -i 's/^# *\(%wheel ALL=(ALL:ALL) ALL\)/\1/' "$root/etc/sudoers" 2>/dev/null || true
    in_root "$root" pacman -S --noconfirm --needed sudo cloud-init networkmanager openssh

    # NetworkManager runs the network, as on the other images.
    in_root "$root" systemctl disable systemd-networkd.service
    in_root "$root" systemctl enable NetworkManager.service sshd.service
    echo 'LANG=C.UTF-8' > "$root/etc/locale.conf"

    # The kernel is booted from outside: it stays at the version the image has.
    sed -i 's/^#\?IgnorePkg *=.*/IgnorePkg = linux-aarch64 linux-aarch64-headers/' "$root/etc/pacman.conf"
    # An initramfs for any machine: mkinitcpio's autodetect would fit it to
    # the one building it, and the disk is virtio's.
    sed -i -e 's/^MODULES=.*/MODULES=(virtio_mmio virtio_blk)/' \
           -e 's/^HOOKS=.*/HOOKS=(base udev modconf block filesystems keyboard fsck)/' \
           "$root/etc/mkinitcpio.conf"
}

# What every Arch image does last: its initramfs, cloud-init's services, and
# no keys or caches from the build.
#   ROOT  the root filesystem
arch_finish() {
    local root="$1" unit
    in_root "$root" mkinitcpio -P
    for unit in cloud-init-main cloud-init-local cloud-init-network cloud-init cloud-config cloud-final; do
        [ -e "$root/usr/lib/systemd/system/$unit.service" ] && in_root "$root" systemctl enable "$unit.service"
    done
    in_root "$root" pacman -Scc --noconfirm

    # pacman's keyring holds a signing key made for the build: each machine
    # makes its own on the first boot instead, as Arch's own cloud images do.
    rm -rf "$root/etc/pacman.d/gnupg"
    cat > "$root/etc/systemd/system/pacman-init.service" <<'EOF'
[Unit]
Description=Initialise pacman's keyring
ConditionDirectoryNotEmpty=!/etc/pacman.d/gnupg
Before=sshd.service cloud-final.service

[Service]
Type=oneshot
ExecStart=/usr/bin/pacman-key --init
ExecStart=/usr/bin/pacman-key --populate archlinuxarm

[Install]
WantedBy=multi-user.target
EOF
    in_root "$root" systemctl enable pacman-init.service
}
