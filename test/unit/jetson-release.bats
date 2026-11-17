#!/usr/bin/env bats
# The Jetson files of a release (docs/release.md, "Jetson"; WP-6.8): the
# switch JETSON_RELEASE (off: a release is exactly what it was), what a
# release with Jetson files publishes, the release notes rule, the source
# mirror and its decisions, the contact of the source offers, and
# build/jetson-release.sh. ci.yml's jetson-release runs the same code on a
# real build (test/image/jetson-release-check.sh).

repo="$BATS_TEST_DIRNAME/../.."
publish="$repo/build/publish.sh"
sources="$repo/build/sources.sh"
jr="$repo/build/jetson-release.sh"
wf="$repo/.github/workflows"

# The images of every release without the switch, as of v0.18.0.
TODAY="amd64-efi-base amd64-efi-base-rt amd64-efi-nvidia amd64-efi-installer arm64-efi-base arm64-efi-base-rt arm64-efi-installer rpi-arm64-base"

setup() {
  tmp=$(mktemp -d)
  # shellcheck source=build/lib.sh
  . "$repo/build/lib.sh"
  unset JETSON_RELEASE
}

teardown() { rm -rf "$tmp"; }

# today_out: the eight images of a release as a release build and the sign
# job leave them, every file each one has.
today_out() {
  local i id n
  for i in $TODAY; do
    id=ironflockos-$i n=ironflockos-$i-1.0.0
    mkdir -p "$tmp/out/$id"
    for f in img.gz cdx.json os-release packages.tsv modules.alias.gz; do printf '%s %s' "$n" "$f" >"$tmp/out/$id/$n.$f"; done
    printf 'raw_size=1\nmin_disk_size=1\n' >"$tmp/out/$id/$n.sizes"
    printf 'bash\t5.2.37-2\nlinux\t6.12.115-2\n' >"$tmp/out/$id/$n.sources.tsv"
    printf 'IMAGE_ID=%s\n' "$id" >"$tmp/out/$id/$n.os-release"
    case "$i" in
      *-installer) printf 'ironflockos-%s-base\n' "${i%-installer}" >"$tmp/out/$id/$n.payloads" ;;
      *) printf bundle >"$tmp/out/$id/$n.raucb" ;;
    esac
    printf 'sums\n' >"$tmp/out/$id/SHA256SUMS"
  done
}

# agreement: a stand-in for NVIDIA's Agreement and a bsp.conf that pins it
# (the repository holds no copy of the real one).
agreement() {
  printf 'NVIDIA Driver License Agreement (stand-in)\n' >"$tmp/agreement.txt"
  sed "s/^BSP_LICENSE_SHA256=.*/BSP_LICENSE_SHA256=$(sha256sum <"$tmp/agreement.txt" | cut -d' ' -f1)/" \
    "$repo/targets/jetson-orin/bsp.conf" >"$tmp/bsp.conf"
  export IRONFLOCKOS_BSP_CONF=$tmp/bsp.conf
}

# jetson_out: the Jetson image as build/jetson-release.sh files leaves it.
jetson_out() {
  local id=ironflockos-jetson-orin-base n=ironflockos-jetson-orin-base-1.0.0
  agreement
  mkdir -p "$tmp/out/$id"
  for f in rootfs.ext4.zst raucb cdx.json packages.tsv; do printf '%s %s' "$n" "$f" >"$tmp/out/$id/$n.$f"; done
  printf 'IMAGE_ID=%s\n' "$id" >"$tmp/out/$id/$n.os-release"
  printf 'bash\t5.2.21-2ubuntu4\nnvidia-l4t-core\t39.2.1-20260806224157\n' >"$tmp/out/$id/$n.sources.tsv"
  printf 'sums\n' >"$tmp/out/$id/SHA256SUMS"
  cp "$tmp/agreement.txt" "$tmp/out/$id/NVIDIA-LICENSE.txt"
  printf kit >"$tmp/out/$id/ironflockos-jetson-flash-kit-1.0.0.tar.gz"
}

# notes [WHAT...]: release notes of 1.0.0 with the Agreement's link
# ("link") and the hardware sentence ("hardware").
notes() {
  mkdir -p "$tmp/notes"
  load_conf "$repo/build/release.conf"
  {
    echo '## New'
    echo
    for w in "$@"; do
      case "$w" in
        link) echo "- NVIDIA's Agreement: [NVIDIA-LICENSE.txt]($DL_BASE/ironflockos/1.0.0/NVIDIA-LICENSE.txt)" ;;
        hardware) echo "- IronFlockOS for NVIDIA Jetson Orin, not yet proven on hardware." ;;
      esac
    done
  } >"$tmp/notes/1.0.0.md"
  export IRONFLOCKOS_NOTES=$tmp/notes
}

# staged: the names stage would upload, sorted.
staged() { sed -n 's|^+ gcloud storage cp .* gs://ironflock-downloads/staging/ironflockos/1.0.0/||p' <<<"$1" | LC_ALL=C sort; }

# --- the switch off: every release as it was --------------------------------------

@test "switch off: the release's images are today's eight, whatever JETSON_RELEASE is but true" {
  load_conf "$repo/build/release.conf"
  [ "$RELEASE_IMAGES" = "$TODAY" ]
  # shellcheck disable=SC2086
  want=$(printf '%s\n' $TODAY)
  [ "$(release_images)" = "$want" ]
  for v in false 1 TRUE yes ""; do
    [ "$(JETSON_RELEASE=$v release_images)" = "$want" ]
  done
  [ "$(JETSON_RELEASE=true release_images)" = "$(printf '%s\n' "$want" jetson-orin-base)" ]
}

