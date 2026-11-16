#!/usr/bin/env bash
# The IronFlockOS flash kit for NVIDIA Jetson Orin (WP-6.4): flashes a module
# in recovery mode with IronFlockOS from a Linux host (x86-64 Ubuntu 22.04 or
# 24.04), with NVIDIA's flash tools from the BSP that it downloads from
# NVIDIA (docs/jetson-licence-review.md, point 4: IronFlockOS publishes no
# flash package and no file of NVIDIA's).
#   sudo jetson-flash.sh --board BOARD [--flock FILE] [options]
#   sudo jetson-flash.sh --board BOARD --no-flash --board-id ID --board-sku SKU [options]
#
# In the kit (build/jetson-flash-kit.sh) this is `ironflockos-jetson-flash`.
# The steps, in this order:
# 1. the arguments, the board, the .flock (build/tegra-flash-flock.sh check)
#    and the host;
# 2. NVIDIA's Driver License Agreement, downloaded from NVIDIA and checked
#    against bsp.conf (build/fetch-bsp.sh --license), shown; nothing of
#    NVIDIA's is unpacked or run unless it is accepted (interactively, or
#    with --accept-nvidia-license);
# 3. the slot image <image-id>-<version>.rootfs.ext4.zst, as the other
#    targets' images are checked: its SHA-256 from the release catalog,
#    whose Ed25519 signature is checked against the catalog key the kit
#    carries (pki/ironflockos-catalog.pub); or a file given with --image,
#    checked against the catalog or against --sha256;
# 4. the BSP from NVIDIA, its SHA-256 and SHA-1 checked before it is
#    unpacked (build/fetch-bsp.sh), and NVIDIA's host prerequisites
#    (tools/l4t_flash_prerequisites.sh);
# 5. the module in recovery mode on USB, of the board named;
# 6. the flash package (build/tegra-flash-package.sh), read from the module,
#    or offline from --board-id and --board-sku with --no-flash;
# 7. the .flock on the package's ESP (build/tegra-flash-flock.sh put);
# 8. NVIDIA's l4t_initrd_flash.sh --flash-only (not with --no-flash);
# 9. at the end, whatever happened: the .flock off the package again.
#
# IRONFLOCKOS_KIT_SKIP_HOST_CHECK, IRONFLOCKOS_CATALOG_KEY, IRONFLOCKOS_BSP_CONF:
# for the unit tests only.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"

IMAGE_ID=ironflockos-jetson-orin-base
catalog_url=https://instance-registry.ironflock.com/dl/ironflockos/manifest.json
catalog_key=${IRONFLOCKOS_CATALOG_KEY:-$src/pki/ironflockos-catalog.pub}

# The boards the kit flashes: NVIDIA's board configuration of the BSP, the
# USB product ids (vendor 0955) of the modules it fits in recovery mode, and
# what it is (NVIDIA's Quick Start, r39.2.1). IronFlockOS goes onto the NVMe
# (nvme0n1) on each; the QSPI firmware is written too.
boards() {
  cat <<'EOF'
jetson-orin-nano-devkit|7323 7423 7523 7623|Orin NX 16GB or 8GB, Orin Nano 8GB or 4GB (P3767) on the Orin Nano Developer Kit carrier (P3768) or one that fits its configuration
jetson-orin-nano-devkit-super|7323 7423 7523 7623|the same, with the Super power modes
jetson-agx-orin-devkit|7023 7223|AGX Orin (P3701-0000, -0004, -0005) on the AGX Orin Developer Kit carrier (P3737)
jetson-agx-orin-devkit-super|7223|AGX Orin 32GB (P3701-0004) on the AGX Orin Developer Kit carrier, with the Super power modes
jetson-agx-orin-devkit-industrial|7023|AGX Orin Industrial (P3701-0008) on the AGX Orin Developer Kit carrier
EOF
}

board_list() { boards | awk -F'|' '{ printf "  %-34s %s\n", $1, $3 }'; }

