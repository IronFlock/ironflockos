#!/usr/bin/env bash
# The release path of a Jetson image, as a dry run (docs/release.md,
# "Jetson"; ci.yml's jetson-release): the code a release with JETSON_RELEASE
# true runs, on a build's Jetson image, without publishing anything.
#   jetson-release-check.sh OUT VERSION
#
# OUT holds the image as build/jetson-release.sh files leaves it
# (OUT/ironflockos-jetson-orin-base/: the slot image, the bundle, the
# os-release, the package lists, NVIDIA-LICENSE.txt and the flash kit).
# It proves, and fails at the first that does not hold:
# 1. stage (build/publish.sh, DRY_RUN=1) refuses the release without notes
#    that link NVIDIA's Agreement and say the image is not proven on
#    hardware, and with such notes would publish exactly the slot image, the
#    bundle, the flash kit, NVIDIA-LICENSE.txt, the os-release, the package
#    list, the SBOM and SHA256SUMS to <version>/;
# 2. NVIDIA-LICENSE.txt is the Agreement as bsp.conf pins it;
# 3. the catalog (tools/catalog, signed with a throwaway key) names the slot
#    image, bundle and kit with their hashes. The Agreement and FlockFlasher
#    board list stay outside the Jetson entry;
# 4. the source mirror: every source package of the image has a place
#    (Ubuntu's archive or Launchpad, release/sources), NVIDIA's sources go to
#    ironflockos/sources/l4t-<L4T version>/, and sources (DRY_RUN=1) would
#    upload them; an open decision is reported, not refused (a release
#    refuses it);
# 5. the FreeRTOS statement in the slot image offers the source at that
#    mirror and names the contact (release/contact), and the image carries
#    the Agreement byte for byte.
#
# Needs docker (apt in the build container, build/sources.sh), go, jq, zstd
# and debugfs. IRONFLOCKOS_WORK: the scratch space (the slot image is
# unpacked there).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../.." && pwd)
# shellcheck source=build/lib.sh
. "$src/build/lib.sh"