@test "switch off: build.yml's matrix is today's, and only the jetson job builds Jetson, behind JETSON_RELEASE" {
  matrix=$(awk '$0 == "  image:" { f = 1; next } f && /^  [a-z]/ { exit } f && /^    (uses|with):/ { exit } f && /- target:/ { t = $3 } f && /^ +variant:/ { v = $2 } f && /^ +kernel:/ { k = $2 } f && /^ +runner:/ { print t, v, k, $2 }' "$wf/build.yml")
  [ "$matrix" = "$(printf '%s\n' \
    'amd64-efi base std ubuntu-latest' \
    'amd64-efi base rt ubuntu-latest' \
    'amd64-efi nvidia std ubuntu-latest' \
    'arm64-efi base std ubuntu-24.04-arm' \
    'arm64-efi base rt ubuntu-24.04-arm' \
    'rpi-arm64 base std ubuntu-24.04-arm')" ]
  sticks=$(awk '$0 == "  installer:" { f = 1; next } f && /^  [a-z]/ { exit } f && /- target:/ { print $3 }' "$wf/build.yml")
  [ "$sticks" = "$(printf 'amd64-efi\narm64-efi')" ]
  grep -qx '    needs: \[image\]' "$wf/build.yml"
  jobs=$(awk '/^jobs:/ { f = 1; next } f && /^  [a-z][a-z0-9-]*:$/ { print $1 }' "$wf/build.yml")
  [ "$jobs" = "$(printf 'image:\njetson:\ninstaller:')" ]
  jetson=$(awk '$0 == "  jetson:" { f = 1; print; next } f && /^  [a-z]/ { exit } f' "$wf/build.yml")
  [[ "$jetson" == *"    if: vars.JETSON_RELEASE == 'true'"* ]]
  [[ "$jetson" == *"      target: jetson-orin"* ]]
  # outside comments, only the jetson job's name and target
  [ "$(grep -v '^ *#' "$wf/build.yml" | grep -c 'jetson-orin')" -eq 2 ]
}

@test "switch off: release.yml's image list and attestation subjects are what they were" {
  load_conf "$repo/build/release.conf"
  images=$(release_images)
  # the filter as release.yml runs it, and as it was before the Jetson files
  filter=$(sed -n "s/.*echo \"attest=\$(jq -Rnc '\(.*\)' <<<\"\$images\")\".*/\1/p" "$wf/release.yml")
  [ -n "$filter" ]
  old='{include: [inputs | {image: ., subjects: (if endswith("-installer") then "*.img.gz" else "*.img.gz\n*.raucb" end)}]}'
  [ "$(jq -Rnc "$filter" <<<"$images")" = "$(jq -Rnc "$old" <<<"$images")" ]
  # with the switch on, the Jetson image's subjects are its slot image, bundle and kit
  [ "$(JETSON_RELEASE=true release_images | jq -Rnc "$filter" | jq -r '.include[] | select(.image == "jetson-orin-base") | .subjects')" = \
    "$(printf '*.rootfs.ext4.zst\n*.raucb\nironflockos-jetson-flash-kit-*.tar.gz')" ]
  # the switch reaches every job that names the release's images
  verify=$(awk '$0 == "  verify:" { f = 1; next } f && /^  [a-z]/ { exit } f' "$wf/release.yml")
  [[ "$verify" == *'JETSON_RELEASE: ${{ vars.JETSON_RELEASE }}'*'images=$(release_images)'* ]]
  [ "$(grep -c 'JETSON_RELEASE: ${{ vars.JETSON_RELEASE }}' "$wf/release.yml")" -eq 6 ]
  grep -q 'RELEASE_IMAGES=$(release_images' "$repo/build/reuse.sh"
}

@test "switch off: stage publishes exactly the files it published, and meta lists what it listed" {
  today_out
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -eq 0 ]
  want=$(for i in $TODAY; do
    n=ironflockos-$i-1.0.0
    printf '%s\n' "$n.img.gz" "$n.cdx.json" "$n.os-release" "$n.packages.tsv" "$n.modules.alias.gz"
    case "$i" in *-installer) ;; *) echo "$n.raucb" ;; esac
  done
  echo SHA256SUMS)
  [ "$(staged "$output")" = "$(LC_ALL=C sort <<<"$want")" ]
  [ "$(staged "$output" | wc -l | tr -d ' ')" = 47 ]
  bash "$publish" meta "$tmp/out" "$tmp/meta" 2>/dev/null
  [ "$(cat "$tmp/meta/sources.tsv")" = "$(printf 'bash\t5.2.37-2\nlinux\t6.12.115-2')" ]
  [ -z "$(find "$tmp/meta" -name 'sources-*')" ]
  [ "$(ls "$tmp/meta/catalog" | wc -l | tr -d ' ')" = 8 ]
}

# --- the switch on: the Jetson files -----------------------------------------------

