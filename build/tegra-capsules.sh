#!/usr/bin/env bash
# The boot firmware lane of jetson-orin at build time (WP-6.5; ADR-0007; the
# licence review, point 6): NVIDIA's own capsules from nvidia-l4t-bootloader,
# installed unchanged in the tree, must be the L4T release the image and the
# BSP pin are (the lock-step rule), and the FreeRTOS statement and source
# offer go with them.
#   tegra-capsules.sh ROOT
#
# Checks, each a build failure:
# - /opt/ota_package/t23x holds capsules for the Orin NX and Nano (TEGRA_BL_3767*)
#   and the AGX Orin (TEGRA_BL_3701*), and NVIDIA's L4TLauncher (BOOTAA64.efi);
# - every capsule there is a UEFI FMP capsule whose firmware version (the FMP
#   payload header's) is L4T_VERSION of bsp.conf, the BSP the flash kit
#   writes the QSPI firmware from;
# - nvidia-l4t-bootloader is L4T_PACKAGE_VERSION, and the tree's
#   /etc/nv_tegra_release names L4T_VERSION;
# - the package's licence texts are there.
# Then it writes /usr/share/doc/ironflockos/FreeRTOS-source-offer.txt.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"
[ "$#" -eq 1 ] || die "usage: tegra-capsules.sh ROOT"
root=$1
[ -d "$root/usr" ] || die "$root is not a root tree"
load_conf "$src/targets/jetson-orin/target.conf"
load_conf "$src/targets/jetson-orin/bsp.conf"
load_conf "$src/build/release.conf"
: "${L4T_VERSION:?}" "${L4T_PACKAGE_VERSION:?}" "${DL_BASE:?}"
[[ "$L4T_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "bsp.conf: L4T_VERSION $L4T_VERSION is not R.M.m"
want=$(((BASH_REMATCH[1] << 16) | (BASH_REMATCH[2] << 8) | BASH_REMATCH[3]))
dir=$root/opt/ota_package/t23x

# fmp_version FILE: the firmware version and the lowest supported version of
# a UEFI FMP capsule (EFI_FMP_CAPSULE_GUID first, then, behind the
# authentication header, the FMP payload header "MSS1": signature, header
# size, firmware version, lowest supported version, all UINT32 LE), or fails.
fmp_version() {
  od -An -v -tu1 -N 65536 "$1" | awk '
    { for (i = 1; i <= NF; i++) b[n++] = $i }
    END {
      split("237 213 203 109 45 232 68 76 189 161 113 148 25 154 217 42", g, " ")
      for (i = 0; i < 16; i++) if (b[i] != g[i + 1]) exit 1
      for (i = 16; i + 16 <= n; i++) {
        if (b[i] == 77 && b[i+1] == 83 && b[i+2] == 83 && b[i+3] == 49) {
          v = b[i+8] + 256 * (b[i+9] + 256 * (b[i+10] + 256 * b[i+11]))
          l = b[i+12] + 256 * (b[i+13] + 256 * (b[i+14] + 256 * b[i+15]))
          print v, l
          exit 0
        }
      }
      exit 1
    }'
}
ver_str() { echo "$(($1 >> 16)).$((($1 >> 8) & 255)).$(($1 & 255))"; }

[ -d "$dir" ] || die "no $dir: nvidia-l4t-bootloader is not in the tree (targets/jetson-orin/packages)"
for board in 3767 3701; do
  compgen -G "$dir/TEGRA_BL_$board*.Cap" >/dev/null || die "no capsule for board $board in $dir (TEGRA_BL_$board*.Cap)"
done
[ -s "$dir/BOOTAA64.efi" ] || die "no L4TLauncher in $dir (BOOTAA64.efi)"
n=0
for f in "$dir"/*.Cap; do
  read -r v l < <(fmp_version "$f") || die "$(basename "$f") is not a UEFI FMP capsule with a payload header"
  [ "$v" -eq "$want" ] ||
    die "$(basename "$f") is L4T $(ver_str "$v"), the BSP pin is L4T $L4T_VERSION (bsp.conf): QSPI and rootfs stay in lock-step"
  [ "$l" -le "$v" ] || die "$(basename "$f"): lowest supported version $(ver_str "$l") above its own"
  n=$((n + 1))
done

# dpkg's own record of the package, read without dpkg.
have=$(awk '$0 == "Package: nvidia-l4t-bootloader" { p = 1; next } /^$/ { p = 0 } p && /^Version: / { print $2; exit }' "$root/var/lib/dpkg/status")
[ "$have" = "$L4T_PACKAGE_VERSION" ] || die "nvidia-l4t-bootloader is ${have:-not installed}, the pin is $L4T_PACKAGE_VERSION"
release=$(head -n 1 "$root/etc/nv_tegra_release" 2>/dev/null || true)
[[ "$release" =~ ^#\ R([0-9]+)\ \(release\),\ REVISION:\ ([0-9]+\.[0-9]+), ]] &&
  [ "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}" = "$L4T_VERSION" ] ||
  die "/etc/nv_tegra_release does not name L4T $L4T_VERSION: ${release:-missing}"
doc=$root/usr/share/doc/nvidia-l4t-bootloader
[ -s "$doc/copyright" ] && [ -s "$doc/LICENSE.bl_update_payload.gz" ] ||
  die "$doc lacks NVIDIA's licence texts (copyright, LICENSE.bl_update_payload.gz)"

mkdir -p "$root/usr/share/doc/ironflockos"
L4T_VERSION=$L4T_VERSION L4T_PACKAGE_VERSION=$L4T_PACKAGE_VERSION DL_BASE=$DL_BASE \
  render "$src/targets/jetson-orin/freertos-offer.txt" >"$root/usr/share/doc/ironflockos/FreeRTOS-source-offer.txt"
log "boot firmware: $n capsules of L4T $L4T_VERSION from nvidia-l4t-bootloader $have, with the FreeRTOS statement"
