#!/usr/bin/env bash
# The source code of an IronFlockOS release (docs/release.md, "Source code").
#   sources.sh image               the source packages of an image, from the
#                                  dpkg-query lines "<source:Package> TAB
#                                  <source:Version> TAB <Built-Using>" on
#                                  stdin: "<source> TAB <version>", sorted
#   sources.sh plan LIST [DISTRO]  where every file of every source package
#                                  in LIST comes from, to stdout. DISTRO
#                                  (distros/<distro>, default debian-trixie)
#                                  is the archive of the images LIST comes
#                                  from: for debian-trixie the build
#                                  container's apt for Debian and the
#                                  Raspberry Pi archive, snapshot.debian.org
#                                  for a version the archive no longer has;
#                                  for ubuntu-noble (Jetson) apt for Ubuntu's
#                                  archive, Launchpad for a version it no
#                                  longer has; release/sources for everything
#                                  else
#   sources.sh index PLAN VERSION  the release's SOURCES, to stdout
#   sources.sh resolve [DISTRO]    in the build container, for plan
#
# build/publish.sh sources uploads a plan's files and its SOURCES.
#
# A plan line is "<source> <version> <pool path> <URL> <hash> <note>", tab
# separated. The pool path is <archive>/<source>/<file> below
# DL_BASE/ironflockos/sources/ (archive: debian, raspberrypi, ubuntu or
# upstream), or l4t-<L4T version>/<file> for the sources a Jetson release
# mirrors from NVIDIA (l4t_sources_dir in build/lib.sh); the hash
# "SHA512:<hex>" (apt's for Ubuntu's archive), "SHA256:<hex>", "SHA1:<hex>"
# or "-" (an upstream tarball). A source
# package whose source is not published has "-" for pool path, URL and hash
# and its reason as the note.
#
# A release/sources line "<source> open REASON" (a source nobody has decided
# yet) fails the plan; with SOURCES_ALLOW_OPEN=1 (the pull request's dry run
# of the Jetson release, ci.yml) it is a plan line without source, its note
# "OPEN: REASON", and a warning.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"

SNAPSHOT=https://snapshot.debian.org
RULES=$repo/release/sources
BSP_CONF=$repo/targets/jetson-orin/bsp.conf

# image: stdin's dpkg-query lines as source packages: each package's own,
# and those its Built-Using names, Debian's field for licence compliance (the
# source of a signed kernel or boot loader is the unsigned one's). A long
# Built-Using continues on lines that start with a space.
image() {
  awk '
    function emit(   n, i, e, p) {
      if (src == "") return
      print src "\t" ver
      n = split(used, e, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", e[i])
        if (e[i] == "") continue
        if (e[i] !~ /^[a-z0-9][a-z0-9+.-]* \(= [^ ()]+\)$/) {
          print "error: not a Built-Using entry of " src ": " e[i] > "/dev/stderr"
          bad = 1
          continue
        }
        split(e[i], p, / \(= /)
        sub(/\)$/, "", p[2])
        print p[1] "\t" p[2]
      }
    }
    /^[ \t]/ {
      if (src == "") { print "error: a continuation line without a package: " $0 > "/dev/stderr"; bad = 1 }
      else used = used "," $0
      next
    }
    {
      emit()
      src = ""
      n = split($0, f, "\t")
      if (n < 2 || f[1] == "" || f[2] == "") { print "error: not a source line: " $0 > "/dev/stderr"; bad = 1; next }
      src = f[1]; ver = f[2]; used = f[3]
    }
    END { emit(); exit bad }' | LC_ALL=C sort -u
}

