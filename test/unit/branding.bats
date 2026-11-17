#!/usr/bin/env bats
# What a person sees at the login prompt, after the login and in lsb-release
# names IronFlockOS, on every target (build/branding.sh, the overlay's
# /etc/issue; docs/build.md, "Identity"; WP-6.8). The Ubuntu files are
# shaped as base-files 13ubuntu10.5 ships them.

repo="$BATS_TEST_DIRNAME/../.."
branding="$repo/build/branding.sh"

setup() {
  tmp=$(mktemp -d)
  r=$tmp/root
  mkdir -p "$r/usr" "$r/etc/update-motd.d" "$r/etc/default" "$r/etc/dpkg/origins"
  cp "$repo/overlay/etc/issue" "$repo/overlay/etc/issue.net" "$r/etc/"
}

teardown() {
  rm -rf "$tmp"
}

# ubuntu_tree: the files of Ubuntu's base-files that carry Ubuntu's name.
ubuntu_tree() {
  printf 'DISTRIB_ID=Ubuntu\nDISTRIB_RELEASE=24.04\nDISTRIB_CODENAME=noble\nDISTRIB_DESCRIPTION="Ubuntu 24.04.5 LTS"\n' >"$r/etc/lsb-release"
  printf '\nThe programs included with the Ubuntu system are free software;\n' >"$r/etc/legal"
  printf '#!/bin/sh\nprintf "Welcome to %%s\\n" "$DISTRIB_DESCRIPTION"\n' >"$r/etc/update-motd.d/00-header"
  printf '#!/bin/sh\nprintf " * Documentation:  https://help.ubuntu.com\\n"\n' >"$r/etc/update-motd.d/10-help-text"
  printf '#!/bin/sh\n[ -n "$URLS" ] || URLS="https://motd.ubuntu.com"\n' >"$r/etc/update-motd.d/50-motd-news"
  printf 'ENABLED=1\nURLS="https://motd.ubuntu.com"\n' >"$r/etc/default/motd-news"
  printf 'Vendor: Ubuntu\nVendor-URL: https://www.ubuntu.com/\n' >"$r/etc/dpkg/origins/ubuntu"
}

@test "the overlay's login prompt names IronFlockOS through os-release, keeps the host and the terminal, and names no distribution" {
  # agetty's \S is PRETTY_NAME of /etc/os-release ("IronFlockOS 1.2.3 (jetson-orin, base)").
  [ "$(cat "$repo/overlay/etc/issue")" = '\S \n \l' ]
  [ "$(cat "$repo/overlay/etc/issue.net")" = IronFlockOS ]
  ! grep -qiE 'ubuntu|debian' "$repo/overlay/etc/issue" "$repo/overlay/etc/issue.net" "$repo/overlay/etc/motd"
}

@test "an Ubuntu tree: lsb-release names IronFlockOS based on Ubuntu, keeps release and codename; no legal notice, no Ubuntu banner, no motd-news" {
  ubuntu_tree
  printf '#!/bin/sh\nuname -snrvm\n' >"$r/etc/update-motd.d/10-uname"
  run bash "$branding" "$r" 1.2.3
  [ "$status" -eq 0 ]
  [ "$(cat "$r/etc/lsb-release")" = "$(printf 'DISTRIB_ID=IronFlockOS\nDISTRIB_RELEASE=24.04\nDISTRIB_CODENAME=noble\nDISTRIB_DESCRIPTION="IronFlockOS 1.2.3, based on Ubuntu 24.04"')" ]
  [ ! -e "$r/etc/legal" ]
  [ ! -e "$r/etc/update-motd.d/00-header" ]
  [ ! -e "$r/etc/update-motd.d/10-help-text" ]
  [ ! -e "$r/etc/update-motd.d/50-motd-news" ]
  [ ! -e "$r/etc/default/motd-news" ]
  [ -z "$(grep -rl 'motd.ubuntu.com' "$r/etc")" ]
  # Other banner scripts and the technical references stay.
  [ -f "$r/etc/update-motd.d/10-uname" ]
  grep -qx 'Vendor: Ubuntu' "$r/etc/dpkg/origins/ubuntu"
  [ "$(cat "$r/etc/issue")" = '\S \n \l' ]
}

@test "a Debian tree has none of Ubuntu's files and keeps its own banner script" {
  printf '#!/bin/sh\nuname -snrvm\n' >"$r/etc/update-motd.d/10-uname"
  run bash "$branding" "$r" 1.2.3
  [ "$status" -eq 0 ]
  [ ! -e "$r/etc/lsb-release" ]
  [ ! -e "$r/etc/legal" ]
  [ -f "$r/etc/update-motd.d/10-uname" ]
}

@test "refuses a tree whose prompt or banner still names the distribution, and what it cannot read" {
  ubuntu_tree
  printf 'Ubuntu 24.04.5 LTS \\n \\l\n\n' >"$r/etc/issue"
  run bash "$branding" "$r" 1.2.3
  [ "$status" -ne 0 ]
  [[ "$output" == *"/etc/issue names the distribution"* ]]

  # The tree is half done now: a second run refuses its lsb-release.
  run bash "$branding" "$r" 1.2.3
  [ "$status" -ne 0 ]
  [[ "$output" == *"is IronFlockOS's already"* ]]

  ubuntu_tree
  cp "$repo/overlay/etc/issue" "$r/etc/issue"
  rm "$r/etc/issue.net"
  run bash "$branding" "$r" 1.2.3
  [ "$status" -ne 0 ]
  [[ "$output" == *"no /etc/issue.net in the tree"* ]]

  cp "$repo/overlay/etc/issue.net" "$r/etc/issue.net"
  ubuntu_tree
  printf '#!/bin/sh\necho "Ubuntu Pro"\n' >"$r/etc/update-motd.d/88-esm-announce"
  run bash "$branding" "$r" 1.2.3
  [ "$status" -ne 0 ]
  [[ "$output" == *"/etc/update-motd.d names Ubuntu or Canonical"* ]]

  rm "$r/etc/update-motd.d/88-esm-announce"
  printf 'DISTRIB_CODENAME=noble\n' >"$r/etc/lsb-release"
  run bash "$branding" "$r" 1.2.3
  [ "$status" -ne 0 ]
  [[ "$output" == *"names no DISTRIB_ID or DISTRIB_RELEASE"* ]]

  ubuntu_tree
  run bash "$branding" "$r" 1.2
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a version"* ]]
  run bash "$branding" "$tmp/missing" 1.2.3
  [ "$status" -ne 0 ]
}

@test "customize.sh runs it after os-release and masks motd-news where Ubuntu's base-files brings it" {
  c=$repo/build/customize.sh
  osr=$(grep -n 'osrelease.sh' "$c" | head -n 1 | cut -d: -f1)
  b=$(grep -n 'bash "$here/branding.sh" "$ROOT" "$IRONFLOCKOS_VERSION"' "$c" | cut -d: -f1)
  [ -n "$osr" ]
  [ -n "$b" ]
  [ "$b" -gt "$osr" ]
  grep -q 'systemctl --root="$ROOT" mask motd-news.timer motd-news.service' "$c"
}