@test "switch on: stage publishes the slot image, the bundle, the kit and the Agreement next to them, in SHA256SUMS" {
  today_out
  jetson_out
  notes link hardware
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  echo "$output"
  [ "$status" -eq 0 ]
  n=ironflockos-jetson-orin-base-1.0.0
  for f in "$n.rootfs.ext4.zst" "$n.raucb" "$n.os-release" "$n.packages.tsv" "$n.cdx.json" NVIDIA-LICENSE.txt ironflockos-jetson-flash-kit-1.0.0.tar.gz; do
    staged "$output" | grep -qx "$f"
  done
  [ "$(staged "$output" | wc -l | tr -d ' ')" = 54 ]
  sums=$(bash "$publish" sums "$tmp/out")
  [[ "$sums" == *"  NVIDIA-LICENSE.txt"* ]] && [[ "$sums" == *"  ironflockos-jetson-flash-kit-1.0.0.tar.gz"* ]] && [[ "$sums" == *"  $n.rootfs.ext4.zst"* ]]
  [[ "$output" == *"Jetson files of 1 image(s)"* ]]
}

@test "switch on: meta lists the Jetson image's source packages apart, and no disk sizes" {
  today_out
  jetson_out
  bash "$publish" meta "$tmp/out" "$tmp/meta" 2>/dev/null
  [ "$(cat "$tmp/meta/sources.tsv")" = "$(printf 'bash\t5.2.37-2\nlinux\t6.12.115-2')" ]
  [ "$(cat "$tmp/meta/sources-ubuntu-noble.tsv")" = "$(printf 'bash\t5.2.21-2ubuntu4\nnvidia-l4t-core\t39.2.1-20260806224157')" ]
  [ -f "$tmp/meta/catalog/ironflockos-jetson-orin-base/ironflockos-jetson-orin-base-1.0.0.os-release" ]
  [ -z "$(find "$tmp/meta/catalog/ironflockos-jetson-orin-base" -name '*.sizes')" ]
}

@test "the release notes: a release with Jetson files links the Agreement and says it is not proven on hardware" {
  today_out
  jetson_out
  export IRONFLOCKOS_NOTES=$tmp/none
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"release-notes/1.0.0.md is missing"*"https://instance-registry.ironflock.com/dl/ironflockos/1.0.0/NVIDIA-LICENSE.txt"* ]]
  [[ "$output" != *"+ gcloud"* ]]
  notes hardware
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not link NVIDIA's Agreement"* ]]
  notes link
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not say that the Jetson image is not yet proven on hardware"*"HARDWARE_TESTED=no"* ]]
  notes link hardware
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -eq 0 ]
  # a release without Jetson files needs no notes
  rm -rf "$tmp/out/ironflockos-jetson-orin-base" "$tmp/notes"
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -eq 0 ]
}

@test "stage refuses Jetson files without the kit, without the Agreement, or with another Agreement" {
  today_out
  jetson_out
  notes link hardware
  d=$tmp/out/ironflockos-jetson-orin-base
  echo other >"$d/NVIDIA-LICENSE.txt"
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -ne 0 ] && [[ "$output" == *"is not NVIDIA's Agreement as bsp.conf pins it"* ]]
  rm "$d/NVIDIA-LICENSE.txt"
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -ne 0 ] && [[ "$output" == *"has no NVIDIA-LICENSE.txt"* ]]
  cp "$tmp/agreement.txt" "$d/NVIDIA-LICENSE.txt"
  mv "$d/ironflockos-jetson-flash-kit-1.0.0.tar.gz" "$d/ironflockos-jetson-flash-kit-0.9.0.tar.gz"
  DRY_RUN=1 run bash "$publish" stage "$tmp/out" 1.0.0
  [ "$status" -ne 0 ] && [[ "$output" == *"has no flash kit ironflockos-jetson-flash-kit-1.0.0.tar.gz"* ]]
}

@test "two files of one name in a release fail it" {
  today_out
  jetson_out
  mkdir -p "$tmp/out/ironflockos-jetson-orin-other"
  printf x >"$tmp/out/ironflockos-jetson-orin-other/NVIDIA-LICENSE.txt"
  run bash "$publish" sums "$tmp/out"
  [ "$status" -ne 0 ]
  [[ "$output" == *"two files of one name"*"NVIDIA-LICENSE.txt"* ]]
}

# --- the source mirror ----------------------------------------------------------

# jetson_list: the Jetson image's source packages from outside Ubuntu, as
# r39.2.1's packages and their dependencies have them.
jetson_list() {
  local p
  for p in bootloader bootloader-utils core cuda cuda-nvgpu firmware firmware-nvgpu init init-nvgpu initrd \
    nvfancontrol nvml nvpmodel tools; do
    printf 'nvidia-l4t-%s\t39.2.1-20260806224157\n' "$p"
  done
  for p in kernel kernel-nvgpu kernel-oot-modules kernel-dtbs kernel-module-configs display-kernel; do
    printf 'nvidia-l4t-%s\t6.8.12-tegra-39.2.1-20260806224157\n' "$p"
  done
  printf 'libnvidia-container\t1.19.1-1\nnvidia-container-toolkit\t1.19.1-1\n'
  printf 'docker-ce\t5:29.10.0-1~ubuntu.24.04~noble\ncontainerd.io\t2.4.2-4~ubuntu.24.04~noble\n'
}

