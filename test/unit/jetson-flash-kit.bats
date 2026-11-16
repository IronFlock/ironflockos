#!/usr/bin/env bats
# The flash kit for Jetson Orin (WP-6.4): build/jetson-flash.sh (the kit's
# command), build/tegra-flash-flock.sh (the .flock on the package's ESP) and
# build/jetson-flash-kit.sh (the archive). NVIDIA's BSP and Agreement are
# fakes served from file:// URLs, the release catalog is signed with a
# throwaway key, and the ESP's FAT image is a fake behind fake mtools; one
# test uses the real mtools where they are installed. Nothing here is
# NVIDIA's.

repo="$BATS_TEST_DIRNAME/../.."
kit="$repo/build/jetson-flash.sh"
flocktool="$repo/build/tegra-flash-flock.sh"
pack="$repo/build/jetson-flash-kit.sh"

setup() {
  dir=$(mktemp -d)
  mkdir -p "$dir/src/Linux_for_Tegra" "$dir/www" "$dir/work"
  bsp=Jetson_Linux_R39.2.1_aarch64.tbz2
  lic=Tegra_Software_License_Agreement-Tegra-Linux.txt
  printf '#!/bin/sh\n' >"$dir/src/Linux_for_Tegra/l4t_initrd_flash.sh"
  chmod +x "$dir/src/Linux_for_Tegra/l4t_initrd_flash.sh"
  tar -cjf "$dir/www/$bsp" -C "$dir/src" Linux_for_Tegra
  printf 'A FAKE AGREEMENT FOR THE TESTS\n' >"$dir/www/$lic"
  printf '%s *./%s\n%s *./%s\n' "$(sha1 "$dir/www/$bsp")" "$bsp" "$(sha1 "$dir/www/$lic")" "$lic" >"$dir/www/release_sha_hashes.txt"
  conf
  # The slot image: any bytes do, the kit only checks them.
  image=$dir/ironflockos-jetson-orin-base-1.2.3.rootfs.ext4.zst
  printf 'a slot image\n' >"$image"
  image_sha=$(sha256 "$image")
  # A device file of the shape enrollment takes.
  printf '{"name":"dev-1","serial_number":"sn-1","secret":"s","device_key":"k"}\n' >"$dir/dev-1.flock"
  export IRONFLOCKOS_KIT_SKIP_HOST_CHECK=1
}

teardown() { rm -rf "$dir"; }

sha1() { sha1sum "$1" | cut -d' ' -f1; }
sha256() { sha256sum "$1" | cut -d' ' -f1; }

# conf [KEY=VALUE...]: bsp.conf for the fakes, with KEY=VALUE overriding.
conf() {
  export IRONFLOCKOS_BSP_CONF=$dir/bsp.conf
  {
    printf 'L4T_VERSION=39.2.1\n'
    printf 'BSP_URL=file://%s/www/%s\n' "$dir" "$bsp"
    printf 'BSP_HASHES_URL=file://%s/www/release_sha_hashes.txt\n' "$dir"
    printf 'BSP_SHA1=%s\nBSP_SHA256=%s\n' "$(sha1 "$dir/www/$bsp")" "$(sha256 "$dir/www/$bsp")"
    printf 'BSP_LICENSE_URL=file://%s/www/%s\n' "$dir" "$lic"
    printf 'BSP_LICENSE_SHA1=%s\nBSP_LICENSE_SHA256=%s\n' "$(sha1 "$dir/www/$lic")" "$(sha256 "$dir/www/$lic")"
    for kv in "$@"; do printf '%s\n' "$kv"; done
  } >"$IRONFLOCKOS_BSP_CONF"
}

# nothing_of_nvidia_unpacked: no BSP in the cache, nothing unpacked.
nothing_of_nvidia_unpacked() {
  [ ! -e "$dir/work/cache/$bsp" ] && [ ! -e "$dir/work/Linux_for_Tegra" ]
}