[ "$#" -eq 2 ] || die "usage: jetson-release-check.sh OUT VERSION"
out=$(cd "$1" && pwd)
version=$2
require jq go zstd debugfs sha256sum gzip
mapfile -t dirs < <(find "$out" -mindepth 1 -maxdepth 1 -type d -name 'ironflockos-jetson-orin-*' | sort)
[ "${#dirs[@]}" -eq 1 ] || die "$out holds ${#dirs[@]} Jetson images, not one"
d=${dirs[0]}
id=$(basename "$d")
name=$id-$version
load_conf "$src/build/release.conf"
load_conf "$src/targets/jetson-orin/target.conf"
load_conf "$src/targets/jetson-orin/bsp.conf"
mirror=$(l4t_sources_dir)
work=$(mktemp -d "${IRONFLOCKOS_WORK:-${TMPDIR:-/tmp}}/jetson-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
publish=$src/build/publish.sh
pass() { printf -- '- %s\n' "$*"; }

echo "## The Jetson release of $version, dry run"
echo

# A development build has no SBOM: a release build makes it (image.yml).
if [ ! -f "$d/$name.cdx.json" ]; then
  printf '{"bomFormat":"CycloneDX","specVersion":"1.6","components":[]}\n' >"$d/$name.cdx.json"
  pass "no SBOM in a development build: a stand-in for $name.cdx.json, which a release build makes"
fi

# --- 1. what stage publishes, and the release notes ------------------------
if IRONFLOCKOS_NOTES=$work/none DRY_RUN=1 bash "$publish" stage "$out" "$version" >"$work/refused.log" 2>&1; then
  cat "$work/refused.log" >&2
  die "stage would publish Jetson files without release notes"
fi
grep -q "NVIDIA-LICENSE.txt" "$work/refused.log" || {
  cat "$work/refused.log" >&2
  die "stage refused the release without notes, but not for the Agreement's link"
}
pass "without release notes that link NVIDIA's Agreement, stage refuses the release"
mkdir -p "$work/notes"
printf '## New\n\n- IronFlockOS for NVIDIA Jetson Orin, not yet proven on hardware. NVIDIA'"'"'s Driver License Agreement: [NVIDIA-LICENSE.txt](%s)\n' \
  "$DL_BASE/ironflockos/$version/NVIDIA-LICENSE.txt" >"$work/notes/$version.md"
IRONFLOCKOS_NOTES=$work/notes DRY_RUN=1 bash "$publish" stage "$out" "$version" >"$work/stage.log" 2>&1 || {
  cat "$work/stage.log" >&2
  die "stage refused the release"
}
sed -n "s|^+ gcloud storage cp .* $BUCKET/staging/ironflockos/$version/||p" "$work/stage.log" | LC_ALL=C sort >"$work/staged"
printf '%s\n' "$name.rootfs.ext4.zst" "$name.raucb" "$name.os-release" "$name.packages.tsv" "$name.cdx.json" \
  NVIDIA-LICENSE.txt "ironflockos-jetson-flash-kit-$version.tar.gz" SHA256SUMS | LC_ALL=C sort >"$work/want"
if ! cmp -s "$work/want" "$work/staged"; then
  diff "$work/want" "$work/staged" >&2 || true
  die "stage would publish other files than a Jetson release's (above: - missing, + extra)"
fi
pass "stage would publish to $BUCKET/staging/ironflockos/$version/, and promote to ironflockos/$version/: $(tr '\n' ' ' <"$work/staged")"

# --- 2. the Agreement ---------------------------------------------------------
[ "$(sha256sum <"$d/NVIDIA-LICENSE.txt" | cut -d' ' -f1)" = "$BSP_LICENSE_SHA256" ] ||
  die "NVIDIA-LICENSE.txt is not the Agreement bsp.conf pins"
pass "NVIDIA-LICENSE.txt is NVIDIA's Agreement as bsp.conf pins it ($BSP_LICENSE_SHA256)"

# --- 3. the catalog -----------------------------------------------------------
bash "$publish" meta "$out" "$work/meta" >/dev/null 2>&1
openssl genpkey -algorithm ed25519 -out "$work/key.pem" 2>/dev/null
openssl pkey -in "$work/key.pem" -pubout -out "$work/key.pub" 2>/dev/null
(
  cd "$src/tools/catalog"
  go run . build -dir "$work/meta/catalog" -files "$work/meta/files.tsv" -repo "$src" -version "$version" -channel test \
    -url "$DL_BASE/ironflockos/$version" -min-agent "$CATALOG_MIN_AGENT" -boards "$src/release/boards.json" -o "$work/payload.json"
  go run . sign -payload "$work/payload.json" -key-file "$work/key.pem" -pubkey "$work/key.pub" -o "$work/manifest.json"
  go run . verify -pubkey "$work/key.pub" "$work/manifest.json" >/dev/null
)
sha_of() { sha256sum <"$d/$1" | cut -d' ' -f1; }
jq -e --arg v "$version" --arg id "$id" --arg base "$DL_BASE/ironflockos/$version" \
  --arg slot "$name.rootfs.ext4.zst" --arg slot_sha "$(sha_of "$name.rootfs.ext4.zst")" \
  --arg kit "ironflockos-jetson-flash-kit-$version.tar.gz" --arg kit_sha "$(sha_of "ironflockos-jetson-flash-kit-$version.tar.gz")" \
  --arg bundle "$name.raucb" --arg bundle_sha "$(sha_of "$name.raucb")" '
  .releases[$v].images[$id] as $i
  | $i.target == "jetson-orin" and $i.architecture == "arm64"
  and $i.image.url == "\($base)/\($slot)" and $i.image.sha256 == $slot_sha
  and ($i.image | has("raw_size") | not) and ($i | has("modules_alias") | not)
  and $i.flash_kit.url == "\($base)/\($kit)" and $i.flash_kit.sha256 == $kit_sha
  and $i.bundle.url == "\($base)/\($bundle)" and $i.bundle.sha256 == $bundle_sha and $i.bundle.compatible == $id
  and ([.boards[].latestImages[].image_id] | index($id) == null)' "$work/payload.json" >/dev/null || {
  jq --arg v "$version" '.releases[$v]' "$work/payload.json" >&2
  die "the catalog does not name the slot image and the bundle as a release must"
}
if grep -q NVIDIA-LICENSE "$work/payload.json"; then
  die "the catalog names the Agreement"
fi
pass "the catalog (signed with a throwaway key, verified) names $name.rootfs.ext4.zst and $name.raucb and the flash kit with their hashes; no board or Agreement"