@test "release/sources: every line is upstream, l4t, initrd, none or open; no none line names a copyleft licence; nothing is open" {
  run awk '!/^[ \t]*(#|$)/ && !($2 == "upstream" && $3 ~ /^https:\/\/[^ ]*\{upstream\}[^ ]*$/ && NF == 3) && !($2 == "l4t" && $3 ~ /^[A-Z][A-Z0-9_]*$/ && NF == 3) && !($2 == "initrd" && NF == 3) && !(($2 == "none" || $2 == "open") && NF >= 3) { print FILENAME ":" FNR ": " $0 }' \
    "$repo/release/sources"
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run awk '$2 == "none" && /GPL/' "$repo/release/sources"
  [ -z "$output" ]
  run awk '!/^[ \t]*#/ && $2 == "open"' "$repo/release/sources"
  [ -z "$output" ]
}

# fake_archive: docker that answers resolve as apt in the build container
# would for every source package, from Ubuntu's primary archive.
fake_archive() {
  mkdir -p "$tmp/bin"
  cat >"$tmp/bin/docker" <<'EOF'
#!/bin/bash
case "$*" in *"sources.sh resolve ubuntu-noble"*) ;; *) echo "docker: $*" >&2; exit 2 ;; esac
while IFS=$'\t' read -r src ver; do
  v=${ver#*:}
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$src" "$ver" "http://archive.ubuntu.com/ubuntu/pool/main/x/$src/${src}_$v.dsc" "${src}_$v.dsc" 1 "SHA256:00"
done
EOF
  chmod +x "$tmp/bin/docker"
}

@test "every NVIDIA source package of the Jetson tree has its decision; NVIDIA's GPL parts and the boot firmware get the L4T sources" {
  load_conf "$repo/targets/jetson-orin/bsp.conf"
  jetson_list >"$tmp/list"
  fake_archive
  PATH="$tmp/bin:$PATH" run bash "$sources" plan "$tmp/list" ubuntu-noble
  echo "$output"
  [ "$status" -eq 0 ]
  plan=$(grep -v '^==>' <<<"$output")
  [ "$(grep -c '^nvidia-l4t-' <<<"$plan")" = 20 ]
  [ "$(grep -c 'OPEN' <<<"$plan")" = 0 ]
  for p in kernel kernel-nvgpu kernel-oot-modules kernel-dtbs display-kernel bootloader; do
    grep -q "^nvidia-l4t-$p	[^	]*	l4t-39.2.1/public_sources.tbz2	$L4T_SOURCES_URL	SHA256:$L4T_SOURCES_SHA256	-$" <<<"$plan"
  done
  grep -q "^libnvidia-container	1.19.1-1	l4t-39.2.1/libnvidia-container-1.19.1.tar.gz	$LIBNVIDIA_CONTAINER_SOURCE_URL	SHA256:$LIBNVIDIA_CONTAINER_SOURCE_SHA256	-$" <<<"$plan"
  grep -q "^nvidia-l4t-core	39.2.1-20260806224157	-	-	-	NVIDIA Driver License Agreement" <<<"$plan"
  # NVIDIA's initrd: its Ubuntu programs' source packages, from Ubuntu's archive
  grep -q "^nvidia-l4t-initrd	39.2.1-20260806224157	-	-	-	its initrd's Ubuntu programs: their source packages are listed here (targets/jetson-orin/initrd.sources)" <<<"$plan"
  for s in busybox bash coreutils glibc util-linux; do
    grep -q "^$s	[^	]*	ubuntu/$s/" <<<"$plan" || { echo "no $s"; return 1; }
  done
  n=$(awk -F'\t' '!/^#/ && !/^[A-Z0-9_]+=/ && NF >= 5 { print $3 "\t" $4 }' "$repo/targets/jetson-orin/initrd.sources" | sort -u | wc -l | tr -d ' ')
  [ "$(grep -c '	ubuntu/' <<<"$plan")" -ge "$n" ]
}

@test "an open decision fails the plan" {
  printf 'nvidia-l4t-x\t39.2.1-20260806224157\n' >"$tmp/list"
  printf 'nvidia-l4t-x open no decision yet\n' >"$tmp/rules"
  # a copy of the repository's tools with one open line in release/sources
  mkdir -p "$tmp/repo"
  cp -R "$repo/build" "$repo/release" "$repo/targets" "$repo/distros" "$tmp/repo/"
  cat "$tmp/rules" >>"$tmp/repo/release/sources"
  run bash "$tmp/repo/build/sources.sh" plan "$tmp/list" ubuntu-noble
  [ "$status" -ne 0 ]
  [[ "$output" == *"error: the source of nvidia-l4t-x 39.2.1-20260806224157 is open (release/sources): no decision yet"* ]]
  SOURCES_ALLOW_OPEN=1 run bash "$tmp/repo/build/sources.sh" plan "$tmp/list" ubuntu-noble
  [ "$status" -eq 0 ]
  [[ "$output" == *$'nvidia-l4t-x\t39.2.1-20260806224157\t-\t-\t-\tOPEN: no decision yet'* ]]
}

# The source packages of today's images (the other targets) that
# release/sources decides, at the pins of 0.18.0.
today_decided() {
  printf '%s\t%s\n' \
    docker-ce '5:29.10.0-1~debian.13~trixie' containerd.io '2.4.2-4~debian.13~trixie' \
    docker-buildx-plugin '0.39.0-1~debian.13~trixie' docker-compose-plugin '5.7.1-1~debian.13~trixie' \
    nvidia-graphics-drivers 620.70.06-1 nvidia-persistenced 620.70.06-1 libnvidia-container 1.20.1-1 \
    nvidia-container-toolkit 1.20.1-1 nvidia-modprobe 620.70.06-1 ironflockos-nvidia-modules 620.70.06-1
}