@test "an unknown board is refused with the list of the known ones" {
  run "$kit" --board jetson-tx2 --work "$dir/work"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown board jetson-tx2"* ]]
  for b in jetson-orin-nano-devkit jetson-orin-nano-devkit-super jetson-agx-orin-devkit \
    jetson-agx-orin-devkit-super jetson-agx-orin-devkit-industrial; do
    [[ "$output" == *"  $b "* ]]
  done
  run "$kit" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"name the board with --board"*"jetson-agx-orin-devkit"* ]]
  [ ! -e "$dir/work/cache" ]
}

@test "--no-flash needs the module's identity, and a flash reads it from the module" {
  run "$kit" --board jetson-orin-nano-devkit --no-flash --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"--board-id and --board-sku"* ]]
  run "$kit" --board jetson-orin-nano-devkit --board-id 3767 --board-sku 0003 --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"go with --no-flash"* ]]
  run "$kit" --board jetson-orin-nano-devkit --sha256 "$image_sha" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"--sha256 goes with --image"* ]]
}

@test "without acceptance of NVIDIA's Agreement nothing of NVIDIA's is fetched or unpacked" {
  run "$kit" --board jetson-orin-nano-devkit --image "$image" --sha256 "$image_sha" --work "$dir/work" </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"has to be accepted before anything of NVIDIA's is unpacked or run"* ]]
  [[ "$output" == *"--accept-nvidia-license"* ]]
  nothing_of_nvidia_unpacked
}

@test "the Agreement is shown with --accept-nvidia-license; a BSP that is not the pinned one stops before it is unpacked" {
  conf BSP_SHA256=0000000000000000000000000000000000000000000000000000000000000000
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --image "$image" --sha256 "$image_sha" --work "$dir/work"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NVIDIA Driver License Agreement below"*"A FAKE AGREEMENT FOR THE TESTS"*"accepted with --accept-nvidia-license"* ]]
  [[ "$output" == *"slot image: ironflockos-jetson-orin-base-1.2.3.rootfs.ext4.zst verified"* ]]
  [[ "$output" == *"does not match the pinned SHA-256 and SHA-1"* ]]
  nothing_of_nvidia_unpacked
}

@test "an Agreement that is not the pinned one is not shown, and nothing else happens" {
  conf BSP_LICENSE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --image "$image" --sha256 "$image_sha" --work "$dir/work"
  [ "$status" -ne 0 ]
  [[ "$output" == *"$lic does not match the pinned"* ]]
  [[ "$output" != *"A FAKE AGREEMENT"* ]]
  nothing_of_nvidia_unpacked
}

@test "NVIDIA's list must still name the Agreement's SHA-1" {
  printf '1111111111111111111111111111111111111111 *./%s\n' "$lic" >"$dir/www/release_sha_hashes.txt"
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --image "$image" --sha256 "$image_sha" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"republished"* ]]
  nothing_of_nvidia_unpacked
}

@test "a slot image without the SHA-256 given stops before the BSP is fetched" {
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --image "$image" \
    --sha256 0000000000000000000000000000000000000000000000000000000000000000 --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"does not have the SHA-256"*"not flashed"* ]]
  nothing_of_nvidia_unpacked
  [ -f "$image" ]
}

