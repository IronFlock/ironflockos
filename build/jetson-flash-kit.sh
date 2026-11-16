#!/usr/bin/env bash
# Pack the flash kit for NVIDIA Jetson Orin (WP-6.4) into one archive:
#   jetson-flash-kit.sh OUT_DIR [VERSION]
#
# OUT_DIR gets ironflockos-jetson-flash-kit-<version>.tar.gz (VERSION
# defaults to the repository's). It holds IronFlockOS's own files only, under
# ironflockos-jetson-flash-kit-<version>/, in the repository's layout so the
# scripts run unchanged:
#   ironflockos-jetson-flash   the command a user runs (build/jetson-flash.sh)
#   README                     how to use it (targets/jetson-orin/flash-kit/README)
#   LICENSE                    Apache-2.0 (license.md)
#   kit.conf                   IRONFLOCKOS_VERSION, the release it flashes
#   build/                     jetson-flash.sh, fetch-bsp.sh, tegra-flash-package.sh,
#                              tegra-flash-flock.sh, tegra-layout.py, lib.sh
#   targets/jetson-orin/       bsp.conf (the BSP's and the Agreement's pins),
#                              target.conf, overlay/.../tegra-extlinux
#   pki/ironflockos-catalog.pub  the key the release catalog is signed with
# Nothing of NVIDIA's is in it (docs/jetson-licence-review.md, points 4 and
# 7): the kit downloads the BSP and its licence from NVIDIA. The archive is
# the same for the same files: sorted, owner 0, the time of
# SOURCE_DATE_EPOCH (else the last commit's), modes 0755 and 0644.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "usage: jetson-flash-kit.sh OUT_DIR [VERSION]"
out=$1
version=${2:-$(tr -d '[:space:]' <"$src/VERSION")}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "$version is not a version"
require python3
epoch=${SOURCE_DATE_EPOCH:-$(git -C "$src" log -1 --format=%ct 2>/dev/null || echo 0)}
top=ironflockos-jetson-flash-kit-$version
mkdir -p "$out"
archive=$(cd "$out" && pwd)/$top.tar.gz

# published path <TAB> source (relative to the repository) or @generated
files=$(
  cat <<EOF
ironflockos-jetson-flash	@wrapper
README	targets/jetson-orin/flash-kit/README
LICENSE	license.md
kit.conf	@kit.conf
build/jetson-flash.sh	build/jetson-flash.sh
build/fetch-bsp.sh	build/fetch-bsp.sh
build/tegra-flash-package.sh	build/tegra-flash-package.sh
build/tegra-flash-flock.sh	build/tegra-flash-flock.sh
build/tegra-layout.py	build/tegra-layout.py
build/lib.sh	build/lib.sh
targets/jetson-orin/bsp.conf	targets/jetson-orin/bsp.conf
targets/jetson-orin/target.conf	targets/jetson-orin/target.conf
targets/jetson-orin/overlay/usr/lib/ironflockos/tegra-extlinux	targets/jetson-orin/overlay/usr/lib/ironflockos/tegra-extlinux
pki/ironflockos-catalog.pub	pki/ironflockos-catalog.pub
EOF
)

python3 -I - "$src" "$archive" "$top" "$version" "$epoch" "$files" <<'PY'
import gzip, io, os, sys, tarfile
src, archive, top, version, epoch, files = sys.argv[1:7]
epoch = int(epoch)
generated = {
    "@wrapper": (b'#!/bin/sh\n# The IronFlockOS flash kit for NVIDIA Jetson Orin; see README.\n'
                 b'exec bash "$(dirname "$0")/build/jetson-flash.sh" "$@"\n', 0o755),
    "@kit.conf": (("# The IronFlockOS release this flash kit flashes (build/jetson-flash-kit.sh).\n"
                   f"IRONFLOCKOS_VERSION={version}\n").encode(), 0o644),
}
entries = []
for line in files.strip().splitlines():
    path, source = line.split("\t")
    if source in generated:
        data, mode = generated[source]
    else:
        full = os.path.join(src, source)
        with open(full, "rb") as f:
            data = f.read()
        mode = 0o755 if os.access(full, os.X_OK) else 0o644
    entries.append((path, data, mode))
entries.sort()
dirs = set()
for path, _, _ in entries:
    parts = path.split("/")[:-1]
    for i in range(1, len(parts) + 1):
        dirs.add("/".join(parts[:i]))


def info(name, mode, kind, size=0):
    ti = tarfile.TarInfo(name)
    ti.mode, ti.type, ti.size, ti.mtime = mode, kind, size, epoch
    ti.uid = ti.gid = 0
    ti.uname = ti.gname = "root"
    return ti


buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as tar:
    tar.addfile(info(top, 0o755, tarfile.DIRTYPE))
    for d in sorted(dirs):
        tar.addfile(info(f"{top}/{d}", 0o755, tarfile.DIRTYPE))
    for path, data, mode in entries:
        tar.addfile(info(f"{top}/{path}", mode, tarfile.REGTYPE, len(data)), io.BytesIO(data))
with open(archive + ".part", "wb") as f:
    with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=epoch, compresslevel=9) as gz:
        gz.write(buf.getvalue())
os.replace(archive + ".part", archive)
PY
log "flash kit: $archive"
printf '%s\n' "$archive"
