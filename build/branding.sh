#!/usr/bin/env bash
# The distribution's visible names in the tree become IronFlockOS's (docs/build.md,
# "Identity"; WP-6.8). The overlay brings /etc/issue and /etc/issue.net to
# every image. This handles the files only Ubuntu's base-files ships with
# Ubuntu's name in them; a Debian tree has none of them and stays as it is.
# The technical references stay: the release and codename in lsb-release,
# ID_LIKE in os-release, package names, version strings,
# /etc/dpkg/origins/ubuntu, the apt sources and the archive keyring.
# customize.sh masks motd-news.timer and motd-news.service.
#   branding.sh ROOT VERSION
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=build/lib.sh
. "$here/lib.sh"

[ "$#" -eq 2 ] || die "usage: branding.sh ROOT VERSION"
root=$1 version=$2
[ -d "$root/usr" ] || die "$root is not a root filesystem"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]] || die "not a version: $version"

# /etc/lsb-release (Ubuntu's base-files; Debian has none): IronFlockOS's
# DISTRIB_ID and DISTRIB_DESCRIPTION, the base named as "based on". Nothing in
# the image needs DISTRIB_ID=Ubuntu: lsb_release answers from os-release, and
# only NVIDIA's nvidia-bug-report-jetson.sh reads the ID, for an install hint.
lsb=$root/etc/lsb-release
if [ -f "$lsb" ]; then
  base_id=$(sed -n 's/^DISTRIB_ID=//p' "$lsb")
  release=$(sed -n 's/^DISTRIB_RELEASE=//p' "$lsb")
  [ -n "$base_id" ] && [ -n "$release" ] || die "$lsb names no DISTRIB_ID or DISTRIB_RELEASE"
  [ "$base_id" != IronFlockOS ] || die "$lsb is IronFlockOS's already"
  description="IronFlockOS $version, based on $base_id $release"
  lines=$(sed -e 's/^DISTRIB_ID=.*/DISTRIB_ID=IronFlockOS/' \
    -e "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION=\"$description\"/" "$lsb")
  printf '%s\n' "$lines" >"$lsb"
  grep -qx "DISTRIB_DESCRIPTION=\"$description\"" "$lsb" || die "$lsb has no DISTRIB_DESCRIPTION"
fi

# Ubuntu's notice, which pam_motd shows at a user's first login.
rm -f "$root/etc/legal"
# Ubuntu's login banner: the header, the help text with Canonical's links,
# and the news from motd.ubuntu.com with its settings (motd-news-config would
# bring those). The overlay's /etc/motd is the banner.
rm -f "$root/etc/update-motd.d/00-header" "$root/etc/update-motd.d/10-help-text" \
  "$root/etc/update-motd.d/50-motd-news" "$root/etc/default/motd-news"

# What a person sees at the login prompt and after it names no distribution.
for f in etc/issue etc/issue.net; do
  [ -f "$root/$f" ] || die "no /$f in the tree (overlay/$f)"
  ! grep -qiE 'ubuntu|debian' "$root/$f" || die "/$f names the distribution"
done
if [ -d "$root/etc/update-motd.d" ] && grep -rqiE 'ubuntu|canonical' "$root/etc/update-motd.d"; then
  die "a script in /etc/update-motd.d names Ubuntu or Canonical"
fi