# catalog VERSION SHA256 SIZE [KEY]: a signed release catalog naming the slot
# image, in the device-agent's envelope; KEY signs it (default: the key the
# kit is told to trust).
catalog() {
  local key=${4:-$dir/catalog.key}
  python3 -I - "$1" "$2" "$3" >"$dir/payload.json" <<'PY'
import json, sys
v, sha, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
img = {"url": f"https://example.invalid/dl/ironflockos/{v}/ironflockos-jetson-orin-base-{v}.rootfs.ext4.zst", "sha256": sha, "size": size}
print(json.dumps({"schema": 1, "releases": {v: {"images": {"ironflockos-jetson-orin-base": {"image": img}}}}}))
PY
  printf 'ironflockos-manifest:v1\nironflockos/manifest.json\n%s' "$(sha256 "$dir/payload.json")" >"$dir/message"
  openssl pkeyutl -sign -inkey "$key" -rawin -in "$dir/message" -out "$dir/signature"
  python3 -I -c 'import base64, json, sys; print(json.dumps({"payload": base64.b64encode(open(sys.argv[1], "rb").read()).decode(), "signature": base64.b64encode(open(sys.argv[2], "rb").read()).decode()}))' \
    "$dir/payload.json" "$dir/signature" >"$dir/www/manifest.json"
}

catalog_keys() {
  openssl genpkey -algorithm ed25519 -out "$dir/catalog.key" 2>/dev/null
  openssl pkey -in "$dir/catalog.key" -pubout -out "$dir/catalog.pub" 2>/dev/null
  openssl genpkey -algorithm ed25519 -out "$dir/other.key" 2>/dev/null
  export IRONFLOCKOS_CATALOG_KEY=$dir/catalog.pub
  # Stop each run once the image is checked: the BSP is not the pinned one.
  conf BSP_SHA256=0000000000000000000000000000000000000000000000000000000000000000
}

@test "the slot image is checked against the signed release catalog" {
  catalog_keys
  catalog 1.2.3 "$image_sha" "$(wc -c <"$image" | tr -d ' ')"
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --version 1.2.3 --image "$image" \
    --catalog "file://$dir/www/manifest.json" --work "$dir/work"
  [[ "$output" == *"in the signed release catalog"* ]]
  [[ "$output" == *"slot image: ironflockos-jetson-orin-base-1.2.3.rootfs.ext4.zst verified"* ]]
  # another image's hash
  catalog 1.2.3 0000000000000000000000000000000000000000000000000000000000000000 "$(wc -c <"$image" | tr -d ' ')"
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --version 1.2.3 --image "$image" \
    --catalog "file://$dir/www/manifest.json" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"does not have the SHA-256"* ]]
  nothing_of_nvidia_unpacked
}

@test "a catalog with another signature, or without the release, is refused" {
  catalog_keys
  catalog 1.2.3 "$image_sha" "$(wc -c <"$image" | tr -d ' ')" "$dir/other.key"
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --version 1.2.3 --image "$image" \
    --catalog "file://$dir/www/manifest.json" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"signature does not verify"* ]]
  [[ "$output" != *"verified"*"verified"* ]]
  catalog 1.2.3 "$image_sha" "$(wc -c <"$image" | tr -d ' ')"
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --version 1.2.4 --image "$image" \
    --catalog "file://$dir/www/manifest.json" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"has no IronFlockOS 1.2.4"* ]]
  printf 'not an envelope' >"$dir/www/manifest.json"
  run "$kit" --board jetson-orin-nano-devkit --accept-nvidia-license --version 1.2.3 --image "$image" \
    --catalog "file://$dir/www/manifest.json" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"not a signed envelope"* ]]
  nothing_of_nvidia_unpacked
}

@test "a file that is not a device's .flock is refused before anything is fetched" {
  printf 'not json' >"$dir/bad.flock"
  printf '{"name":"a/b","serial_number":"sn","secret":"s","device_key":"k"}' >"$dir/slash.flock"
  printf '{"name":"dev","serial_number":"sn","device_key":"k"}' >"$dir/nosecret.flock"
  printf '{"name":"dev","serial_number":"sn","secret":"s","device_key":"k"}' >"$dir/dev.json"
  for f in bad slash nosecret; do
    run "$kit" --board jetson-orin-nano-devkit --flock "$dir/$f.flock" --accept-nvidia-license --image "$image" --sha256 "$image_sha" --work "$dir/work"
    [ "$status" -ne 0 ]
    [[ "$output" != *"secret"*'"s"'* ]]
  done
  run "$kit" --board jetson-orin-nano-devkit --flock "$dir/dev.json" --accept-nvidia-license --image "$image" --sha256 "$image_sha" --work "$dir/work"
  [ "$status" -ne 0 ] && [[ "$output" == *"is not a device file (.flock)"* ]]
  [ ! -e "$dir/work/cache" ]
}

