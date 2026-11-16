#!/usr/bin/env bash
# The device's .flock on the ESP of a jetson-orin flash package (WP-6.4), as
# FlockFlasher and `ironflock os flash` put it on the IRONFLOCKOS partition of
# the other targets: on Jetson that partition is NVIDIA's `esp`, the device's
# /boot/efi, where ironflockos-enroll looks for *.flock at the first boot.
#   tegra-flash-flock.sh check FLOCK
#   tegra-flash-flock.sh put IMAGES FLOCK
#   tegra-flash-flock.sh check-board CONF
#   tegra-flash-flock.sh put-board IMAGES CONF
#   tegra-flash-flock.sh remove IMAGES
#
# IMAGES is the package, L4T_DIR/tools/kernel_flash/images
# (build/tegra-flash-package.sh). Its external/flash.idx names the ESP's
# image; each line is "<n>, <dev>:<name>, <start>, <size>, <file>,
# <file size>, <attributes>, <sha1>".
#
# check: the file is a device file as FlockFlasher's prototype and
# `ironflock os flash` read one: named *.flock, at most 5 MiB, a JSON object
# whose name and serial_number are plain names, with a secret and a
# device_key (else enrollment refuses it). No message says what it holds.
# put: check, then copy the .flock into the ESP's FAT image (mtools, nothing
# is mounted), read it back, and give flash.idx the image's new SHA-1. The
# ESP's image and flash.idx are kept as they were in IMAGES.ironflockos-orig,
# outside the package, for remove.
# put-board: NVIDIA's nv_boot_control.conf, which flash.sh wrote for the
# module (TNSPEC, COMPATIBLE_SPEC, TEGRA_CHIPID), the same way into the ESP's
# root, after put. The slot images do not carry it (they are the release's,
# for every module); the device copies it to /etc at boot (tegra-board-conf).
# remove: the ESP's image and flash.idx as they were before the first put;
# the package keeps no .flock. Nothing to do when put did not run.
#
# Without a .flock the package flashes a device that boots and waits for
# one (ironflockos-enroll), as a FlockFlasher image without a .flock does.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"

usage() { die "usage: tegra-flash-flock.sh check FLOCK | put IMAGES FLOCK | check-board CONF | put-board IMAGES CONF | remove IMAGES"; }

# check_flock FLOCK
check_flock() {
  local f=$1 name
  name=$(basename "$f")
  case "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" in
    ?*.flock) ;;
    *) die "$f is not a device file (.flock)" ;;
  esac
  [ -f "$f" ] || die "$f is not a file"
  [ "$(wc -c <"$f" | tr -d ' ')" -le $((5 << 20)) ] || die "$f is too large for a device file"
  require python3
  python3 -I - "$f" <<'PY' || exit 1
import json, sys
path = sys.argv[1]
def fail(msg):
    sys.stderr.write(f"error: {path} {msg}\n")
    sys.exit(1)
try:
    with open(path, "rb") as f:
        data = json.loads(f.read().decode("utf-8"))
except (OSError, UnicodeDecodeError, ValueError):
    fail("is not a device file: it is not JSON")
if not isinstance(data, dict):
    fail("is not a device file")
for key in ("name", "serial_number"):
    v = data.get(key)
    if not isinstance(v, str) or v in ("", ".", "..") or "/" in v or "\\" in v \
            or any(ord(c) < 0x20 or ord(c) == 0x7f for c in v):
        fail(f"is not a valid .flock: its {key} is not a plain name")
if not isinstance(data.get("secret"), str) or not data["secret"] or data.get("device_key") is None:
    fail("is not a valid .flock: no device_key or secret")
PY
}

# flock_name FLOCK: the name the .flock gets on the ESP, as `ironflock os
# flash` names it (configFileName): its own, made valid on FAT, ending in
# .flock.
flock_name() {
  local stem
  stem=$(basename "$1")
  case "$(printf '%s' "$stem" | tr '[:upper:]' '[:lower:]')" in *.flock) stem=${stem%??????} ;; esac
  stem=$(printf '%s' "$stem" | LC_ALL=C tr '\000-\037<>:"/\\|?*' '_')
  while [[ "$stem" == *[.\ ] ]]; do stem=${stem%?}; done
  [ -n "$stem" ] || stem=device
  printf '%s.flock' "$stem"
}

# esp_entry IMAGES: "<line number> <file> <file size> <sha1>" of the ESP in
# flash.idx; fails unless there is exactly one.
esp_entry() {
  local idx=$1/external/flash.idx out
  [ -f "$idx" ] || die "$idx not found: is $1 a flash package (build/tegra-flash-package.sh)?"
  out=$(awk -F', ' '$2 ~ /^[0-9]+:[0-9]+:esp$/ { n++; print NR, $5, $6, $8 } END { if (n != 1) exit 1 }' "$idx") ||
    die "$idx has no single esp partition"
  printf '%s\n' "$out"
}

sha1_of() { sha1sum "$1" | cut -d' ' -f1; }
size_of() { wc -c <"$1" | tr -d ' '; }

# remove_flock IMAGES
remove_flock() {
  local images=$1 entry file orig=$1.ironflockos-orig
  [ -d "$orig" ] || return 0
  entry=$(esp_entry "$images")
  read -r _ file _ _ <<<"$entry"
  [ -f "$orig/esp" ] && [ -f "$orig/flash.idx" ] || die "$orig is not what put leaves: remove it, and make the package again"
  mv -f "$orig/esp" "$images/external/$file"
  mv -f "$orig/flash.idx" "$images/external/flash.idx"
  rmdir "$orig"
  log "the .flock is off the package's ESP again"
}