@test "today's images: release/sources decides as before, but for libnvidia-container, which now gets its tag's source" {
  today_decided >"$tmp/list"
  run bash "$sources" plan "$tmp/list"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    docker-ce '5:29.10.0-1~debian.13~trixie' - - - 'Apache-2.0 (https://github.com/docker/docker-ce-packaging)' \
    containerd.io '2.4.2-4~debian.13~trixie' - - - 'Apache-2.0 (https://github.com/containerd/containerd)' \
    docker-buildx-plugin '0.39.0-1~debian.13~trixie' - - - 'Apache-2.0 (https://github.com/docker/buildx)' \
    docker-compose-plugin '5.7.1-1~debian.13~trixie' - - - 'Apache-2.0 (https://github.com/docker/compose)' \
    nvidia-graphics-drivers 620.70.06-1 - - - "NVIDIA's proprietary driver licence: binaries only" \
    nvidia-persistenced 620.70.06-1 - - - 'MIT (https://github.com/NVIDIA/nvidia-persistenced)' \
    libnvidia-container 1.20.1-1 upstream/libnvidia-container/libnvidia-container_1.20.1.tar.gz \
    https://github.com/NVIDIA/libnvidia-container/archive/refs/tags/v1.20.1.tar.gz - - \
    nvidia-container-toolkit 1.20.1-1 - - - 'Apache-2.0 (https://github.com/NVIDIA/nvidia-container-toolkit)' \
    nvidia-modprobe 620.70.06-1 upstream/nvidia-modprobe/nvidia-modprobe_620.70.06.tar.gz \
    https://github.com/NVIDIA/nvidia-modprobe/archive/refs/tags/620.70.06.tar.gz - - \
    ironflockos-nvidia-modules 620.70.06-1 upstream/ironflockos-nvidia-modules/ironflockos-nvidia-modules_620.70.06.tar.gz \
    https://github.com/NVIDIA/open-gpu-kernel-modules/archive/refs/tags/620.70.06.tar.gz - -)" ]
  # the one difference to 0.18.0's releases: libnvidia-container was
  # "none Apache-2.0" and is the upstream tarball of its tag
  grep -qx 'libnvidia-container       upstream https://github.com/NVIDIA/libnvidia-container/archive/refs/tags/v{upstream}.tar.gz' "$repo/release/sources"
}

@test "an L4T package of another version than the pinned sources fails the plan" {
  printf 'nvidia-l4t-kernel\t6.8.12-tegra-39.2.2-20261001000000\n' >"$tmp/list"
  run bash "$sources" plan "$tmp/list" ubuntu-noble
  [ "$status" -ne 0 ]
  [[ "$output" == *"nvidia-l4t-kernel 6.8.12-tegra-39.2.2-20261001000000 is not the version whose source bsp.conf pins (L4T_SOURCES_VERSION 39.2.1-20260806224157)"* ]]
}

@test "the source pins belong to the packages the target pins" {
  load_conf "$repo/targets/jetson-orin/target.conf"
  load_conf "$repo/targets/jetson-orin/bsp.conf"
  [ "$L4T_SOURCES_VERSION" = "$L4T_PACKAGE_VERSION" ]
  [ "$LIBNVIDIA_CONTAINER_SOURCE_VERSION" = "$L4T_CONTAINER_TOOLKIT_VERSION" ]
  [ "$L4T_SOURCES_URL" = "https://developer.download.nvidia.com/embedded/L4T/r39_Release_v${L4T_VERSION#*.}/sources/public_sources.tbz2" ] ||
    [ "$L4T_SOURCES_URL" = "https://developer.download.nvidia.com/embedded/L4T/r39_Release_v2.1/sources/public_sources.tbz2" ]
  [[ "$L4T_SOURCES_SHA256" =~ ^[0-9a-f]{64}$ ]] && [[ "$LIBNVIDIA_CONTAINER_SOURCE_SHA256" =~ ^[0-9a-f]{64}$ ]]
  [ "$LIBNVIDIA_CONTAINER_SOURCE_URL" = "https://github.com/NVIDIA/libnvidia-container/archive/refs/tags/v${L4T_CONTAINER_TOOLKIT_VERSION%-*}.tar.gz" ]
  [ "$(l4t_sources_dir)" = "l4t-$L4T_VERSION" ]
}

# fake_ubuntu: docker that answers resolve as apt in the build container
# would (bash from Ubuntu's archive, coreutils not there any more), and curl
# that answers Launchpad's API for coreutils.
fake_ubuntu() {
  mkdir -p "$tmp/bin"
  cat >"$tmp/bin/docker" <<'EOF'
#!/bin/bash
case "$*" in *"sources.sh resolve ubuntu-noble"*) ;; *) echo "docker: $*" >&2; exit 2 ;; esac
while IFS=$'\t' read -r src ver; do
  case "$src" in
    bash) printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$src" "$ver" "http://archive.ubuntu.com/ubuntu/pool/main/b/bash/bash_$ver.dsc" "bash_$ver.dsc" 2429 "SHA256:d73f" ;;
    *) printf '%s\t%s\t-\n' "$src" "$ver" ;;
  esac