# --- the .flock on the package's ESP ----------------------------------------

# fake_package: a package's external/flash.idx and an ESP "image" (a fake
# FAT: it starts with FAT; the fake mtools keep its files beside it and write
# a digest of them into it, so its SHA-1 changes as a FAT image's would).
fake_package() {
  pkg=$dir/images
  mkdir -p "$pkg/external" "$dir/bin"
  { printf 'FAT'; head -c 65533 /dev/zero; } >"$pkg/external/esp.img"
  printf 'GPT' >"$pkg/external/gpt_primary.bin"
  {
    printf '0, 3:0:primary_gpt, 0, 3, gpt_primary.bin, 3, fixed-<reserved>-0, %s\n' "$(sha1 "$pkg/external/gpt_primary.bin")"
    printf '3, 3:0:esp, 1048576, 65536, esp.img, 65536, fixed-<reserved>-4, %s\n' "$(sha1 "$pkg/external/esp.img")"
    printf '7, 3:0:data, 9000000, 268435456, , , expand-<reserved>-17, \n'
  } >"$pkg/external/flash.idx"
  cat >"$dir/bin/mdir" <<'SH'
#!/bin/sh
[ "$1" = -i ] && [ "$(head -c 3 "$2")" = FAT ]
SH
  cat >"$dir/bin/mcopy" <<'SH'
#!/bin/sh
# mcopy -o -i IMG SRC ::/NAME | mcopy -n -i IMG ::/NAME DEST
[ "$1" = -o ] || [ "$1" = -n ] || exit 1
img=$3
mkdir -p "$img.files"
case "$4" in
  ::/*) cp "$img.files/${4#::/}" "$5" ;;
  *) cp "$4" "$img.files/${5#::/}" && cat "$img.files"/* | sha1sum | cut -c1-40 | dd of="$img" bs=1 seek=3 conv=notrunc 2>/dev/null ;;
esac
SH
  chmod +x "$dir/bin/mdir" "$dir/bin/mcopy"
  export PATH="$dir/bin:$PATH"
  cp "$pkg/external/esp.img" "$dir/esp.orig"
  cp "$pkg/external/flash.idx" "$dir/idx.orig"
}

@test "put: the .flock goes onto the ESP and flash.idx gets the ESP's new SHA-1; remove: the package as it was" {
  fake_package
  run "$flocktool" put "$pkg" "$dir/dev-1.flock"
  [ "$status" -eq 0 ] && [[ "$output" == *"the .flock is on the ESP as dev-1.flock (flash.idx line 2)"* ]]
  cmp -s "$dir/dev-1.flock" "$pkg/external/esp.img.files/dev-1.flock"
  new=$(sha1 "$pkg/external/esp.img")
  [ "$new" != "$(sha1 "$dir/esp.orig")" ]
  [ "$(sed -n 2p "$pkg/external/flash.idx")" = "3, 3:0:esp, 1048576, 65536, esp.img, 65536, fixed-<reserved>-4, $new" ]
  [ "$(sed -n 1p "$pkg/external/flash.idx")" = "$(sed -n 1p "$dir/idx.orig")" ]
  [ "$(sed -n 3p "$pkg/external/flash.idx")" = "$(sed -n 3p "$dir/idx.orig")" ]
  [ "$(wc -c <"$pkg/external/esp.img" | tr -d ' ')" = 65536 ]
  # nothing of put's is left in the package itself
  [ "$(ls "$pkg/external" | sort | tr '\n' ' ')" = "esp.img esp.img.files flash.idx gpt_primary.bin " ]
  run "$flocktool" remove "$pkg"
  [ "$status" -eq 0 ]
  cmp -s "$pkg/external/esp.img" "$dir/esp.orig"
  cmp -s "$pkg/external/flash.idx" "$dir/idx.orig"
  [ ! -e "$pkg.ironflockos-orig" ]
  # remove without put changes nothing
  run "$flocktool" remove "$pkg"
  [ "$status" -eq 0 ] && cmp -s "$pkg/external/flash.idx" "$dir/idx.orig"
}

@test "put twice starts from the package as made; the name is made valid on FAT" {
  fake_package
  "$flocktool" put "$pkg" "$dir/dev-1.flock"
  cp "$dir/dev-1.flock" "$dir/My:Dev*. .FLOCK"
  run "$flocktool" put "$pkg" "$dir/My:Dev*. .FLOCK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the .flock is off the package's ESP again"*"as My_Dev_.flock"* ]]
  cmp -s "$dir/dev-1.flock" "$pkg/external/esp.img.files/My_Dev_.flock"
  [ "$(cut -d' ' -f8 <(sed -n 2p "$pkg/external/flash.idx"))" = "$(sha1 "$pkg/external/esp.img")" ]
  "$flocktool" remove "$pkg"
  cmp -s "$pkg/external/esp.img" "$dir/esp.orig" && cmp -s "$pkg/external/flash.idx" "$dir/idx.orig"
}

@test "put refuses an ESP it does not know, and leaves the package as it was" {
  fake_package
  # flash.idx's SHA-1 is not the image's
  sed -i.bak 's/esp.img, 65536, fixed-<reserved>-4, [0-9a-f]*/esp.img, 65536, fixed-<reserved>-4, 0000000000000000000000000000000000000000/' "$pkg/external/flash.idx"
  rm -f "$pkg/external/flash.idx.bak"
  run "$flocktool" put "$pkg" "$dir/dev-1.flock"
  [ "$status" -ne 0 ] && [[ "$output" == *"does not have the SHA-1 flash.idx gives"* ]]
  cp "$dir/idx.orig" "$pkg/external/flash.idx"
  # not a FAT image
  printf 'XXX' | dd of="$pkg/external/esp.img" bs=1 conv=notrunc 2>/dev/null
  sed -i.bak "s/$(sha1 "$dir/esp.orig")/$(sha1 "$pkg/external/esp.img")/" "$pkg/external/flash.idx"
  rm -f "$pkg/external/flash.idx.bak"
  run "$flocktool" put "$pkg" "$dir/dev-1.flock"
  [ "$status" -ne 0 ] && [[ "$output" == *"is not a FAT file system"* ]]
  [ ! -e "$pkg/external/esp.img.files" ] && [ ! -e "$pkg.ironflockos-orig" ]
  # no esp line
  grep -v ':esp,' "$dir/idx.orig" >"$pkg/external/flash.idx"
  run "$flocktool" put "$pkg" "$dir/dev-1.flock"
  [ "$status" -ne 0 ] && [[ "$output" == *"has no single esp partition"* ]]
  # a .flock that is not one
  cp "$dir/idx.orig" "$pkg/external/flash.idx"
  printf '{}' >"$dir/empty.flock"
  run "$flocktool" put "$pkg" "$dir/empty.flock"
  [ "$status" -ne 0 ] && [[ "$output" == *"not a valid .flock"* ]]
}