usage() {
  cat >&2 <<EOF
usage: sudo ${0##*/} --board BOARD [--flock FILE] [options]

Flashes IronFlockOS onto the NVMe of an NVIDIA Jetson Orin module that is
attached over USB in recovery mode, with NVIDIA's flash tools, which it
downloads from NVIDIA.

  --board BOARD            the module and its carrier, one of:
$(board_list)
  --flock FILE             the device's .flock from IronFlock: the device enrolls
                           with it at its first boot. Without it the device boots
                           and waits for one.
  --accept-nvidia-license  accept NVIDIA's Driver License Agreement without being
                           asked; it is still printed
  --version VERSION        the IronFlockOS release (default: $(kit_version))
  --image FILE             a slot image ($IMAGE_ID-<version>.rootfs.ext4.zst)
                           instead of the release's download
  --sha256 HEX             the SHA-256 of --image, instead of the catalog's
  --catalog URL            the signed release catalog (default: $catalog_url)
  --work DIR               where the BSP is unpacked and the package made
                           (default: ./ironflockos-jetson; about 20 GB)
  --cache DIR              downloads, kept between runs (default: WORK/cache)
  --skip-prerequisites     do not install NVIDIA's and the kit's host packages
  --no-flash               make the package only, offline, with no module:
    --board-id ID          the module's board id (3767, 3701)
    --board-sku SKU        the module's SKU (0003: Orin Nano 8GB)
    --fab FAB --board-rev REV --chip-sku SKU   more of the module's identity
EOF
  exit 2
}

kit_version() {
  if [ -f "$src/kit.conf" ]; then
    sed -n 's/^IRONFLOCKOS_VERSION=//p' "$src/kit.conf"
  elif [ -f "$src/VERSION" ]; then
    tr -d '[:space:]' <"$src/VERSION"
  fi
}

board='' flock='' accept=no version='' image='' image_sha256='' work='' cache='' prereq=yes flash=yes
board_id='' board_sku='' fab='' board_rev='' chip_sku=''
need() { [ "$#" -ge 2 ] && [ -n "$2" ] || die "$1 needs a value"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --board) need "$@" && board=$2 && shift ;;
    --flock) need "$@" && flock=$2 && shift ;;
    --accept-nvidia-license) accept=yes ;;
    --version) need "$@" && version=$2 && shift ;;
    --image) need "$@" && image=$2 && shift ;;
    --sha256) need "$@" && image_sha256=$2 && shift ;;
    --catalog) need "$@" && catalog_url=$2 && shift ;;
    --work) need "$@" && work=$2 && shift ;;
    --cache) need "$@" && cache=$2 && shift ;;
    --skip-prerequisites) prereq=no ;;
    --no-flash) flash=no ;;
    --board-id) need "$@" && board_id=$2 && shift ;;
    --board-sku) need "$@" && board_sku=$2 && shift ;;
    --fab) need "$@" && fab=$2 && shift ;;
    --board-rev) need "$@" && board_rev=$2 && shift ;;
    --chip-sku) need "$@" && chip_sku=$2 && shift ;;
    -h | --help) usage ;;
    *) die "unknown argument $1 (--help lists them)" ;;
  esac
  shift
done

# --- 1. what was asked -----------------------------------------------------
[ -n "$board" ] || die "name the board with --board; the kit knows:
$(board_list)"
usb_ids=$(boards | awk -F'|' -v b="$board" '$1 == b { print $2 }')
[ -n "$usb_ids" ] || die "unknown board $board; the kit knows:
$(board_list)"
if [ "$flash" = no ]; then
  [ -n "$board_id" ] && [ -n "$board_sku" ] || die "--no-flash makes the package offline: name the module with --board-id and --board-sku"
elif [ -n "$board_id$board_sku$fab$board_rev$chip_sku" ]; then
  die "--board-id, --board-sku, --fab, --board-rev and --chip-sku go with --no-flash; a flash reads them from the module"