# snapshot SOURCE VERSION: the plan lines of a Debian source package from
# snapshot.debian.org, which keeps every version the archive ever had; fails
# when it does not know the version.
snapshot() {
  local src=$1 ver=$2 json lines
  json=$(curl -fsS --proto '=https' --retry 5 \
    "$SNAPSHOT/mr/package/$(jq -rn --arg s "$src" '$s | @uri')/$(jq -rn --arg v "$ver" '$v | @uri')/srcfiles?fileinfo=1" 2>/dev/null) ||
    return 1
  lines=$(jq -r --arg src "$src" --arg ver "$ver" --arg file "$SNAPSHOT/file/" '
    .fileinfo // {} | to_entries[] | .key as $hash
    | (.value | map(select(.archive_name == "debian" or .archive_name == "debian-security")) | first) as $f
    | select($f != null)
    | [$src, $ver, "debian/\($src)/\($f.name)", $file + $hash, "SHA1:" + $hash, "-"] | @tsv' <<<"$json") || return 1
  awk -F'\t' '$3 ~ /\.dsc$/ { found = 1 } END { exit !found }' <<<"$lines" || return 1
  printf '%s\n' "$lines"
}

# launchpad SOURCE VERSION: the plan lines of an Ubuntu source package of
# DISTRO_SUITE from Launchpad, which keeps every version Ubuntu ever
# published (its librarian), with each file's SHA-256 from Launchpad's API;
# fails when it does not know the version.
launchpad() {
  local src=$1 ver=$2 json pub lines
  json=$(curl -fsS --proto '=https' --retry 5 \
    "$LAUNCHPAD_API/ubuntu/+archive/primary?ws.op=getPublishedSources&exact_match=true&source_name=$(jq -rn --arg s "$src" '$s | @uri')&version=$(jq -rn --arg v "$ver" '$v | @uri')" 2>/dev/null) ||
    return 1
  pub=$(jq -r --arg suite "/ubuntu/$DISTRO_SUITE" '[.entries // [] | .[]
      | select(.source_package_version != null and (.distro_series_link // "" | endswith($suite)))] | first | .self_link // empty' <<<"$json") ||
    return 1
  [ -n "$pub" ] || return 1
  json=$(curl -fsS --proto '=https' --retry 5 "$pub?ws.op=sourceFileUrls&include_meta=true" 2>/dev/null) || return 1
  lines=$(jq -r --arg src "$src" --arg ver "$ver" '.[]
    | (.url | split("/") | last | gsub("%2B"; "+") | gsub("%7E"; "~") | gsub("%3A"; ":")) as $f
    | select((.sha256 // "") | test("^[0-9a-f]{64}$"))
    | [$src, $ver, "ubuntu/\($src)/\($f)", .url, "SHA256:" + .sha256, "-"] | @tsv' <<<"$json") || return 1
  awk -F'\t' '$3 ~ /\.dsc$/ { found = 1 } END { exit !found }' <<<"$lines" || return 1
  printf '%s\n' "$lines"
}

# l4t_files: for each "l4t NAME" of release/sources, "NAME <TAB> pool path
# <TAB> URL <TAB> SHA256:<hex> <TAB> version" from bsp.conf (NAME_FILE,
# NAME_URL, NAME_SHA256, NAME_VERSION), the pool path below
# l4t_sources_dir.
l4t_files() {
  local name file url sha ver dir
  load_conf "$BSP_CONF"
  dir=$(l4t_sources_dir)
  while read -r name; do
    [[ "$name" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "release/sources: l4t $name is not a name of bsp.conf"
    file=${name}_FILE url=${name}_URL sha=${name}_SHA256 ver=${name}_VERSION
    file=${!file:-} url=${!url:-} sha=${!sha:-} ver=${!ver:-}
    [[ "$file" =~ ^[A-Za-z0-9][A-Za-z0-9+._~-]*$ ]] && [[ "$url" == https://* ]] && [[ "$sha" =~ ^[0-9a-f]{64}$ ]] && [ -n "$ver" ] ||
      die "release/sources: l4t $name needs ${name}_FILE, ${name}_URL (https), ${name}_SHA256 and ${name}_VERSION in targets/jetson-orin/bsp.conf"
    printf '%s\t%s/%s\t%s\tSHA256:%s\t%s\n' "$name" "$dir" "$file" "$url" "$sha" "$ver"
  done < <(awk '!/^[ \t]*(#|$)/ && $2 == "l4t" { print $3 }' "$RULES" | sort -u)
}

# initrd_sources LIST: for each source package of LIST that release/sources
# decides "initrd FILE" (NVIDIA's initrd, built from Ubuntu's binary
# packages), the source packages FILE names, "<source> TAB <version>", and
# those their Built-Using names (as image does). FILE must be of that
# package's version (INITRD_PACKAGE_VERSION), or the plan fails.
initrd_sources() {
  local list=$1 src ver file want
  while read -r src file; do
    ver=$(awk -F'\t' -v s="$src" '$1 == s { print $2; exit }' "$list")
    [ -n "$ver" ] || continue
    [ -f "$repo/$file" ] || die "release/sources: $src: initrd $file does not exist"
    want=$(sed -n 's/^INITRD_PACKAGE_VERSION=//p' "$repo/$file")
    [ "$want" = "$ver" ] ||
      die "$src $ver: $file lists the initrd of ${want:-no version} (tools/initrd-sources.py makes it anew)"
    awk -F'\t' '!/^#/ && !/^[A-Z0-9_]+=/ && NF >= 5 { print $3 "\t" $4 ($5 == "-" ? "" : "\t" $5) }' "$repo/$file" |
      bash "$here/sources.sh" image
  done < <(awk '!/^[ \t]*(#|$)/ && $2 == "initrd" { print $1, $3 }' "$RULES")
}

plan() {
  local list=$1 distro=${2:-debian-trixie} src ver missing=() fallback
  [ -s "$list" ] || die "$list lists no source packages"
  [ -f "$RULES" ] || die "$RULES is missing"
  require awk
  case "$distro" in
    debian-trixie)
      load_conf "$repo/distros/debian-trixie/versions"
      RPI_MIRROR=$(sed -n 's/^RPI_MIRROR=//p' "$repo/targets/rpi-arm64/target.conf")
      [ -n "$RPI_MIRROR" ] || die "targets/rpi-arm64/target.conf names no RPI_MIRROR"
      fallback=snapshot
      ;;
    ubuntu-noble)
      load_conf "$repo/distros/ubuntu-noble/versions"
      : "${DISTRO_SOURCE_MIRROR:?}" "${DISTRO_SOURCE_SECURITY_MIRROR:?}" "${LAUNCHPAD_API:?}"
      fallback=launchpad
      ;;
    *) die "plan: no source archive known for $distro" ;;
  esac
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  l4t_files >"$tmp/l4t.tsv"
  # NVIDIA's initrd: the Ubuntu source packages of its programs join the list.
  initrd_sources "$list" >"$tmp/initrd.tsv"
  if [ -s "$tmp/initrd.tsv" ]; then
    LC_ALL=C sort -u "$list" "$tmp/initrd.tsv" >"$tmp/list.tsv"
    list=$tmp/list.tsv
  fi

  # release/sources first: "none" and "upstream" lines go to the plan as
  # they are, every other source package to the archives. An "l4t NAME"
  # line takes the versions of NAME_VERSION (with an epoch, and as the end
  # of a longer version: NVIDIA's kernel packages are
  # <kernel>-tegra-<L4T package version>); other versions of the same
  # source take its other line.
  awk -v archive="$tmp/archive.tsv" -v l4t="$tmp/l4t.tsv" -v allow_open="${SOURCES_ALLOW_OPEN:-0}" '
    BEGIN {
      FS = "\t"
      while ((getline line < l4t) > 0) { split(line, f, "\t"); lpath[f[1]] = f[2]; lurl[f[1]] = f[3]; lhash[f[1]] = f[4]; lver[f[1]] = f[5] }
      FS = " "
    }
    FNR == NR {
      if ($0 ~ /^[ \t]*(#|$)/) next
      n = split($0, w, /[ \t]+/)
      if (n < 3 || (w[2] != "none" && w[2] != "upstream" && w[2] != "l4t" && w[2] != "open" && w[2] != "initrd") || ((w[2] == "l4t" || w[2] == "initrd") && n != 3)) {
        print "error: release/sources:" FNR ": not \"<source> none|upstream|l4t|initrd|open ...\"" > "/dev/stderr"; bad = 1; next
      }
      arg = $0
      sub(/^[^ \t]+[ \t]+[^ \t]+[ \t]+/, "", arg)
      if (w[2] == "l4t") {
        if (w[1] in lname) { print "error: release/sources:" FNR ": a second l4t line for " w[1] > "/dev/stderr"; bad = 1 }
        lname[w[1]] = w[3]; next
      }
      if (w[1] in kind) { print "error: release/sources:" FNR ": a second line for " w[1] > "/dev/stderr"; bad = 1 }
      kind[w[1]] = w[2]; val[w[1]] = arg
      next
    }
    {
      FS = "\t"; split($0, f, "\t"); src = f[1]; ver = f[2]
      if (src !~ /^[a-z0-9][a-z0-9+.-]*$/ || ver !~ /^[0-9A-Za-z.+~:-]+$/) { print "error: not a source package: " $0 > "/dev/stderr"; bad = 1; next }
      if (src in lname) {
        nm = lname[src]; v = ver; sub(/^[0-9]+:/, "", v)
        if (v == lver[nm] || (length(v) > length(lver[nm]) && substr(v, length(v) - length(lver[nm])) == "-" lver[nm])) {
          print src "\t" ver "\t" lpath[nm] "\t" lurl[nm] "\t" lhash[nm] "\t-"; next
        }
        if (!(src in kind)) {
          print "error: " src " " ver " is not the version whose source bsp.conf pins (" nm "_VERSION " lver[nm] ")" > "/dev/stderr"; bad = 1; next
        }
      }
      if (!(src in kind)) { print src "\t" ver > archive; next }
      if (kind[src] == "none") { print src "\t" ver "\t-\t-\t-\t" val[src]; next }
      if (kind[src] == "initrd") {
        print src "\t" ver "\t-\t-\t-\tits initrd'"'"'s Ubuntu programs: their source packages are listed here (" val[src] "); its own files are NVIDIA'"'"'s"; next
      }
      if (kind[src] == "open") {
        if (allow_open == "1") {
          print "warning: the source of " src " " ver " is open (release/sources): " val[src] > "/dev/stderr"
          print src "\t" ver "\t-\t-\t-\tOPEN: " val[src]; next
        }
        print "error: the source of " src " " ver " is open (release/sources): " val[src] > "/dev/stderr"; bad = 1; next
      }
      up = ver; sub(/^[0-9]+:/, "", up); sub(/-[^-]*$/, "", up)
      url = val[src]; gsub(/\{upstream\}/, up, url)
      print src "\t" ver "\tupstream/" src "/" src "_" up ".tar.gz\t" url "\t-\t-"
    }
    END { exit bad }' "$RULES" "$list"

  [ -s "$tmp/archive.tsv" ] || return 0
  require docker curl jq
  load_conf "$here/builder.conf"
  log "resolving $(wc -l <"$tmp/archive.tsv" | tr -d ' ') source packages with apt in $BUILDER_IMAGE"
  docker run --rm -i \
    -v "$repo:/src:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    "$BUILDER_IMAGE" \
    bash /src/build/sources.sh resolve "$distro" <"$tmp/archive.tsv" >"$tmp/resolved.tsv"
  if [ "$distro" = debian-trixie ]; then
    awk -v debian="$DISTRO_MIRROR/" -v security="$DISTRO_SECURITY_MIRROR/" -v rpi="$RPI_MIRROR/" -v missing="$tmp/missing.tsv" '
      BEGIN { FS = OFS = "\t"; printf "" > missing }
      $3 == "-" { print $1, $2 > missing; next }
      {
        if (index($3, debian) == 1 || index($3, security) == 1) a = "debian"
        else if (index($3, rpi) == 1) a = "raspberrypi"
        else { print "error: " $1 " " $2 ": a file from an unknown archive: " $3 > "/dev/stderr"; bad = 1; next }
        print $1, $2, a "/" $1 "/" $4, $3, $6, "-"
      }
      END { exit bad }' "$tmp/resolved.tsv"
  else
    awk -v ubuntu="$DISTRO_SOURCE_MIRROR/" -v security="$DISTRO_SOURCE_SECURITY_MIRROR/" -v missing="$tmp/missing.tsv" '
      BEGIN { FS = OFS = "\t"; printf "" > missing }
      $3 == "-" { print $1, $2 > missing; next }
      {
        if (index($3, ubuntu) == 1 || index($3, security) == 1) a = "ubuntu"
        else { print "error: " $1 " " $2 ": a file from an unknown archive: " $3 > "/dev/stderr"; bad = 1; next }
        print $1, $2, a "/" $1 "/" $4, $3, $6, "-"
      }
      END { exit bad }' "$tmp/resolved.tsv"
  fi
  while IFS=$'\t' read -r src ver; do
    if ! "$fallback" "$src" "$ver"; then
      missing+=("$src $ver")
    fi
  done <"$tmp/missing.tsv"
  [ "${#missing[@]}" -eq 0 ] && return 0
  if [ "$distro" = debian-trixie ]; then
    die "no source for: $(join_by ', ' "${missing[@]}"). A source package outside Debian and the Raspberry Pi archive needs a line in release/sources."
  fi
  die "no source for: $(join_by ', ' "${missing[@]}"). A source package outside Ubuntu's archive needs a line in release/sources."
}

# resolve: in the build container, the files of each source package of
# stdin's list as apt finds them ("<source> <version> <URL> <file> <size>
# <hash>"), or "<source> <version> -" when apt does not know it.
resolve() {
  if [ ! -f /etc/debian_version ] || ! command -v apt-get >/dev/null; then
    die "resolve runs in the build container (sources.sh plan)"
  fi
  local distro=${1:-debian-trixie} rpi src ver out
  case "$distro" in
    debian-trixie | ubuntu-noble) load_conf "$repo/distros/$distro/versions" ;;
    *) die "resolve: no source archive known for $distro" ;;
  esac
  # The Raspberry Pi archive is https: the certificates first, from the
  # image's own sources; Ubuntu's archive key for Ubuntu's.
  apt-get -qq -o Acquire::Retries=5 update >&2
  if [ "$distro" = debian-trixie ]; then
    apt-get -qq -y -o Acquire::Retries=5 install --no-install-recommends ca-certificates >/dev/null
  else
    apt-get -qq -y -o Acquire::Retries=5 install --no-install-recommends ca-certificates ubuntu-keyring >/dev/null
  fi
  # Then only the source indexes (the image's own entries name the keyring
  # by another path, which apt refuses for the same archive).
  rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
  if [ "$distro" = debian-trixie ]; then
    rpi=$(sed -n 's/^RPI_MIRROR=//p' "$repo/targets/rpi-arm64/target.conf")
    {
      printf 'Types: deb-src\nURIs: %s\nSuites: %s %s-updates\nComponents: %s\nSigned-By: %s\n\n' \
        "$DISTRO_MIRROR" "$DISTRO_SUITE" "$DISTRO_SUITE" "$DISTRO_COMPONENTS" "$DISTRO_KEYRING"
      printf 'Types: deb-src\nURIs: %s\nSuites: %s-security\nComponents: %s\nSigned-By: %s\n\n' \
        "$DISTRO_SECURITY_MIRROR" "$DISTRO_SUITE" "$DISTRO_COMPONENTS" "$DISTRO_KEYRING"
      printf 'Types: deb-src\nURIs: %s\nSuites: %s\nComponents: main\nSigned-By:\n' "$rpi" "$DISTRO_SUITE"
      sed -e 's/^$/./' -e 's/^/ /' "$repo/targets/rpi-arm64/apt/raspberrypi.asc"
    } >/etc/apt/sources.list.d/ironflockos-sources.sources
  else
    # Ubuntu's source packages are in its primary and security archives
    # (the ports archive the image installs from has the same), their
    # indexes signed with Ubuntu's archive key.
    {
      printf 'Types: deb-src\nURIs: %s\nSuites: %s %s-updates\nComponents: %s\nSigned-By: %s\n\n' \
        "$DISTRO_SOURCE_MIRROR" "$DISTRO_SUITE" "$DISTRO_SUITE" "$DISTRO_COMPONENTS" "$DISTRO_KEYRING"
      printf 'Types: deb-src\nURIs: %s\nSuites: %s-security\nComponents: %s\nSigned-By: %s\n' \
        "$DISTRO_SOURCE_SECURITY_MIRROR" "$DISTRO_SUITE" "$DISTRO_COMPONENTS" "$DISTRO_KEYRING"
    } >/etc/apt/sources.list.d/ironflockos-sources.sources
  fi
  apt-get -qq -o Acquire::Retries=5 update >&2
  # apt leaves out a file it finds in the current directory.
  cd "$(mktemp -d)"
  while IFS=$'\t' read -r src ver; do
    if out=$(apt-get source --print-uris --only-source "$src=$ver" 2>/dev/null); then
      # 'URL' file size hash
      while read -r url file size hash; do
        case "$url" in
          \'*\') printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$src" "$ver" "${url:1:${#url}-2}" "$file" "$size" "$hash" ;;
        esac
      done <<<"$out"
    else
      printf '%s\t%s\t-\n' "$src" "$ver"
    fi
  done
}

index() {
  local plan=$1 version=$2
  [ -s "$plan" ] || die "$plan is an empty plan"
  load_conf "$here/release.conf"
  cat <<HEADER
# IronFlockOS $version: the source code of the software in its images.
#
# An image is a collection of separate programs, each under its own licence,
# which /usr/share/doc/<package>/copyright in the image names; the
# <image>.packages.tsv next to this file lists the packages of an image.
# Below is every file of every source package the images were built from,
# on this server; "dget <URL of a .dsc>" fetches a Debian source package
# with all its files. A source package with "-" as its URL has no source
# here, for the reason after it: none of them is under a copyleft licence.
#
# IronFlockOS's own files are https://github.com/IronFlock/ironflockos at the tag
# v$version, under the Apache License 2.0.
#
# source	version	URL or -	reason
HEADER
  awk -F'\t' -v base="$DL_BASE/ironflockos/sources/" '
    $3 == "-" { print $1 "\t" $2 "\t-\t" $6; next }
    { print $1 "\t" $2 "\t" base $3 }' "$plan" | LC_ALL=C sort -u
}

cmd=${1:-}
case "$cmd" in
  image) image ;;
  plan) plan "${2:?usage: sources.sh plan LIST [DISTRO]}" "${3:-}" ;;
  index) index "${2:?usage: sources.sh index PLAN VERSION}" "${3:?usage: sources.sh index PLAN VERSION}" ;;
  resolve) resolve "${2:-}" ;;
  *) die "usage: sources.sh image|plan|index|resolve ..." ;;
esac