@test "put and remove on a real FAT image (mtools)" {
  command -v mformat >/dev/null && command -v mcopy >/dev/null || skip "mtools are not installed"
  pkg=$dir/images
  mkdir -p "$pkg/external"
  head -c 33554432 /dev/zero >"$pkg/external/esp.img"
  mformat -i "$pkg/external/esp.img" -F ::
  orig=$(sha1 "$pkg/external/esp.img")
  printf '2, 3:0:esp, 1048576, 33554432, esp.img, 33554432, fixed-<reserved>-4, %s\n' "$orig" >"$pkg/external/flash.idx"
  run "$flocktool" put "$pkg" "$dir/dev-1.flock"
  [ "$status" -eq 0 ]
  mcopy -n -i "$pkg/external/esp.img" ::/dev-1.flock "$dir/back"
  cmp -s "$dir/back" "$dir/dev-1.flock"
  [ "$(cut -d' ' -f8 "$pkg/external/flash.idx")" = "$(sha1 "$pkg/external/esp.img")" ]
  "$flocktool" remove "$pkg"
  [ "$(sha1 "$pkg/external/esp.img")" = "$orig" ]
}

# --- the archive -------------------------------------------------------------

@test "the kit is IronFlockOS's scripts only, the same archive each time, and runs unpacked" {
  SOURCE_DATE_EPOCH=1700000000 run "$pack" "$dir/out" 1.2.3
  [ "$status" -eq 0 ]
  a=$dir/out/ironflockos-jetson-flash-kit-1.2.3.tar.gz
  [ "${lines[${#lines[@]} - 1]}" = "$a" ]
  first=$(sha256 "$a")
  SOURCE_DATE_EPOCH=1700000000 "$pack" "$dir/out" 1.2.3 >/dev/null 2>&1
  [ "$(sha256 "$a")" = "$first" ]
  run python3 -I -c 'import sys, tarfile
for m in tarfile.open(sys.argv[1]).getmembers():
    print(m.name.split("/", 1)[1] if "/" in m.name else ".", oct(m.mode), m.uid, m.mtime) if m.isfile() else None' "$a"
  [ "$status" -eq 0 ]
  expected="LICENSE 0o644 0 1700000000
README 0o644 0 1700000000
build/fetch-bsp.sh 0o755 0 1700000000
build/jetson-flash.sh 0o755 0 1700000000
build/lib.sh 0o644 0 1700000000
build/tegra-flash-flock.sh 0o755 0 1700000000
build/tegra-flash-package.sh 0o755 0 1700000000
build/tegra-layout.py 0o755 0 1700000000
ironflockos-jetson-flash 0o755 0 1700000000
kit.conf 0o644 0 1700000000
pki/ironflockos-catalog.pub 0o644 0 1700000000
targets/jetson-orin/bsp.conf 0o644 0 1700000000
targets/jetson-orin/overlay/usr/lib/ironflockos/tegra-extlinux 0o755 0 1700000000
targets/jetson-orin/target.conf 0o644 0 1700000000"
  [ "$(printf '%s\n' "${lines[@]}" | sort)" = "$expected" ]
  mkdir "$dir/x"
  tar -xzf "$a" -C "$dir/x"
  k=$dir/x/ironflockos-jetson-flash-kit-1.2.3
  grep -qx 'IRONFLOCKOS_VERSION=1.2.3' "$k/kit.conf"
  # nothing of NVIDIA's: no layout, no Agreement, no BSP file
  ! grep -rlE 'Tegra_Software_License_Agreement|NVIDIA Driver License Agreement' "$k" --include='*.xml'
  ! grep -rqF 'IMPORTANT NOTICE' "$k"
  run "$k/ironflockos-jetson-flash" --help
  [ "$status" -eq 2 ] && [[ "$output" == *"--board BOARD"* ]] && [[ "$output" == *"(default: 1.2.3)"* ]]
  run "$k/ironflockos-jetson-flash" --board jetson-tx2
  [ "$status" -ne 0 ] && [[ "$output" == *"unknown board jetson-tx2"* ]]
  # the unpacked kit stops without acceptance, before anything of NVIDIA's
  run "$k/ironflockos-jetson-flash" --board jetson-orin-nano-devkit --image "$image" --sha256 "$image_sha" --work "$dir/work" </dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"has to be accepted"* ]]
  nothing_of_nvidia_unpacked
}