fi
[ -n "$image_sha256" ] && [ -z "$image" ] && die "--sha256 goes with --image"
[ -z "$image_sha256" ] || [[ "$image_sha256" =~ ^[0-9a-f]{64}$ ]] || die "--sha256 is 64 hex digits"
[ -z "$image" ] || [ -f "$image" ] || die "$image not found"
[ -n "$version" ] || version=$(kit_version)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "no IronFlockOS version: name it with --version"
if [ -n "$flock" ]; then
  bash "$here/tegra-flash-flock.sh" check "$flock"
  flock=$(cd "$(dirname "$flock")" && pwd)/$(basename "$flock")
fi
work=${work:-$PWD/ironflockos-jetson}
cache=${cache:-$work/cache}

if [ "${IRONFLOCKOS_KIT_SKIP_HOST_CHECK:-}" != 1 ]; then
  [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ] ||
    die "NVIDIA's flash tools run on an x86-64 Linux host (Ubuntu 22.04 or 24.04)"
  [ "$(id -u)" = 0 ] || die "run it with sudo: NVIDIA's flash tools mount and loop images and talk to the module over USB"
  # shellcheck disable=SC1091 # the host's
  host=$(. /etc/os-release 2>/dev/null && printf '%s %s' "${ID:-}" "${VERSION_ID:-}") || host=unknown
  case "$host" in
    "ubuntu 22.04" | "ubuntu 24.04") ;;
    *) warn "this host is $host; NVIDIA's flash tools of r39.2.1 are made for Ubuntu 22.04 and 24.04" ;;
  esac
fi
require curl python3 openssl sha256sum sha1sum
mkdir -p "$work" "$cache"
chmod 0700 "$work"

# --- 9. at the end: no .flock stays in the package --------------------------
package=''
cleanup() {
  if [ -n "$package" ] && [ -n "$flock" ] && [ -d "$package" ]; then
    bash "$here/tegra-flash-flock.sh" remove "$package" || warn "the .flock may still be in $package: delete $work"
  fi
}
trap cleanup EXIT

# --- 2. NVIDIA's Agreement -------------------------------------------------
load_conf "${IRONFLOCKOS_BSP_CONF:-$src/targets/jetson-orin/bsp.conf}"
licence=$(bash "$here/fetch-bsp.sh" --license "$cache")
intro="IronFlockOS's flash kit downloads NVIDIA Jetson Linux $L4T_VERSION (the BSP)
from NVIDIA and runs NVIDIA's flash tools from it on this host. NVIDIA licenses
the BSP to you under the NVIDIA Driver License Agreement below, which NVIDIA
publishes at $BSP_LICENSE_URL.
The kit's own scripts are under the Apache License 2.0; they do not license
NVIDIA's software. The IronFlockOS image the kit writes holds NVIDIA's
software under the same Agreement (/usr/share/doc/nvidia-l4t-*/copyright on
the device)."
if [ "$accept" = yes ]; then
  printf '%s\n\n' "$intro"
  cat "$licence"
  printf '\n'
  log "NVIDIA's Driver License Agreement: accepted with --accept-nvidia-license"
else
  [ -t 0 ] || die "NVIDIA's Driver License Agreement has to be accepted before anything of NVIDIA's is unpacked or run: run the kit in a terminal, or read the Agreement ($licence, or $BSP_LICENSE_URL) and add --accept-nvidia-license"
  { printf '%s\n\n' "$intro" && cat "$licence"; } >"$work/agreement.txt"
  if [ -t 1 ] && command -v less >/dev/null; then
    less "$work/agreement.txt"
  else
    cat "$work/agreement.txt"
  fi
  printf '\nDo you accept NVIDIA'\''s Driver License Agreement? Type yes to accept: '
  answer=''
  read -r answer || true
  [ "$answer" = yes ] || die "the Agreement was not accepted: nothing of NVIDIA's was unpacked or run"
  log "NVIDIA's Driver License Agreement: accepted"
fi

