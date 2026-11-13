#!/bin/bash
# Builds one image inside a privileged debian:trixie container, the same way
# here and on GitHub's runners.
#
#     build/in-container.sh IMAGE OUT
#
# IMAGE is a script in build/ (debian-kde, ubuntu-gnome, arch-kde, omarchy);
# OUT is where its release files go.
set -euo pipefail
image="$1"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"

docker run --rm --privileged --network host \
    -v "$here:/build:ro" -v "$out:/out" \
    debian:trixie bash -c "
        set -euo pipefail
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
            mmdebstrap ubuntu-keyring e2fsprogs btrfs-progs xz-utils zstd python3 \
            curl ca-certificates libarchive-tools file gpg gpgv >/dev/null
        bash /build/$image.sh /out
    "