# --- the module's nv_boot_control.conf on the package's ESP (WP-6.5) ---------

# board_conf FILE: an nv_boot_control.conf of flash.sh's shape (the values of
# the CI's offline flash of an Orin Nano 8GB).
board_conf() {
  printf 'TNSPEC 3767-000-0003--1-0-jetson-orin-nano-devkit-nvme0n1p1\nCOMPATIBLE_SPEC 3767--0003--1--jetson-orin-nano-devkit-\nTEGRA_LEGACY_UPDATE false\nTEGRA_CHIPID 0x23\n' >"$1"
}

@test "put-board: flash.sh's nv_boot_control.conf goes onto the ESP next to the .flock; remove takes both off" {
  fake_package
  board_conf "$dir/nv_boot_control.conf"
  "$flocktool" put "$pkg" "$dir/dev-1.flock"
  run "$flocktool" put-board "$pkg" "$dir/nv_boot_control.conf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"flash.sh's nv_boot_control.conf is on the ESP (flash.idx line 2): 3767--0003--1--jetson-orin-nano-devkit-"* ]]
  cmp -s "$dir/nv_boot_control.conf" "$pkg/external/esp.img.files/nv_boot_control.conf"
  cmp -s "$dir/dev-1.flock" "$pkg/external/esp.img.files/dev-1.flock"
  [ "$(cut -d' ' -f8 <(sed -n 2p "$pkg/external/flash.idx"))" = "$(sha1 "$pkg/external/esp.img")" ]
  "$flocktool" remove "$pkg"
  cmp -s "$pkg/external/esp.img" "$dir/esp.orig"
  cmp -s "$pkg/external/flash.idx" "$dir/idx.orig"
  # without a .flock too
  run "$flocktool" put-board "$pkg" "$dir/nv_boot_control.conf"
  [ "$status" -eq 0 ]
  "$flocktool" remove "$pkg"
  cmp -s "$pkg/external/esp.img" "$dir/esp.orig"
}