done
EOF
  cat >"$tmp/bin/curl" <<'EOF'
#!/bin/bash
url=${*: -1}
case "$url" in
  *getPublishedSources*source_name=coreutils*)
    echo '{"entries": [{"source_package_version": "9.4-3ubuntu6", "distro_series_link": "https://api.launchpad.net/1.0/ubuntu/jammy", "self_link": "https://api.launchpad.net/1.0/ubuntu/+archive/primary/+sourcepub/1"},
      {"source_package_version": "9.4-3ubuntu6", "distro_series_link": "https://api.launchpad.net/1.0/ubuntu/noble", "self_link": "https://api.launchpad.net/1.0/ubuntu/+archive/primary/+sourcepub/2"}]}' ;;
  *getPublishedSources*) echo '{"entries": []}' ;;
  */+sourcepub/2?ws.op=sourceFileUrls*)
    echo '[{"url": "https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/coreutils/9.4-3ubuntu6/coreutils_9.4-3ubuntu6.dsc", "size": 1, "sha256": "'"$(printf a%.0s {1..64})"'"},
      {"url": "https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/coreutils/9.4-3ubuntu6/coreutils_9.4.orig.tar.xz", "size": 2, "sha256": "'"$(printf b%.0s {1..64})"'"}]' ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "$tmp/bin/docker" "$tmp/bin/curl"
}

@test "Ubuntu's source packages: from Ubuntu's archive, and from Launchpad when the archive no longer has the version" {
  fake_ubuntu
  printf 'bash\t5.2.21-2ubuntu4\ncoreutils\t9.4-3ubuntu6\n' >"$tmp/list"
  PATH="$tmp/bin:$PATH" run bash "$sources" plan "$tmp/list" ubuntu-noble
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash	5.2.21-2ubuntu4	ubuntu/bash/bash_5.2.21-2ubuntu4.dsc	http://archive.ubuntu.com/ubuntu/pool/main/b/bash/bash_5.2.21-2ubuntu4.dsc	SHA256:d73f	-"* ]]
  [[ "$output" == *"coreutils	9.4-3ubuntu6	ubuntu/coreutils/coreutils_9.4-3ubuntu6.dsc	https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/coreutils/9.4-3ubuntu6/coreutils_9.4-3ubuntu6.dsc	SHA256:aaaa"* ]]
  [[ "$output" == *"coreutils	9.4-3ubuntu6	ubuntu/coreutils/coreutils_9.4.orig.tar.xz	"*"SHA256:bbbb"* ]]
  # a version neither has fails, and names the way out
  printf 'zsh\t1.0-1\n' >"$tmp/list"
  PATH="$tmp/bin:$PATH" run bash "$sources" plan "$tmp/list" ubuntu-noble
  [ "$status" -ne 0 ]
  [[ "$output" == *"no source for: zsh 1.0-1. A source package outside Ubuntu's archive needs a line in release/sources."* ]]
  run bash "$sources" plan "$tmp/list" fedora-40
  [ "$status" -ne 0 ]
}