# --- 3. the slot image -----------------------------------------------------
name=$IMAGE_ID-$version.rootfs.ext4.zst
# catalog_image: "<url> <sha256> <size>" of the slot image in the signed
# catalog, after its signature is checked as the device-agent checks it
# (ironflockos-manifest:v1, ADR-0009).
catalog_image() {
  local t
  t=$(mktemp -d)
  # shellcheck disable=SC2064 # $t is fixed here
  trap "rm -rf '$t'" RETURN
  curl -fsSL --proto '=https,file' --retry 3 --max-filesize 65536 -o "$t/manifest.json" "$catalog_url" ||
    die "cannot download the release catalog $catalog_url"
  python3 -I - "$t" <<'PY' || die "the release catalog is not a signed envelope"
import base64, hashlib, json, sys
d = sys.argv[1]
with open(d + "/manifest.json", "rb") as f:
    e = json.load(f)
payload = base64.b64decode(e["payload"], validate=True)
sig = base64.b64decode(e["signature"].strip(), validate=True)
if len(sig) != 64:
    sys.exit(1)
msg = "ironflockos-manifest:v1\nironflockos/manifest.json\n" + hashlib.sha256(payload).hexdigest()
for name, data in (("payload", payload), ("message", msg.encode()), ("signature", sig)):
    with open(d + "/" + name, "wb") as f:
        f.write(data)
PY
  openssl pkeyutl -verify -pubin -inkey "$catalog_key" -rawin -in "$t/message" -sigfile "$t/signature" >/dev/null 2>&1 ||
    die "the release catalog's signature does not verify with $catalog_key"
  python3 -I - "$t/payload" "$version" "$IMAGE_ID" <<'PY'
import json, re, sys
path, version, image_id = sys.argv[1:]
with open(path, "rb") as f:
    c = json.load(f)
release = c.get("releases", {}).get(version)
if release is None:
    sys.stderr.write(f"error: the release catalog has no IronFlockOS {version}\n")
    sys.exit(1)
img = release.get("images", {}).get(image_id, {}).get("image")
if not img:
    sys.stderr.write(f"error: IronFlockOS {version} has no {image_id} image in the release catalog\n")
    sys.exit(1)
url, sha, size = img.get("url", ""), img.get("sha256", ""), img.get("size")
if not url.startswith("https://") or not re.fullmatch(r"[0-9a-f]{64}", sha) or not isinstance(size, int):
    sys.stderr.write(f"error: the catalog's {image_id} entry is not complete\n")
    sys.exit(1)
print(url, sha, size)
PY
}

want_size=''
if [ -n "$image" ] && [ -n "$image_sha256" ]; then
  log "slot image: $image, checked against --sha256"
else
  entry=$(catalog_image) || exit 1
  read -r url image_sha256 want_size <<<"$entry"
  log "slot image: $IMAGE_ID $version in the signed release catalog"
fi
if [ -z "$image" ]; then
  [ "${url##*/}" = "$name" ] || die "the catalog's image is ${url##*/}, not $name"
  image=$cache/$name
  if [ -f "$image" ] && echo "$image_sha256  $image" | sha256sum -c --quiet - >/dev/null 2>&1; then
    log "slot image: $name from the cache"
  else
    rm -f "$image"
    log "slot image: downloading $url"
    curl -fSL --proto '=https' --retry 5 --retry-all-errors -o "$image.part" "$url" || die "cannot download $url"
    mv "$image.part" "$image"
  fi
fi
case "$(basename "$image")" in
  "$IMAGE_ID"-*.rootfs.ext4.zst) ;;
  *) die "$image is not a slot image of $IMAGE_ID (<image-id>-<version>.rootfs.ext4.zst)" ;;
esac
if [ -n "$want_size" ] && [ "$(wc -c <"$image" | tr -d ' ')" != "$want_size" ]; then
  [ "$image" != "$cache/$name" ] || rm -f "$image"
  die "$image is not the size the catalog gives ($want_size bytes)"
fi
if ! echo "$image_sha256  $image" | sha256sum -c --quiet - >/dev/null 2>&1; then
  [ "$image" != "$cache/$name" ] || rm -f "$image"
  die "$image does not have the SHA-256 $image_sha256: not flashed"
