#!/usr/bin/env bash
# What a release with Jetson files needs besides the image (docs/release.md,
# "Jetson"; docs/jetson-licence-review.md, points 2, 3 and 6).
#   jetson-release.sh files OUT_DIR VERSION
#       NVIDIA's Agreement as NVIDIA-LICENSE.txt, fetched from NVIDIA and
#       checked against the pins of targets/jetson-orin/bsp.conf
#       (build/fetch-bsp.sh --license), and the flash kit
#       ironflockos-jetson-flash-kit-<version>.tar.gz
#       (build/jetson-flash-kit.sh), into OUT_DIR next to the image. The
#       repository holds no copy of the Agreement.
#   jetson-release.sh notes VERSION
#       the release notes of VERSION (IRONFLOCKOS_NOTES, default
#       release-notes/) link NVIDIA-LICENSE.txt of the release and, while
#       target.conf has HARDWARE_TESTED=no, say that the Jetson image is not
#       yet proven on hardware.
#   jetson-release.sh check VERSION
#       before a release with Jetson files starts (release.yml's verify,
#       while JETSON_RELEASE is true): the contact of the source offers
#       (release/contact) is complete, no source package of release/sources
#       is still open, the source pins of bsp.conf belong to the packages
#       target.conf pins, the FreeRTOS statement takes the mirror and the
#       contact from where the release puts them, and the notes (above).
#       Names every problem, then fails.
#
# IRONFLOCKOS_BSP_CACHE: where the Agreement is downloaded to (default: a
# temporary directory); IRONFLOCKOS_CONTACT, IRONFLOCKOS_RULES: another
# contact file, another release/sources (tests).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/.." && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"

usage="usage: jetson-release.sh files OUT_DIR VERSION | notes VERSION | check VERSION"
version_ok() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "$1 is not a version"; }

files() {
  local out=$1 version=$2 cache license
  version_ok "$version"
  mkdir -p "$out"
  cache=${IRONFLOCKOS_BSP_CACHE:-}
  if [ -z "$cache" ]; then
    files_tmp=$(mktemp -d)
    trap 'rm -rf "$files_tmp"' EXIT
    cache=$files_tmp
  fi
  license=$(bash "$here/fetch-bsp.sh" --license "$cache")
  cp "$license" "$out/NVIDIA-LICENSE.txt"
  chmod 0644 "$out/NVIDIA-LICENSE.txt"
  if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    # The kit's time is the commit the image names (build/run-in-builder.sh).
    read -r _ SOURCE_DATE_EPOCH < <(build_commit "$src" "${IRONFLOCKOS_BUILD_COMMIT:-}") || true
    export SOURCE_DATE_EPOCH
  fi
  bash "$here/jetson-flash-kit.sh" "$out" "$version" >/dev/null
  log "NVIDIA's Agreement (NVIDIA-LICENSE.txt) and the flash kit of $version in $out"
}

# notes_problems VERSION: what the notes of VERSION lack, one line each.
notes_problems() {
  local version=$1 notes url tested
  load_conf "$src/build/release.conf"
  notes=${IRONFLOCKOS_NOTES:-$src/release-notes}/$version.md
  url=$DL_BASE/ironflockos/$version/NVIDIA-LICENSE.txt
  if [ ! -f "$notes" ]; then
    echo "release-notes/$version.md is missing: a release with Jetson files has notes that link NVIDIA's Agreement, $url"
    return 0
  fi
  grep -qF "$url" "$notes" ||
    echo "release-notes/$version.md does not link NVIDIA's Agreement, $url"
  tested=$(sed -n 's/^HARDWARE_TESTED=//p' "$src/targets/jetson-orin/target.conf")
  if [ "$tested" != yes ]; then
    grep -qiF "not yet proven on hardware" "$notes" ||
      echo "release-notes/$version.md does not say that the Jetson image is not yet proven on hardware (targets/jetson-orin/target.conf: HARDWARE_TESTED=${tested:-unset})"
  fi
  return 0
}

notes() {
  local version=$1 problems
  version_ok "$version"
  problems=$(notes_problems "$version")
  if [ -n "$problems" ]; then
    printf 'error: %s\n' "$problems" >&2
    die "the release notes of a release with Jetson files (docs/release.md \"Jetson\")"
  fi
  log "release-notes/$version.md links NVIDIA's Agreement and says what it must of the Jetson image"
}

# pins_problems: the source pins of bsp.conf against the packages of
# target.conf, one line per mismatch.
pins_problems() {
  (
    load_conf "$src/targets/jetson-orin/target.conf"
    load_conf "$src/targets/jetson-orin/bsp.conf"
    [ "${L4T_SOURCES_VERSION:-}" = "$L4T_PACKAGE_VERSION" ] ||
      echo "bsp.conf: L4T_SOURCES_VERSION ${L4T_SOURCES_VERSION:-unset} is not the packages' L4T_PACKAGE_VERSION $L4T_PACKAGE_VERSION (target.conf)"
    [[ "$L4T_PACKAGE_VERSION" == "$L4T_VERSION-"* ]] ||
      echo "target.conf: L4T_PACKAGE_VERSION $L4T_PACKAGE_VERSION is not of the BSP's L4T_VERSION $L4T_VERSION"
    [ "${LIBNVIDIA_CONTAINER_SOURCE_VERSION:-}" = "$L4T_CONTAINER_TOOLKIT_VERSION" ] ||
      echo "bsp.conf: LIBNVIDIA_CONTAINER_SOURCE_VERSION ${LIBNVIDIA_CONTAINER_SOURCE_VERSION:-unset} is not the container toolkit's L4T_CONTAINER_TOOLKIT_VERSION $L4T_CONTAINER_TOOLKIT_VERSION (target.conf)"
  )
}

check() {
  local version=$1 problems=() line open
  version_ok "$version"
  if ! line=$( (load_contact "${IRONFLOCKOS_CONTACT:-$src/release/contact}") 2>&1); then
    problems+=("${line#error: }")
  fi
  open=$(awk '!/^[ \t]*(#|$)/ && $2 == "open" { print $1 }' "${IRONFLOCKOS_RULES:-$src/release/sources}" | tr '\n' ' ')
  [ -z "$open" ] || problems+=("release/sources: the source of ${open% } is still open (a decision first: upstream, l4t or, without a copyleft licence, none)")
  while IFS= read -r line; do problems+=("$line"); done < <(pins_problems)
  for line in '@DL_BASE@/ironflockos/sources/@L4T_SOURCES_DIR@/' @CONTACT_NAME@ @CONTACT_STREET@ @CONTACT_CITY@ @CONTACT_EMAIL@; do
    grep -qF "$line" "$src/targets/jetson-orin/freertos-offer.txt" ||
      problems+=("targets/jetson-orin/freertos-offer.txt does not take $line from where the release puts it")
  done
  while IFS= read -r line; do
    [ -z "$line" ] || problems+=("$line")
  done < <(notes_problems "$version")
  if [ "${#problems[@]}" -gt 0 ]; then
    printf 'error: %s\n' "${problems[@]}" >&2
    die "a release with Jetson files cannot start: ${#problems[@]} problem(s) above (docs/release.md \"Jetson\")"
  fi
  log "a release of $version with Jetson files has what it needs: the contact, every source decided, the pins, the notes"
}

case "${1:-}" in
  files) files "${2:?$usage}" "${3:?$usage}" ;;
  notes) notes "${2:?$usage}" ;;
  check) check "${2:?$usage}" ;;
  *) die "$usage" ;;
esac