@test "resolve takes Ubuntu's source indexes from its primary and security archives, signed by its archive key" {
  load_conf "$repo/distros/ubuntu-noble/versions"
  [ "$DISTRO_SOURCE_MIRROR" = http://archive.ubuntu.com/ubuntu ]
  [ "$DISTRO_SOURCE_SECURITY_MIRROR" = http://security.ubuntu.com/ubuntu ]
  [ "$LAUNCHPAD_API" = https://api.launchpad.net/1.0 ]
  body=$(sed -n '/^resolve() {/,/^}/p' "$sources")
  [[ "$body" == *'install --no-install-recommends ca-certificates ubuntu-keyring'* ]]
  [[ "$body" == *'"$DISTRO_SOURCE_MIRROR" "$DISTRO_SUITE" "$DISTRO_SUITE" "$DISTRO_COMPONENTS" "$DISTRO_KEYRING"'* ]]
  [[ "$body" == *'"$DISTRO_SOURCE_SECURITY_MIRROR" "$DISTRO_SUITE" "$DISTRO_COMPONENTS" "$DISTRO_KEYRING"'* ]]
}

@test "publish.sh sources: the L4T mirror and Ubuntu's pool are paths of the pool; SOURCES names them" {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    nvidia-l4t-kernel 6.8.12-tegra-39.2.1-20260806224157 l4t-39.2.1/public_sources.tbz2 https://developer.download.nvidia.com/x/public_sources.tbz2 SHA256:83 - \
    nvidia-l4t-bootloader 39.2.1-20260806224157 l4t-39.2.1/public_sources.tbz2 https://developer.download.nvidia.com/x/public_sources.tbz2 SHA256:83 - \
    bash 5.2.21-2ubuntu4 ubuntu/bash/bash_5.2.21-2ubuntu4.dsc http://archive.ubuntu.com/ubuntu/pool/main/b/bash/bash_5.2.21-2ubuntu4.dsc SHA256:d7 - >"$tmp/plan"
  DRY_RUN=1 run bash "$publish" sources "$tmp/plan" 1.0.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"would have uploaded 2 of the release's 2 source files"* ]]
  run bash "$sources" index "$tmp/plan" 1.0.0
  [[ "$output" == *$'nvidia-l4t-kernel\t6.8.12-tegra-39.2.1-20260806224157\thttps://instance-registry.ironflock.com/dl/ironflockos/sources/l4t-39.2.1/public_sources.tbz2'* ]]
  for bad in l4t-x/public_sources.tbz2 l4t-39.2.1/../manifest.json ubuntu/../x; do
    printf 'x\t1\t%s\thttps://x\tSHA256:00\t-\n' "$bad" >"$tmp/plan"
    DRY_RUN=1 run bash "$publish" sources "$tmp/plan" 1.0.0
    [ "$status" -ne 0 ]
  done
}

# --- the contact and the check before a release with Jetson files ---------------------

@test "the contact is IronFlock's as given, complete, and an emptied copy fails with a clear message" {
  load_contact "$repo/release/contact"
  [ "$CONTACT_NAME" = "IronFlock GmbH" ]
  [ "$CONTACT_STREET" = "Taunusanlage 8" ]
  [ "$CONTACT_CITY" = "60329 Frankfurt am Main" ]
  [ "$CONTACT_EMAIL" = "legal@ironflock.com" ]
  [ "$(grep -vc '^#' "$repo/release/contact")" = 4 ]
  sed 's/^CONTACT_STREET=.*/CONTACT_STREET=/' "$repo/release/contact" >"$tmp/contact"
  run load_contact "$tmp/contact"
  [ "$status" -ne 0 ]
  [[ "$output" == *"the contact of the source offers is incomplete (empty: CONTACT_STREET)"* ]]
}

@test "jetson-release.sh check: what a release with Jetson files needs before it starts" {
  load_conf "$repo/build/release.conf"
  grep -v ' open ' "$repo/release/sources" >"$tmp/rules"
  notes link hardware
  IRONFLOCKOS_RULES=$tmp/rules run bash "$jr" check 1.0.0
  echo "$output"
  [ "$status" -eq 0 ]
  # the repository as it is: nothing open
  run bash "$jr" check 1.0.0
  echo "$output"
  [ "$status" -eq 0 ]
  # an open decision stops it
  printf 'nvidia-l4t-x open no decision yet\n' >>"$tmp/rules"
  IRONFLOCKOS_RULES=$tmp/rules run bash "$jr" check 1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"release/sources: the source of nvidia-l4t-x is still open"* ]]
  [[ "$output" != *"bsp.conf:"* ]]
  # an emptied contact, notes without the link: each named
  grep -v ' open ' "$repo/release/sources" >"$tmp/rules"
  sed 's/^CONTACT_NAME=.*/CONTACT_NAME=/' "$repo/release/contact" >"$tmp/contact"
  notes hardware
  IRONFLOCKOS_RULES=$tmp/rules IRONFLOCKOS_CONTACT=$tmp/contact run bash "$jr" check 1.0.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"the contact of the source offers is incomplete (empty: CONTACT_NAME)"* ]]
  [[ "$output" == *"does not link NVIDIA's Agreement"* ]]
  [[ "$output" == *"2 problem(s)"* ]]
}

@test "jetson-release.sh files: NVIDIA's Agreement from NVIDIA as pinned, and the kit, which holds nothing of NVIDIA's" {
  mkdir -p "$tmp/www"
  printf 'NVIDIA Driver License Agreement (stand-in)\n' >"$tmp/www/Tegra_Software_License_Agreement-Tegra-Linux.txt"
  sha1=$(sha1sum <"$tmp/www/Tegra_Software_License_Agreement-Tegra-Linux.txt" | cut -d' ' -f1)
  sha256=$(sha256sum <"$tmp/www/Tegra_Software_License_Agreement-Tegra-Linux.txt" | cut -d' ' -f1)
  printf '%s *./Tegra_Software_License_Agreement-Tegra-Linux.txt\n' "$sha1" >"$tmp/www/release_sha_hashes.txt"
  printf 'L4T_VERSION=39.2.1\nBSP_HASHES_URL=file://%s/www/release_sha_hashes.txt\nBSP_LICENSE_URL=file://%s/www/Tegra_Software_License_Agreement-Tegra-Linux.txt\nBSP_LICENSE_SHA1=%s\nBSP_LICENSE_SHA256=%s\n' \
    "$tmp" "$tmp" "$sha1" "$sha256" >"$tmp/bsp.conf"
  IRONFLOCKOS_BSP_CONF=$tmp/bsp.conf SOURCE_DATE_EPOCH=1700000000 run bash "$jr" files "$tmp/out" 1.0.0
  echo "$output"
  [ "$status" -eq 0 ]
  cmp "$tmp/out/NVIDIA-LICENSE.txt" "$tmp/www/Tegra_Software_License_Agreement-Tegra-Linux.txt"
  [ -f "$tmp/out/ironflockos-jetson-flash-kit-1.0.0.tar.gz" ]
  ! tar -tzf "$tmp/out/ironflockos-jetson-flash-kit-1.0.0.tar.gz" | grep -qi -e license_agreement -e NVIDIA-LICENSE
  # an Agreement that is not the pinned one is not taken
  echo changed >>"$tmp/www/Tegra_Software_License_Agreement-Tegra-Linux.txt"
  IRONFLOCKOS_BSP_CONF=$tmp/bsp.conf run bash "$jr" files "$tmp/out2" 1.0.0
  [ "$status" -ne 0 ]
  [ ! -e "$tmp/out2/NVIDIA-LICENSE.txt" ]
}