@test "check-board refuses what is not flash.sh's nv_boot_control.conf, before the ESP is touched" {
  fake_package
  board_conf "$dir/good.conf"
  run "$flocktool" check-board "$dir/good.conf"
  [ "$status" -eq 0 ]
  grep -v '^COMPATIBLE_SPEC' "$dir/good.conf" >"$dir/nocompat.conf"
  { cat "$dir/good.conf"; echo 'TNSPEC again'; } >"$dir/twice.conf"
  sed 's/^TEGRA_CHIPID .*/TEGRA_CHIPID 0x23 extra/' "$dir/good.conf" >"$dir/fields.conf"
  { cat "$dir/good.conf"; printf '\001\n'; } >"$dir/binary.conf"
  head -c 5000 /dev/zero | tr '\0' a >"$dir/big.conf"
  for f in nocompat twice fields binary big; do
    run "$flocktool" put-board "$pkg" "$dir/$f.conf"
    [ "$status" -ne 0 ] || { echo "accepted: $f"; return 1; }
    [ ! -e "$pkg.ironflockos-orig" ]
    cmp -s "$pkg/external/esp.img" "$dir/esp.orig"
  done
}

@test "the kit puts flash.sh's conf on the ESP when it is there, and goes on without it" {
  grep -q 'bash "$here/tegra-flash-flock.sh" check-board "$board_conf"' "$kit"
  grep -q 'bash "$here/tegra-flash-flock.sh" put-board "$package" "$board_conf"' "$kit"
  grep -q 'board_conf=$l4t/rootfs/etc/nv_boot_control.conf' "$kit"
  grep -q 'warn "no nv_boot_control.conf from flash.sh' "$kit"
  # the cleanup takes off whatever was put, with or without a .flock
  grep -q 'if \[ -n "$package" \] && \[ -d "$package" \]; then' "$kit"
}