# --- 4. the source mirror -----------------------------------------------------
list=$(find "$work/meta" -maxdepth 1 -name 'sources-*.tsv' | sort)
[ "$(echo "$list" | wc -l)" -eq 1 ] && [ -n "$list" ] || die "meta has no single list of the Jetson image's source packages: $list"
distro=$(basename "$list" .tsv)
distro=${distro#sources-}
SOURCES_ALLOW_OPEN=1 bash "$src/build/sources.sh" plan "$list" "$distro" >"$work/sources.plan" 2>"$work/plan.log" || {
  cat "$work/plan.log" >&2
  die "a source package of the Jetson image has no source and no decision"
}
grep -F 'warning:' "$work/plan.log" >&2 || true
awk -F'\t' -v p="$mirror/$L4T_SOURCES_FILE" -v u="$L4T_SOURCES_URL" -v h="SHA256:$L4T_SOURCES_SHA256" \
  '$3 == p && $4 == u && $5 == h { n++ } END { exit !n }' "$work/sources.plan" ||
  die "the plan does not mirror NVIDIA's $L4T_SOURCES_FILE to $mirror/"
awk -F'\t' -v p="$mirror/$LIBNVIDIA_CONTAINER_SOURCE_FILE" '$1 == "libnvidia-container" && $3 == p { n++ } END { exit !n }' "$work/sources.plan" ||
  die "the plan does not mirror libnvidia-container's source to $mirror/"
awk -F'\t' '$3 ~ /^ubuntu\// { n++ } END { exit !n }' "$work/sources.plan" || die "the plan has no Ubuntu source package"
missing=$(cut -f1 "$list" | grep '^nvidia-l4t-' | while read -r s; do awk -F'\t' -v s="$s" '$1 == s { f = 1 } END { exit !f }' "$work/sources.plan" || echo "$s"; done)
[ -z "$missing" ] || die "the plan lacks $missing"
bash "$src/build/sources.sh" index "$work/sources.plan" "$version" >"$work/SOURCES"
grep -qF "$DL_BASE/ironflockos/sources/$mirror/$L4T_SOURCES_FILE" "$work/SOURCES" || die "SOURCES does not name $mirror/$L4T_SOURCES_FILE"
DRY_RUN=1 bash "$publish" sources "$work/sources.plan" "$version" >"$work/sources.log" 2>&1 || {
  cat "$work/sources.log" >&2
  die "publish.sh sources refused the plan"
}
grep -q "staging/ironflockos/$version/SOURCES" "$work/sources.log" || die "publish.sh sources would not stage SOURCES"
open=$(awk -F'\t' '$6 ~ /^OPEN: / { print $1 }' "$work/sources.plan" | sort -u | tr '\n' ' ')
pass "the source mirror: $(cut -f1,2 "$work/sources.plan" | sort -u | wc -l | tr -d ' ') source packages, $(awk -F'\t' '$3 ~ /^ubuntu\//' "$work/sources.plan" | wc -l | tr -d ' ') files from Ubuntu, NVIDIA's $L4T_SOURCES_FILE and $LIBNVIDIA_CONTAINER_SOURCE_FILE to ironflockos/sources/$mirror/; SOURCES staged"
if [ -n "$open" ]; then
  pass "**open, which a release refuses: ${open% }** (release/sources)"
fi

# --- 5. the statement and the Agreement in the slot image ---------------------
zstd -q -dc "$d/$name.rootfs.ext4.zst" >"$work/slot.ext4"
debugfs -R "cat /usr/share/doc/ironflockos/FreeRTOS-source-offer.txt" "$work/slot.ext4" >"$work/offer.txt" 2>/dev/null
grep -qxF "  $DL_BASE/ironflockos/sources/$mirror/" "$work/offer.txt" ||
  die "the FreeRTOS statement in the slot image does not offer the source at the mirror ironflockos/sources/$mirror/"
load_contact "$src/release/contact"
for line in "$CONTACT_NAME" "$CONTACT_STREET" "$CONTACT_CITY"; do
  grep -qxF "  $line" "$work/offer.txt" || die "the FreeRTOS statement in the slot image does not name \"$line\""
done
grep -qF "$CONTACT_EMAIL" "$work/offer.txt" || die "the FreeRTOS statement in the slot image does not name $CONTACT_EMAIL"
debugfs -R "cat /usr/share/doc/nvidia-l4t-core/Tegra_Software_License_Agreement-Tegra-Linux.txt.gz" "$work/slot.ext4" 2>/dev/null |
  gzip -dc | sha256sum | cut -d' ' -f1 >"$work/agreement.sha"
rm -f "$work/slot.ext4"
[ "$(cat "$work/agreement.sha")" = "$BSP_LICENSE_SHA256" ] || die "the slot image does not carry the Agreement byte for byte"
pass "the slot image's FreeRTOS statement offers the source at that mirror and names $CONTACT_NAME, $CONTACT_STREET, $CONTACT_CITY, $CONTACT_EMAIL; it carries the Agreement byte for byte"