# esp_put IMAGES FILE NAME: FILE into the ESP's FAT image as NAME (mtools,
# nothing is mounted), read back, and flash.idx given the image's new SHA-1.
# The first put keeps the ESP's image and flash.idx as they were in
# IMAGES.ironflockos-orig, outside the package, for remove; later ones add to
# it.
esp_put() {
  local images=$1 src=$2 name=$3 idx=$1/external/flash.idx entry line file size sha1 esp tmp new
  require mcopy mdir sha1sum cmp
  export MTOOLS_SKIP_CHECK=1
  entry=$(esp_entry "$images")
  read -r line file size sha1 <<<"$entry"
  esp=$images/external/$file
  [ -n "$file" ] && [ -f "$esp" ] || die "the ESP's image $esp (flash.idx line $line) is not there"
  [ "$(size_of "$esp")" = "$size" ] || die "the ESP's image is not the size flash.idx gives ($size bytes)"
  [ -z "$sha1" ] || [ "$(sha1_of "$esp")" = "$sha1" ] ||
    die "the ESP's image does not have the SHA-1 flash.idx gives: the index is not what this script knows"
  mdir -i "$esp" ::/ >/dev/null 2>&1 || die "the ESP's image $esp is not a FAT file system: cannot put $name on it"
  if [ ! -d "$images.ironflockos-orig" ]; then
    mkdir -m 0700 "$images.ironflockos-orig"
    cp -p "$esp" "$images.ironflockos-orig/esp"
    cp -p "$idx" "$images.ironflockos-orig/flash.idx"
  fi
  tmp=$(mktemp -d)
  chmod 0700 "$tmp"
  if ! mcopy -o -i "$esp" "$src" "::/$name" >/dev/null 2>&1; then
    rm -rf "$tmp"
    remove_flock "$images"
    die "cannot copy $name into the ESP's image"
  fi
  if ! { mcopy -n -i "$esp" "::/$name" "$tmp/back" >/dev/null 2>&1 && cmp -s "$src" "$tmp/back"; } ||
    [ "$(size_of "$esp")" != "$size" ]; then
    rm -rf "$tmp"
    remove_flock "$images"
    die "$name read back from the ESP's image is not the file given"
  fi
  rm -f "$tmp/back"
  if [ -n "$sha1" ]; then
    new=$(sha1_of "$esp")
    awk -F', ' -v OFS=', ' -v n="$line" -v s="$new" 'NR == n { $8 = s } { print }' "$idx" >"$tmp/flash.idx"
    cat "$tmp/flash.idx" >"$idx"
    if [ "$(esp_entry "$images" | cut -d' ' -f4)" != "$new" ]; then
      rm -rf "$tmp"
      remove_flock "$images"
      die "cannot give flash.idx the ESP's new SHA-1"
    fi
  fi
  rm -rf "$tmp"
  esp_line=$line
}

# put_flock IMAGES FLOCK
put_flock() {
  local name
  check_flock "$2"
  # An earlier put that was not removed: start from the package as made.
  remove_flock "$1"
  name=$(flock_name "$2")
  esp_put "$1" "$2" "$name"
  log "the .flock is on the ESP as $name (flash.idx line $esp_line)"
}

# check_board CONF: the nv_boot_control.conf NVIDIA's flash.sh wrote for the
# module: text of at most 4 KiB naming TNSPEC, COMPATIBLE_SPEC and
# TEGRA_CHIPID once each, as "KEY value" (the device's tegra-board-conf takes
# the same rule).
check_board() {
  local f=$1 k
  [ -f "$f" ] || die "$f is not a file"
  [ "$(wc -c <"$f" | tr -d ' ')" -le 4096 ] || die "$f is larger than 4 KiB: not NVIDIA's nv_boot_control.conf"
  ! LC_ALL=C grep -q '[^[:print:][:space:]]' "$f" || die "$f is not text: not NVIDIA's nv_boot_control.conf"
  for k in TNSPEC COMPATIBLE_SPEC TEGRA_CHIPID; do
    [ "$(awk -v k="$k" '$1 == k && NF == 2 && $2 ~ /^[A-Za-z0-9._-]+$/ { n++ } $1 == k { m++ } END { print n + 0, m + 0 }' "$f")" = "1 1" ] ||
      die "$f does not name $k once, as \"$k value\""
  done
}

# put_board IMAGES CONF: flash.sh's nv_boot_control.conf onto the ESP, where
# the device copies it to /etc at every boot (tegra-board-conf, WP-6.5).
put_board() {
  check_board "$2"
  esp_put "$1" "$2" nv_boot_control.conf
  log "flash.sh's nv_boot_control.conf is on the ESP (flash.idx line $esp_line): $(awk '$1 == "COMPATIBLE_SPEC" { print $2 }' "$2")"
}

case "${1:-}" in
  check)
    [ "$#" -eq 2 ] || usage
    check_flock "$2"
    log "$2: a device file"
    ;;
  put)
    [ "$#" -eq 3 ] || usage
    put_flock "$2" "$3"
    ;;
  check-board)
    [ "$#" -eq 2 ] || usage
    check_board "$2"
    log "$2: NVIDIA's nv_boot_control.conf"
    ;;
  put-board)
    [ "$#" -eq 3 ] || usage
    put_board "$2" "$3"
    ;;
  remove)
    [ "$#" -eq 2 ] || usage
    remove_flock "$2"
    ;;
  *) usage ;;
esac
