#!/usr/bin/env bash
# Fetch the NVIDIA Jetson Linux BSP pinned in targets/jetson-orin/bsp.conf
# (ADR-0008; WP-6.1) and unpack it, or NVIDIA's licence of it.
#   fetch-bsp.sh CACHE_DIR [DEST_DIR]
#   fetch-bsp.sh --license CACHE_DIR
#
# CACHE_DIR keeps the tarball between builds (CI caches it keyed on
# bsp.conf); a cached file is downloaded again only when it fails the checks.
# DEST_DIR, if given, gets Linux_for_Tegra/.
#
# --license fetches NVIDIA's Driver License Agreement of the BSP
# (BSP_LICENSE_URL, docs/jetson-licence-review.md) into CACHE_DIR and prints
# its path; the flash kit shows it before anything of NVIDIA's is unpacked.
#
# A file is used only when its SHA-256 is the pinned one and its SHA-1 the
# pinned one. When NVIDIA's release_sha_hashes.txt can be fetched, it must
# still list that SHA-1: a republished file fails instead of slipping in.
#
# IRONFLOCKOS_BSP_CONF: for the unit tests.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"

license=no
if [ "${1:-}" = --license ]; then
  license=yes
  shift
  [ "$#" -eq 1 ] || die "usage: fetch-bsp.sh --license CACHE_DIR"
fi
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  die "usage: fetch-bsp.sh CACHE_DIR [DEST_DIR] | fetch-bsp.sh --license CACHE_DIR"
fi
cache=$1
dest=${2:-}
load_conf "${IRONFLOCKOS_BSP_CONF:-$src/targets/jetson-orin/bsp.conf}"
: "${L4T_VERSION:?}" "${BSP_HASHES_URL:?}"
require curl sha256sum sha1sum
if [ "$license" = yes ]; then
  : "${BSP_LICENSE_URL:?}" "${BSP_LICENSE_SHA1:?}" "${BSP_LICENSE_SHA256:?}"
  url=$BSP_LICENSE_URL want_sha1=$BSP_LICENSE_SHA1 want_sha256=$BSP_LICENSE_SHA256
  what="NVIDIA's licence of the BSP"
else
  : "${BSP_URL:?}" "${BSP_SHA1:?}" "${BSP_SHA256:?}"
  require tar
  url=$BSP_URL want_sha1=$BSP_SHA1 want_sha256=$BSP_SHA256
  what="BSP $L4T_VERSION"
fi

name=${url##*/}
file=$cache/$name
mkdir -p "$cache"

# NVIDIA's list, when it can be had (an offline rebuild from the cache still
# works on the pinned hashes alone).
if listed=$(curl -fsSL --proto '=https,file' --retry 3 "$BSP_HASHES_URL" 2>/dev/null); then
  nvidia_sha1=$(printf '%s\n' "$listed" | awk -v n="$name" '{ f = $2; sub(/^\*?(\.\/)?/, "", f) } f == n { print $1; exit }')
  [ -n "$nvidia_sha1" ] || die "NVIDIA's release_sha_hashes.txt does not list $name"
  [ "$nvidia_sha1" = "$want_sha1" ] ||
    die "NVIDIA lists SHA-1 $nvidia_sha1 for $name, the pin is $want_sha1: the file was republished"
else
  warn "cannot fetch $BSP_HASHES_URL; checking against the pinned hashes only"
fi

verified() {
  [ -f "$1" ] &&
    echo "$want_sha256  $1" | sha256sum -c --quiet - >/dev/null 2>&1 &&
    echo "$want_sha1  $1" | sha1sum -c --quiet - >/dev/null 2>&1
}

if verified "$file"; then
  log "$what: $name from the cache"
else
  rm -f "$file"
  log "$what: downloading $name"
  curl -fsSL --proto '=https,file' --retry 5 --retry-all-errors -o "$file.part" "$url" ||
    die "cannot download $url"
  mv "$file.part" "$file"
  if ! verified "$file"; then
    rm -f "$file"
    die "$name does not match the pinned SHA-256 and SHA-1 (targets/jetson-orin/bsp.conf)"
  fi
  log "$what: $name verified"
fi

if [ "$license" = yes ]; then
  printf '%s\n' "$file"
  exit 0
fi

if [ -n "$dest" ]; then
  mkdir -p "$dest"
  rm -rf "$dest/Linux_for_Tegra"
  # lbzip2 unpacks in parallel where it is installed.
  if command -v lbzip2 >/dev/null; then
    tar -I lbzip2 -xf "$file" -C "$dest"
  else
    tar -xjf "$file" -C "$dest"
  fi
  [ -x "$dest/Linux_for_Tegra/l4t_initrd_flash.sh" ] || die "$name has no Linux_for_Tegra/l4t_initrd_flash.sh"
  log "BSP $L4T_VERSION: unpacked to $dest/Linux_for_Tegra"
fi