# --- the workflows -----------------------------------------------------------------

@test "the Jetson release image is checked and gets its Agreement and kit in image.yml, only for jetson-orin" {
  steps=$(grep -n "inputs.target == 'jetson-orin'" "$wf/image.yml" | wc -l | tr -d ' ')
  [ "$steps" = 2 ]
  grep -q 'build/jetson-release.sh files "out/ironflockos-$TARGET-$VARIANT$SUFFIX"' "$wf/image.yml"
  grep -q 'sudo test/image/jetson-rootfs-check.sh' "$wf/image.yml"
  # before the SBOM and the list of files a release may reuse the images by
  [ "$(grep -n 'run: build/jetson-release.sh files' "$wf/image.yml" | cut -d: -f1)" -lt "$(grep -n 'build/reuse.sh list' "$wf/image.yml" | cut -d: -f1)" ]
}

@test "release.yml: the check before a release with Jetson files, and Ubuntu's sources in the sources job" {
  grep -q "if: vars.JETSON_RELEASE == 'true' && (steps.mode.outputs.mode == 'release' || steps.mode.outputs.mode == 'dry-run')" "$wf/release.yml"
  grep -q 'run: build/jetson-release.sh check "$(tr -d' "$wf/release.yml"
  src_job=$(awk '$0 == "  sources:" { f = 1; next } f && /^  [a-z]/ { exit } f' "$wf/release.yml")
  [[ "$src_job" == *'build/sources.sh plan meta/sources.tsv > sources.plan'*'for f in meta/sources-*.tsv; do'*'build/sources.sh plan "$f" "${distro%.tsv}" >> sources.plan'* ]]
  grep -q 'rauc openssl e2fsprogs fdisk jq zstd' "$repo/build/sign-in-builder.sh"
}

@test "ci.yml proves the Jetson release path on every pull request with JETSON_CI, without the switch" {
  job=$(awk '$0 == "  jetson-release:" { f = 1; next } f && /^  [a-z]/ { exit } f' "$wf/ci.yml")
  [[ "$job" == *"needs: [jetson-rootfs]"* ]]
  [[ "$job" == *"if: vars.JETSON_CI == 'true'"* ]]
  [[ "$job" == *'test/image/jetson-release-check.sh out "$(tr -d'* ]]
  [[ "$job" != *"JETSON_RELEASE"* ]] && [[ "$job" != *"id-token"* ]] && [[ "$job" != *"gcloud"* ]]
  rootfs=$(awk '$0 == "  jetson-rootfs:" { f = 1; next } f && /^  [a-z]/ { exit } f' "$wf/ci.yml")
  [[ "$rootfs" == *'build/jetson-release.sh files out/ironflockos-jetson-orin-base'* ]]
  [ -x "$repo/test/image/jetson-release-check.sh" ] && [ -x "$jr" ]
}

# --- NVIDIA's initrd ------------------------------------------------------------

@test "initrd.sources: the Ubuntu packages of NVIDIA's initrd at the pin, each with its source, and the initrd's hash" {
  f=$repo/targets/jetson-orin/initrd.sources
  load_conf "$repo/targets/jetson-orin/target.conf"
  [ "$(sed -n 's/^INITRD_PACKAGE=//p' "$f")" = nvidia-l4t-initrd ]
  [ "$(sed -n 's/^INITRD_PACKAGE_VERSION=//p' "$f")" = "$L4T_PACKAGE_VERSION" ]
  [[ "$(sed -n 's/^INITRD_SHA256=//p' "$f")" =~ ^[0-9a-f]{64}$ ]]
  # every line: binary, version, source, source version, Built-Using, counts
  run awk -F'\t' '!/^#/ && !/^[A-Z0-9_]+=/ && !(NF == 6 && $1 ~ /^[a-z0-9][a-z0-9+.-]*$/ && $3 ~ /^[a-z0-9][a-z0-9+.-]*$/ && $4 ~ /^[0-9A-Za-z.+~:-]+$/ && $6 ~ /^[0-9]+ [1-9][0-9]*$/) { print FNR ": " $0 }' "$f"
  [ -z "$output" ]
  for p in busybox bash coreutils libc6 util-linux kmod e2fsprogs; do
    grep -q "^$p	" "$f" || { echo "no $p"; return 1; }
  done
  # the files from no Ubuntu package: NVIDIA's init and firmware
  grep -q '^# not from Ubuntu: init	.*LicenseRef-NvidiaProprietary' "$f"
  # the build and the root tree check hold the image's initrd to the hash
  grep -q 'initrd_sha=$(sed -n '"'"'s/^INITRD_SHA256=//p'"'"' "$target_dir/initrd.sources")' "$repo/build/customize.sh"
  grep -q 'initrd.sources lists the Ubuntu programs of' "$repo/test/image/jetson-rootfs-check.sh"
  [ -x "$repo/tools/initrd-sources.py" ]
}

@test "the plan refuses an initrd.sources of another initrd version" {
  printf 'nvidia-l4t-initrd\t39.2.2-20261001000000\n' >"$tmp/list"
  run bash "$sources" plan "$tmp/list" ubuntu-noble
  [ "$status" -ne 0 ]
  [[ "$output" == *"nvidia-l4t-initrd 39.2.2-20261001000000: targets/jetson-orin/initrd.sources lists the initrd of 39.2.1-20260806224157"* ]]
}