fi
log "slot image: $(basename "$image") verified"

# --- 4. the BSP and the host's prerequisites --------------------------------
bash "$here/fetch-bsp.sh" "$cache" "$work"
l4t=$work/Linux_for_Tegra
if [ "$prereq" = yes ]; then
  log "NVIDIA's host prerequisites (tools/l4t_flash_prerequisites.sh) and the kit's"
  (cd "$l4t" && ./tools/l4t_flash_prerequisites.sh)
  kit_packages=(zstd e2fsprogs mtools usbutils python3)
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${kit_packages[@]}" >/dev/null ||
    { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${kit_packages[@]}" >/dev/null; } ||
    die "cannot install ${kit_packages[*]}"
fi
require zstd debugfs e2fsck mcopy mdir
[ "$flash" = no ] || require lsusb

# --- 5. the module ---------------------------------------------------------
if [ "$flash" = yes ]; then
  found=$(lsusb -d 0955: 2>/dev/null | sed -n 's/.* ID 0955:\([0-9a-fA-F]\{4\}\).*/\1/p' | tr 'A-F' 'a-f' | sort -u)
  hint="Put the module into recovery mode: on the Orin Nano Developer Kit carrier, power off, put a jumper across the REC and GND pins of the button header, and power on; on the AGX Orin Developer Kit, power off, hold the Force Recovery button, press and release Power, and release Force Recovery. Connect its flashing USB port to this host, then run the kit again."
  [ -n "$found" ] || die "no Jetson in recovery mode on this host's USB (lsusb -d 0955:). $hint"
  [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" -eq 1 ] || die "more than one Jetson on USB ($(echo "$found" | tr '\n' ' ')): connect only the one to flash"
  case " $usb_ids " in
    *" $found "*) log "the module: 0955:$found in recovery mode, for $board" ;;
    *) die "the Jetson on USB (0955:$found) is no module of $board (0955:${usb_ids// /, 0955:}); name its board with --board" ;;
  esac
fi

# --- 6. the flash package --------------------------------------------------
pkg_args=("$l4t" "$image" "$board")
pkg_env=()
if [ "$flash" = no ]; then
  pkg_args+=("$board_id" "$board_sku")
  [ -z "$fab" ] || pkg_env+=("FAB=$fab")
  [ -z "$board_rev" ] || pkg_env+=("BOARDREV=$board_rev")
  [ -z "$chip_sku" ] || pkg_env+=("CHIP_SKU=$chip_sku")
fi
env ${pkg_env[@]+"${pkg_env[@]}"} bash "$here/tegra-flash-package.sh" "${pkg_args[@]}"
package=$l4t/tools/kernel_flash/images

# --- 7. the .flock ---------------------------------------------------------
if [ -n "$flock" ]; then
  bash "$here/tegra-flash-flock.sh" put "$package" "$flock"
else
  log "no --flock: the device boots and waits for its .flock (on its ESP, /boot/efi)"
fi

# --- 8. the flash ----------------------------------------------------------
flash_cmd=(./tools/kernel_flash/l4t_initrd_flash.sh --showlogs --network usb0 --flash-only --erase-all)
if [ "$flash" = no ]; then
  log "--no-flash: the package is $package; a module in recovery mode would now be flashed with: (cd $l4t && sudo ${flash_cmd[*]})"
  exit 0
fi
log "flashing: NVIDIA's ${flash_cmd[*]} (the QSPI firmware, then the NVMe; about 15 minutes)"
if ! (cd "$l4t" && "${flash_cmd[@]}"); then
  die "the flash failed. NVIDIA's logs are in $l4t/initrdlog. The module stays in recovery mode or can be put into it again; run the kit again to flash it from the start"
fi
log "flashed: the module restarts into IronFlockOS $version, slot A"
if [ -n "$flock" ]; then
  log "at its first boot it enrolls with $(basename "$flock") and comes online in IronFlock"
else
  log "it waits for its .flock: put one on its ESP (/boot/efi), or flash again with --flock"
fi
