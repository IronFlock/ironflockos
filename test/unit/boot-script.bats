#!/usr/bin/env bats
# ironflockos-boot-script (ADR-0022): the boot script and its loader on the
# IRONFLOCKOS partition, with fakes for grub-editenv (a plain KEY=VALUE file),
# grub-script-check and sync, a tree that stands for the partition and the
# slot's /usr/lib/ironflockos/boot. And the loader and the script themselves,
# as far as they can be checked without GRUB.

repo="$BATS_TEST_DIRNAME/../.."
tool="$repo/overlay/usr/lib/ironflockos/boot-script"
fixture="$repo/test/qemu/fixtures/grub-0.17.0.cfg"

setup() {
  tmp=$(mktemp -d)
  esp=$tmp/esp
  boot=$esp/EFI/BOOT
  mkdir -p "$boot" "$esp/EFI/debian" "$tmp/files" "$tmp/run" "$tmp/bin" "$tmp/var"
  # grub-editenv FILE list | set KEY=VALUE..., on a plain KEY=VALUE file.
  cat >"$tmp/bin/grub-editenv" <<'SH'
#!/bin/bash
f=$1
cmd=$2
shift 2
[ -z "${FAKE_EDITENV_FAIL:-}" ] || [ "$cmd" = list ] || exit 1
case "$cmd" in
  list) cat "$f" ;;
  set)
    for kv in "$@"; do
      grep -v "^${kv%%=*}=" "$f" >"$f.new" || true
      echo "$kv" >>"$f.new"
      mv "$f.new" "$f"
    done
    ;;
esac
SH
  printf '#!/bin/sh\n[ -z "${FAKE_SCRIPT_CHECK_FAIL:-}" ]\n' >"$tmp/bin/grub-script-check"
  printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/sync"
  chmod +x "$tmp/bin/"*
  export PATH="$tmp/bin:$PATH"
  export IRONFLOCKOS_ESP=$esp IRONFLOCKOS_BOOT_FILES=$tmp/files IRONFLOCKOS_PROC_CMDLINE=$tmp/cmdline
  export IRONFLOCKOS_SLOT_PROVEN=$tmp/var/slot-proven IRONFLOCKOS_RUN=$tmp/run
  # A device on slot A, proven and marked good in this boot, booted by
  # boot script 2; the slot carries script 2 and loader 1, and the
  # partition has them.
  script 2 >"$tmp/files/boot.cfg"
  loader 1 >"$tmp/files/loader.cfg"
  cp "$tmp/files/loader.cfg" "$boot/grub.cfg"
  cp "$tmp/files/loader.cfg" "$esp/EFI/debian/grub.cfg"
  cp "$tmp/files/boot.cfg" "$boot/boot.cfg"
  printf 'ORDER=A B\nA_OK=1\nA_TRY=0\nB_OK=1\nB_TRY=0\nIRONFLOCKOS_CMDLINE=\n' >"$boot/grubenv"
  cmdline A 2
  : >"$tmp/var/slot-proven"
}
teardown() { rm -rf "$tmp"; }

# script N [LINE]: a whole boot script of version N.
script() {
  printf '# ironflockos-boot-script-version: %s\nmenuentry "IronFlockOS slot ${slot}" {\n    linux /vmlinuz rauc.slot=${slot} ironflockos.boot_script=%s %s\n}\n# end of the IronFlockOS boot script\n' "$1" "$1" "${2:-}"
}
loader() { printf '# ironflockos-boot-loader-version: %s\nsource ${prefix}/boot.cfg\n# end of the IronFlockOS boot loader\n' "$1"; }
# cmdline SLOT SCRIPT: this boot's kernel command line ("" SCRIPT: none named).
cmdline() {
  if [ -n "$2" ]; then
    echo "rw rootwait root=PARTUUID=x rauc.slot=$1 ironflockos.boot_script=$2 console=tty0" >"$tmp/cmdline"
  else
    echo "rw rootwait root=PARTUUID=x rauc.slot=$1 console=tty0" >"$tmp/cmdline"
  fi
}
env_of() { sed -n "s/^$1=//p" "$boot/grubenv"; }
set_env() { "$tmp/bin/grub-editenv" "$boot/grubenv" set "$@"; }
# legacy: the partition as 0.17.0 wrote it: the whole script as grub.cfg,
# EFI/debian/grub.cfg sourcing it, no boot.cfg.
legacy() {
  # shellcheck source=build/lib.sh
  . "$repo/build/lib.sh"
  (load_conf "$repo/targets/amd64-efi/target.conf" && render "$fixture") >"$boot/grub.cfg"
  printf '# IronFlockOS: the A/B script is in /EFI/BOOT, next to the boot loader. Debian'"'"'s\n# GRUB reads it there first; this file is for a GRUB that reads only its\n# prefix, /EFI/debian.\nsource ($root)/EFI/BOOT/grub.cfg\n' >"$esp/EFI/debian/grub.cfg"
  rm -f "$boot/boot.cfg"
  cp "$boot/grub.cfg" "$tmp/legacy.cfg"
  cmdline A ""
}
no_leftovers() { [ -z "$(find "$esp" -name '.*' -type f)" ]; }
run_tool() { run sh "$tool" "$@"; }

@test "usage: a mode is required" {
  run_tool
  [ "$status" -eq 2 ]
  run_tool frobnicate
  [ "$status" -eq 2 ]
}

@test "without the partition's EFI/BOOT or grubenv, or without the slot's files, nothing is done" {
  rm "$boot/grubenv"
  run_tool kept
  [ "$status" -eq 0 ] && [ -z "$output" ]
  echo 'ORDER=A B' >"$boot/grubenv"
  rm "$tmp/files/boot.cfg"
  run_tool kept
  [ "$status" -eq 0 ] && [[ "$output" == *"this slot has no boot script"* ]]
  script 3 | head -n 3 >"$tmp/files/boot.cfg"
  run_tool kept
  [ "$status" -eq 0 ] && [[ "$output" == *"not whole"* ]]
  cmp "$boot/boot.cfg" <(script 2)
}

@test "a device whose partition has the slot's scripts: nothing to do, and the status says what it has" {
  before=$(cd "$esp" && find . -type f -exec cksum {} +)
  for mode in boot proven kept; do
    run_tool "$mode"
    [ "$status" -eq 0 ] && [ -z "$output" ]
  done
  [ "$(cd "$esp" && find . -type f -exec cksum {} +)" = "$before" ]
  grep -qx booted=2 "$tmp/run/boot-script"
  grep -qx installed=2 "$tmp/run/boot-script"
  grep -qx slot=2 "$tmp/run/boot-script"
  grep -qx loader=1 "$tmp/run/boot-script"
  grep -qx trial= "$tmp/run/boot-script"
}

# --- the change-over of a device installed with 0.17.0 --------------------------

@test "change-over: 0.17.0's grub.cfg becomes boot.cfg byte for byte, the loader comes to both paths, and the slot's script is staged" {
  legacy
  run_tool proven
  [ "$status" -eq 0 ]
  cmp "$boot/boot.cfg" "$tmp/legacy.cfg"
  cmp "$boot/grub.cfg" "$tmp/files/loader.cfg"
  cmp "$esp/EFI/debian/grub.cfg" "$tmp/files/loader.cfg"
  cmp "$boot/boot-next.cfg" "$tmp/files/boot.cfg"
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = staged ] && [ "$(env_of IRONFLOCKOS_SCRIPT_SLOT)" = A ]
  [[ "$output" == *"changed over"* ]] && [[ "$output" == *"boot script 2 staged"* ]]
  grep -qx installed=1 "$tmp/run/boot-script"
  no_leftovers
}

@test "change-over: the order keeps a path GRUB boots at every step: the second path first, then the rename, then grub.cfg" {
  legacy
  # Each rename the tool makes, with what GRUB's two paths hold after it.
  cat >"$tmp/bin/mv" <<SH
#!/bin/bash
/bin/mv "\$@" || exit
dest=\${!#}
first=\$([ -e "$boot/grub.cfg" ] && head -n 1 "$boot/grub.cfg" | cut -c1-30 || echo missing)
second=\$(head -n 1 "$esp/EFI/debian/grub.cfg" | cut -c1-30)
echo "\${dest#$esp/} | first: \$first | second: \$second" >>"$tmp/mv.log"
SH
  chmod +x "$tmp/bin/mv"
  run_tool proven
  [ "$status" -eq 0 ]
  cat "$tmp/mv.log"
  # 1. the loader to the second path while grub.cfg is 0.17.0's script
  sed -n 1p "$tmp/mv.log" | grep -q '^EFI/debian/grub.cfg | first: # IronFlockOS boot script.* | second: # ironflockos-boot-loader'
  # 2. grub.cfg to boot.cfg: GRUB now reads the second path, a loader
  sed -n 2p "$tmp/mv.log" | grep -q '^EFI/BOOT/boot.cfg | first: missing | second: # ironflockos-boot-loader'
  # 3. the loader to grub.cfg, under a name that was free
  sed -n 3p "$tmp/mv.log" | grep -q '^EFI/BOOT/grub.cfg | first: # ironflockos-boot-loader'
  [ "$(grep -c '\.cfg |' "$tmp/mv.log")" -eq 4 ] # and boot-next.cfg, staged
}

@test "change-over: only once the slot is proven, GRUB's first choice and good in this boot, and not after an update was installed" {
  legacy
  run_tool boot
  cmp "$boot/grub.cfg" "$tmp/legacy.cfg" && [ ! -e "$boot/boot.cfg" ]
  rm "$tmp/var/slot-proven"
  run_tool kept
  cmp "$boot/grub.cfg" "$tmp/legacy.cfg"
  : >"$tmp/var/slot-proven"
  set_env A_TRY=1
  run_tool kept
  cmp "$boot/grub.cfg" "$tmp/legacy.cfg"
  set_env A_TRY=0 "ORDER=B A"
  run_tool kept
  cmp "$boot/grub.cfg" "$tmp/legacy.cfg"
  set_env "ORDER=A B"
  : >"$tmp/run/boot-script.hold"
  run_tool kept
  cmp "$boot/grub.cfg" "$tmp/legacy.cfg"
  grep -q 'source (\$root)/EFI/BOOT/grub.cfg' "$esp/EFI/debian/grub.cfg"
  rm "$tmp/run/boot-script.hold"
  run_tool kept
  cmp "$boot/boot.cfg" "$tmp/legacy.cfg"
}

@test "change-over: refused on a partition IronFlockOS did not lay out so (before ADR-0011, another second path, not its script)" {
  legacy
  rm "$esp/EFI/debian/grub.cfg"
  run_tool proven
  cmp "$boot/grub.cfg" "$tmp/legacy.cfg" && [ ! -e "$boot/boot.cfg" ]
  grep -q '^result=not changed over: no EFI/debian/grub.cfg' "$tmp/run/boot-script"
  echo 'configfile /somewhere/else.cfg' >"$esp/EFI/debian/grub.cfg"
  run_tool proven
  cmp "$boot/grub.cfg" "$tmp/legacy.cfg"
  grep -q '^result=not changed over: EFI/debian/grub.cfg is not the one IronFlockOS wrote' "$tmp/run/boot-script"
  legacy
  echo 'set timeout=5' >"$boot/grub.cfg"
  run_tool proven
  [ "$(cat "$boot/grub.cfg")" = 'set timeout=5' ]
  grep -q '^result=not changed over: grub.cfg is not an IronFlockOS boot script' "$tmp/run/boot-script"
}

@test "change-over with an emptied EFI/debian/grub.cfg: GRUB reads grub.cfg meanwhile, so it goes ahead" {
  legacy
  : >"$esp/EFI/debian/grub.cfg"
  run_tool proven
  cmp "$boot/boot.cfg" "$tmp/legacy.cfg"
  cmp "$esp/EFI/debian/grub.cfg" "$tmp/files/loader.cfg"
}

@test "change-over cut after the second path: it goes on from there" {
  legacy
  cp "$tmp/files/loader.cfg" "$esp/EFI/debian/grub.cfg"
  run_tool proven
  cmp "$boot/boot.cfg" "$tmp/legacy.cfg"
  cmp "$boot/grub.cfg" "$tmp/files/loader.cfg"
}

@test "change-over cut after the rename: at the next boot grub.cfg is the loader again, from the second path" {
  legacy
  cp "$tmp/files/loader.cfg" "$esp/EFI/debian/grub.cfg"
  mv "$boot/grub.cfg" "$boot/boot.cfg"
  run_tool boot
  [ "$status" -eq 0 ]
  cmp "$boot/grub.cfg" "$tmp/files/loader.cfg"
  cmp "$boot/boot.cfg" "$tmp/legacy.cfg"
  [[ "$output" == *"grub.cfg was missing: the loader again, from EFI/debian/grub.cfg"* ]]
  no_leftovers
}

@test "change-over cut in the rename, both names left and fsck truncated the boot.cfg: changed over again" {
  legacy
  cp "$tmp/files/loader.cfg" "$esp/EFI/debian/grub.cfg"
  : >"$boot/boot.cfg"
  run_tool proven
  cmp "$boot/boot.cfg" "$tmp/legacy.cfg"
  cmp "$boot/grub.cfg" "$tmp/files/loader.cfg"
  no_leftovers
}

# --- the loader at both paths ---------------------------------------------------

@test "a grub.cfg fsck emptied or a power cut cut short is the loader again at the next boot, from the second path" {
  : >"$boot/grub.cfg"
  run_tool boot
  cmp "$boot/grub.cfg" "$esp/EFI/debian/grub.cfg"
  loader 1 | head -n 2 >"$boot/grub.cfg"
  run_tool boot
  cmp "$boot/grub.cfg" "$tmp/files/loader.cfg"
  no_leftovers
}

@test "a second path that is not the loader becomes a copy of grub.cfg" {
  : >"$esp/EFI/debian/grub.cfg"
  run_tool boot
  cmp "$esp/EFI/debian/grub.cfg" "$boot/grub.cfg"
  rm "$esp/EFI/debian/grub.cfg"
  run_tool boot
  cmp "$esp/EFI/debian/grub.cfg" "$boot/grub.cfg"
}

@test "neither path a loader: both from the slot, and the slot's script when boot.cfg is gone" {
  rm "$boot/grub.cfg" "$boot/boot.cfg"
  echo 'source ($root)/EFI/BOOT/grub.cfg' >"$esp/EFI/debian/grub.cfg"
  run_tool boot
  cmp "$boot/grub.cfg" "$tmp/files/loader.cfg"
  cmp "$esp/EFI/debian/grub.cfg" "$tmp/files/loader.cfg"
  cmp "$boot/boot.cfg" "$tmp/files/boot.cfg"
}

@test "a newer loader of the slot's: the second path first, then grub.cfg; never an older one" {
  loader 2 >"$tmp/files/loader.cfg"
  run_tool boot
  [ "$(head -n 1 "$boot/grub.cfg")" = "# ironflockos-boot-loader-version: 1" ]
  run_tool proven
  cmp "$boot/grub.cfg" "$tmp/files/loader.cfg"
  cmp "$esp/EFI/debian/grub.cfg" "$tmp/files/loader.cfg"
  loader 1 >"$tmp/files/loader.cfg"
  run_tool proven
  [ "$(head -n 1 "$boot/grub.cfg")" = "# ironflockos-boot-loader-version: 2" ]
}

@test "a renewal cut after the second path is finished at the next boot" {
  loader 2 >"$esp/EFI/debian/grub.cfg"
  run_tool boot
  cmp "$boot/grub.cfg" "$esp/EFI/debian/grub.cfg"
  [ "$(head -n 1 "$boot/grub.cfg")" = "# ironflockos-boot-loader-version: 2" ]
}

# --- staging --------------------------------------------------------------------

@test "a newer script of the slot's is staged for its first trial, through a temporary name" {
  script 3 >"$tmp/files/boot.cfg"
  run_tool proven
  [ "$status" -eq 0 ]
  cmp "$boot/boot-next.cfg" "$tmp/files/boot.cfg"
  cmp "$boot/boot.cfg" <(script 2)
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = staged ] && [ "$(env_of IRONFLOCKOS_SCRIPT_SLOT)" = A ]
  [[ "$output" == *"boot script 3 staged: the next boot tries it, trial 1 of 2 (in use: 2)"* ]]
  grep -qx trial=staged "$tmp/run/boot-script" && grep -qx trial-version=3 "$tmp/run/boot-script"
  no_leftovers
  # Staged once: the next runs change nothing.
  run_tool kept
  [ -z "$output" ]
}

@test "staging: never at the boot's start, never an older or the same version, never while a trial is open" {
  script 3 >"$tmp/files/boot.cfg"
  run_tool boot
  [ ! -e "$boot/boot-next.cfg" ]
  script 1 >"$tmp/files/boot.cfg"
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  script 2 >"$tmp/files/boot.cfg"
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  # This boot is a trial's: the slot's newer script waits.
  script 4 >"$tmp/files/boot.cfg"
  script 3 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=tried IRONFLOCKOS_SCRIPT_SLOT=A
  cmdline A 3
  run_tool proven
  cmp "$boot/boot-next.cfg" <(script 3)
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = tried ]
}

@test "staging needs the slot proven, GRUB's first choice, good in this boot, no update installed" {
  script 3 >"$tmp/files/boot.cfg"
  rm "$tmp/var/slot-proven"
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  : >"$tmp/var/slot-proven"
  set_env "ORDER=B A"
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  set_env "ORDER=A B" A_TRY=1
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  set_env A_TRY=0 A_OK=0
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  set_env A_OK=1
  : >"$tmp/run/boot-script.hold"
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  rm "$tmp/run/boot-script.hold"
  run_tool kept
  [ -e "$boot/boot-next.cfg" ]
}

@test "a version that failed its trial is not staged again; a higher one is" {
  set_env IRONFLOCKOS_SCRIPT_FAILED=3
  script 3 >"$tmp/files/boot.cfg"
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  grep -qx 'result=boot script 3 is not staged: 3 failed its trial' "$tmp/run/boot-script"
  script 4 >"$tmp/files/boot.cfg"
  run_tool kept
  cmp "$boot/boot-next.cfg" "$tmp/files/boot.cfg"
}

@test "a script grub-script-check refuses is not staged" {
  script 3 >"$tmp/files/boot.cfg"
  FAKE_SCRIPT_CHECK_FAIL=1 run_tool kept
  [ ! -e "$boot/boot-next.cfg" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ]
  [[ "$output" == *"fails grub-script-check: not staged"* ]]
}

@test "a system the loader's last resort booted, or a boot.cfg that is not whole: the slot's script is staged, even of the same version" {
  cmdline A 0
  run_tool kept
  cmp "$boot/boot-next.cfg" "$tmp/files/boot.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL= IRONFLOCKOS_SCRIPT_SLOT=
  rm "$boot/boot-next.cfg"
  cmdline A 2
  script 2 | head -n 3 >"$boot/boot.cfg"
  run_tool kept
  cmp "$boot/boot-next.cfg" "$tmp/files/boot.cfg"
}

@test "grubenv that cannot be written: nothing is staged, the run fails soft" {
  script 3 >"$tmp/files/boot.cfg"
  FAKE_EDITENV_FAIL=1 run_tool kept
  [ "$status" -eq 0 ]
  [ ! -e "$boot/boot-next.cfg" ]
  [[ "$output" == *"could not write grubenv"* ]]
}

# --- the trial ------------------------------------------------------------------

stage3() {
  script 3 >"$tmp/files/boot.cfg"
  script 3 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=tried IRONFLOCKOS_SCRIPT_SLOT=A A_TRY=1
  cmdline A 3
}

@test "the trial's boot waits for the slot's two minutes: nothing at the start or at the agent's mark" {
  stage3
  set_env A_TRY=0
  run_tool boot
  run_tool proven
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = tried ] && [ -e "$boot/boot-next.cfg" ]
  cmp "$boot/boot.cfg" <(script 2)
}

@test "confirmed by ironflockos-slot-keep's proof: boot-next.cfg becomes boot.cfg, the trial ends" {
  stage3
  set_env A_TRY=0
  run_tool kept
  [ "$status" -eq 0 ]
  cmp "$boot/boot.cfg" <(script 3)
  [ ! -e "$boot/boot-next.cfg" ]
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_SLOT)" = "" ]
  [[ "$output" == *"boot script 3 is in use"* ]]
  grep -qx installed=3 "$tmp/run/boot-script"
  no_leftovers
}

@test "not confirmed while the slot is not good in this boot (RAUC's mark-good did not come through)" {
  stage3
  run_tool kept
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = tried ]
  cmp "$boot/boot.cfg" <(script 2)
}

# A trial of version 3 that the loader found unconfirmed at the boot after it.
unconfirmed3() {
  stage3
  set_env IRONFLOCKOS_SCRIPT_TRIAL=failed A_TRY=1
  cmdline A 2
}

@test "a first trial the loader found unconfirmed: counted once, boot-next.cfg goes, the slot's flags stay as GRUB left them" {
  unconfirmed3
  run_tool boot
  [ "$status" -eq 0 ]
  [ ! -e "$boot/boot-next.cfg" ]
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = 3 ]
  [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = "" ]
  [ "$(env_of A_TRY)" = 1 ]
  cmp "$boot/boot.cfg" <(script 2)
  [[ "$output" == *"the trial of boot script 3 was not confirmed (its boot was not confirmed): first trial not confirmed, one more; boot script 2 stays in use"* ]]
  grep -qx 'trials=1 of 2' "$tmp/run/boot-script" && grep -qx unconfirmed=3 "$tmp/run/boot-script"
  grep -qx trials-of=3 "$tmp/run/boot-script"
  grep -q '^result=the trial of boot script 3 was not confirmed' "$tmp/run/boot-script"
  # Not staged again in this boot's first run, nor before the slot is good in this boot.
  [ ! -e "$boot/boot-next.cfg" ]
  run_tool proven
  [ ! -e "$boot/boot-next.cfg" ]
  grep -q '^result=the trial of boot script 3 was not confirmed' "$tmp/run/boot-script"
}

@test "the retry: staged again by the same rules, and the second unconfirmed trial is the failure for good" {
  unconfirmed3
  run_tool boot
  set_env A_TRY=0
  run_tool kept
  cmp "$boot/boot-next.cfg" <(script 3)
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = staged ] && [ "$(env_of IRONFLOCKOS_SCRIPT_SLOT)" = A ]
  [[ "$output" == *"boot script 3 staged: the next boot tries it, trial 2 of 2 (in use: 2)"* ]]
  grep -qx 'trials=1 of 2' "$tmp/run/boot-script"
  # The second trial's boot, unconfirmed again.
  set_env IRONFLOCKOS_SCRIPT_TRIAL=tried
  cmdline A 3
  run_tool boot
  grep -qx 'trials=2 of 2' "$tmp/run/boot-script"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=failed A_TRY=1
  cmdline A 2
  run_tool boot
  [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = 3 ] && [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = "" ]
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ] && [ ! -e "$boot/boot-next.cfg" ]
  [[ "$output" == *"the trial of boot script 3 was not confirmed again (its boot was not confirmed): failed for good; boot script 2 stays in use, 3 is not tried again"* ]]
  grep -qx failed=3 "$tmp/run/boot-script" && grep -qx 'trials=2 of 2' "$tmp/run/boot-script"
  # Not a third time; a higher version is.
  set_env A_TRY=0
  run_tool kept
  [ ! -e "$boot/boot-next.cfg" ]
  grep -qx 'result=boot script 3 is not staged: 3 failed its trial' "$tmp/run/boot-script"
  script 4 >"$tmp/files/boot.cfg"
  run_tool kept
  cmp "$boot/boot-next.cfg" <(script 4)
  grep -qx 'trials=0 of 2' "$tmp/run/boot-script"
}

@test "a higher version starts its own count; a confirmed second trial clears it" {
  unconfirmed3
  run_tool boot
  # Version 4 comes before 3 had its second trial: its unconfirmed trial is its first.
  script 4 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=failed IRONFLOCKOS_SCRIPT_SLOT=A
  run_tool boot
  [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = 4 ] && [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = "" ]
  # 4's second trial is confirmed: no count is left.
  script 4 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=tried IRONFLOCKOS_SCRIPT_SLOT=A A_TRY=0
  cmdline A 4
  run_tool kept
  cmp "$boot/boot.cfg" <(script 4)
  [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = "" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = "" ]
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ]
}

@test "a trial whose boot ran another script: failed; when its script booted the other slot, the trial's slot gets its try back" {
  stage3
  cmdline A 2
  run_tool boot
  [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = 3 ] && [ "$(env_of A_TRY)" = 1 ]
  stage3
  set_env IRONFLOCKOS_SCRIPT_UNCONFIRMED=
  cmdline B 3
  run_tool boot
  [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = 3 ] && [ "$(env_of A_TRY)" = 0 ]
  [[ "$output" == *"slot B booted with boot script 3"* ]]
}

@test "the highest failed version is kept" {
  stage3
  set_env IRONFLOCKOS_SCRIPT_FAILED=7 IRONFLOCKOS_SCRIPT_UNCONFIRMED=3 IRONFLOCKOS_SCRIPT_TRIAL=failed
  run_tool boot
  [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = 7 ]
}

@test "a confirmation cut short (good) is finished at the next boot" {
  stage3
  set_env IRONFLOCKOS_SCRIPT_TRIAL=good
  run_tool boot
  cmp "$boot/boot.cfg" <(script 3)
  [ ! -e "$boot/boot-next.cfg" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ]
  # good, and boot-next.cfg no longer whole: boot.cfg stays
  stage3
  set_env IRONFLOCKOS_SCRIPT_TRIAL=good
  script 4 | head -n 2 >"$boot/boot-next.cfg"
  run_tool boot
  cmp "$boot/boot.cfg" <(script 3)
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ] && [ ! -e "$boot/boot-next.cfg" ]
}

@test "a boot-next.cfg without a trial (a power cut between file and grubenv) goes; one staged by the other slot or not whole too" {
  script 3 >"$boot/boot-next.cfg"
  run_tool boot
  [ ! -e "$boot/boot-next.cfg" ]
  script 3 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=staged IRONFLOCKOS_SCRIPT_SLOT=B
  run_tool boot
  [ ! -e "$boot/boot-next.cfg" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ]
  script 3 | head -n 2 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=staged IRONFLOCKOS_SCRIPT_SLOT=A
  run_tool boot
  [ ! -e "$boot/boot-next.cfg" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ]
  set_env IRONFLOCKOS_SCRIPT_TRIAL=bogus
  run_tool boot
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ]
}

# --- an update installed --------------------------------------------------------

@test "cancel: an update installed while a script is staged or on trial cancels it, and nothing is staged until the next boot" {
  script 3 >"$tmp/files/boot.cfg"
  run_tool proven
  [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = staged ]
  run_tool cancel
  [ "$status" -eq 0 ]
  [ ! -e "$boot/boot-next.cfg" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_TRIAL)" = "" ]
  [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = "" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = "" ]
  [ -e "$tmp/run/boot-script.hold" ]
  [[ "$output" == *"an OS update was installed: the staged boot script 3 goes"* ]]
  run_tool proven
  [ ! -e "$boot/boot-next.cfg" ]
  stage3
  run_tool cancel
  [ ! -e "$boot/boot-next.cfg" ] && [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = "" ]
  [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = "" ]
  cmp "$boot/boot.cfg" <(script 2)
}

@test "cancel finishes a confirmed trial and counts a trial boot the loader found unconfirmed" {
  stage3
  set_env IRONFLOCKOS_SCRIPT_TRIAL=good
  run_tool cancel
  cmp "$boot/boot.cfg" <(script 3)
  script 4 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=failed IRONFLOCKOS_SCRIPT_SLOT=A
  run_tool cancel
  [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = 4 ] && [ ! -e "$boot/boot-next.cfg" ]
  script 4 >"$boot/boot-next.cfg"
  set_env IRONFLOCKOS_SCRIPT_TRIAL=failed IRONFLOCKOS_SCRIPT_SLOT=A
  run_tool cancel
  [ "$(env_of IRONFLOCKOS_SCRIPT_FAILED)" = 4 ] && [ "$(env_of IRONFLOCKOS_SCRIPT_UNCONFIRMED)" = "" ]
}

@test "rauc-post-install cancels after it wrote a root slot, and never fails for it" {
  pi=$repo/overlay/usr/lib/ironflockos/rauc-post-install
  grep -q 'boot_script_tool=${IRONFLOCKOS_BOOT_SCRIPT:-/usr/lib/ironflockos/boot-script}' "$pi"
  grep -q '"$boot_script_tool" cancel || echo "rauc-post-install: could not cancel a staged boot script" >&2' "$pi"
  # in the rootfs branch, after the slot is unmounted
  awk '/^    rootfs\)/ { r = 1 } /^    boot\)/ { r = 0 } r && /unmount_slot$/ { u = 1 } r && u && /boot_script_tool" cancel/ { ok = 1 } END { exit !ok }' "$pi"
}

# --- the units ------------------------------------------------------------------

@test "units: at every boot after the partition is mounted, at the slot's proof, at its two minutes; never a failed unit" {
  u=$repo/overlay/usr/lib/systemd/system
  grep -qx 'ExecStart=-/usr/lib/ironflockos/boot-script boot' "$u/ironflockos-boot-script.service"
  grep -qx 'After=boot-efi.mount' "$u/ironflockos-boot-script.service"
  grep -qx 'ConditionPathIsDirectory=/boot/efi/EFI/BOOT' "$u/ironflockos-boot-script.service"
  grep -qx 'WantedBy=multi-user.target' "$u/ironflockos-boot-script.service"
  grep -qx 'ExecStart=-/usr/lib/ironflockos/boot-script proven' "$u/ironflockos-slot-proven.service"
  # after the mark, in the unit with slot-keep's condition and timer
  [ "$(grep '^ExecStart=' "$u/ironflockos-slot-keep.service" | tr '\n' '|')" = 'ExecStart=-/usr/bin/rauc status mark-good|ExecStart=-/usr/lib/ironflockos/boot-script kept|' ]
  grep -qx 'ConditionPathExists=/var/lib/ironflockos/slot-proven' "$u/ironflockos-slot-keep.service"
  grep -q 'enable ironflockos-boot-script.service' "$repo/build/customize.sh"
}

# --- the loader and the script as files -----------------------------------------

@test "the loader and the script: version on the first line, the end mark on the last, the script's version on the command line" {
  . "$repo/build/lib.sh"
  for t in amd64-efi arm64-efi; do
    (
      load_conf "$repo/targets/$t/target.conf"
      render "$repo/targets/$t/grub/loader.cfg" >"$tmp/loader.cfg"
      render "$repo/targets/$t/grub/boot.cfg" >"$tmp/boot.cfg"
      head -n 1 "$tmp/loader.cfg" | grep -qx '# ironflockos-boot-loader-version: [0-9][0-9]*'
      tail -n 1 "$tmp/loader.cfg" | grep -qx '# end of the IronFlockOS boot loader'
      v=$(sed -n '1s/^# ironflockos-boot-script-version: \([0-9][0-9]*\)$/\1/p' "$tmp/boot.cfg")
      [ -n "$v" ]
      tail -n 1 "$tmp/boot.cfg" | grep -qx '# end of the IronFlockOS boot script'
      grep -q "^set BASE_CMDLINE=\".* ironflockos.boot_script=$v .*\"$" "$tmp/boot.cfg"
      [ "$(grep -o 'ironflockos\.boot_script=[0-9][0-9]*' "$tmp/boot.cfg" | sort -u)" = "ironflockos.boot_script=$v" ]
    )
  done
}

@test "the loader and the script name only modules built into Debian's signed GRUB" {
  # GRUB_MODULES of debian/build-efi-images in Debian's grub2 2.12 (trixie),
  # the modules of grub<arch>.efi.signed; under Secure Boot it loads no others.
  builtin=" all_video boot btrfs cat chain configfile echo efifwsetup efinet ext2 fat font f2fs gettext gfxmenu
    gfxterm gfxterm_background gzio halt help hfsplus iso9660 jfs jpeg keystatus loadenv loopback linux ls lsefi
    lsefimmap lsefisystab lssal memdisk minicmd normal ntfs part_apple part_msdos part_gpt password_pbkdf2 peimage
    png probe reboot regexp search search_fs_uuid search_fs_file search_label serial sleep smbios squash4 test tpm
    true video xfs zfs zfscrypt zfsinfo cryptodisk luks luks2 lvm "
  for f in loader.cfg boot.cfg; do
    for m in $(sed -n 's/^ *insmod \([a-z0-9_]*\)$/\1/p' "$repo/targets/amd64-efi/grub/$f"); do
      [[ "$builtin" == *" $m "* ]] || {
        echo "$f: $m is not built in"
        false
      }
    done
  done
}

@test "the loader writes only the trial's state and a slot's try flag, never more than grubenv holds" {
  l=$repo/targets/amd64-efi/grub/loader.cfg
  [ "$(grep -o 'save_env --file ${prefix}/grubenv [A-Z_ ]*' "$l" | sed 's/ *$//' | LC_ALL=C sort -u | tr '\n' '|')" = 'save_env --file ${prefix}/grubenv IRONFLOCKOS_SCRIPT_TRIAL|save_env --file ${prefix}/grubenv IRONFLOCKOS_SCRIPT_TRIAL A_TRY|save_env --file ${prefix}/grubenv IRONFLOCKOS_SCRIPT_TRIAL B_TRY|' ]
  # tried and failed are not longer than staged, the value they replace,
  # and a try flag keeps its length: save_env rewrites the block in place.
  for v in tried failed; do [ "${#v}" -le 6 ]; done
  # grubenv's 1024 bytes with every variable at a long value: RAUC's, the
  # display's, a long real-time tuning, the QEMU test's command line, and
  # the trial's.
  body="# GRUB Environment Block
ORDER=A B
A_OK=1
A_TRY=0
B_OK=1
B_TRY=0
IRONFLOCKOS_CMDLINE=systemd.debug_shell=ttyS1 ironflockos.boot=text systemd.mask=serial-getty@hvc0.service
IRONFLOCKOS_BOOT=splash
IRONFLOCKOS_RT_CMDLINE=nosoftlockup isolcpus=managed_irq,domain,2-7,10-15 nohz_full=2-7,10-15 rcu_nocbs=2-7,10-15 irqaffinity=0-1,8-9 processor.max_cstate=1 intel_idle.max_cstate=0
IRONFLOCKOS_SCRIPT_TRIAL=staged
IRONFLOCKOS_SCRIPT_SLOT=A
IRONFLOCKOS_SCRIPT_UNCONFIRMED=999
IRONFLOCKOS_SCRIPT_FAILED=999
"
  [ "${#body}" -lt 600 ]
}

@test "the loader's choices: the trial only when staged for GRUB's first slot, good and untried; boot.cfg otherwise; the last resort last" {
  l=$(grep -v '^ *#' "$repo/targets/amd64-efi/grub/loader.cfg")
  # The trial's conditions, and its try saved before the script runs.
  [[ "$l" == *'if [ "${IRONFLOCKOS_SCRIPT_TRIAL}" = staged ]; then'* ]]
  [[ "$l" == *'if [ "${ironflockos_first}" = A -a "${IRONFLOCKOS_SCRIPT_SLOT}" = A -a "${A_OK}" = 1 -a "${A_TRY}" = 0 ]; then'* ]]
  [[ "$l" == *'if [ "${ironflockos_first}" = B -a "${IRONFLOCKOS_SCRIPT_SLOT}" = B -a "${B_OK}" = 1 -a "${B_TRY}" = 0 ]; then'* ]]
  [[ "$l" == *$'set IRONFLOCKOS_SCRIPT_TRIAL=tried\n            if save_env --file ${prefix}/grubenv IRONFLOCKOS_SCRIPT_TRIAL; then\n                set ironflockos_trial=yes'* ]]
  # An unconfirmed trial at the next boot.
  [[ "$l" == *$'elif [ "${IRONFLOCKOS_SCRIPT_TRIAL}" = tried ]; then\n    ironflockos_trial_failed'* ]]
  # The trial's boot: two submenus, then the last resort, as fallbacks.
  [[ "$l" == *$'submenu "IronFlockOS, boot script on trial" --id ironflockos-next {\n        source ${prefix}/boot-next.cfg\n    }'* ]]
  [[ "$l" == *'set fallback="1 2 3"'* ]]
  # Otherwise boot.cfg as grub.cfg ran before, and the last resort when it set up nothing.
  [[ "$l" == *$'unset default\n    source ${prefix}/boot.cfg\n'* ]]
  [[ "$l" == *$'if [ -z "${default}" ]; then\n        set default=0\n        set fallback=1\n        set timeout=0'* ]]
  [ "$(grep -cE '^menuentry "IronFlockOS slot \$\{ironflockos_(one|two)\}, last resort"' "$repo/targets/amd64-efi/grub/loader.cfg")" = 2 ]
  # The last resort is on text, names itself as script 0 and keeps the test's parameters.
  [[ "$l" == *'set ironflockos_text="rw rootwait panic=10 fsck.repair=yes systemd.gpt_auto=0 ironflockos.boot_script=0 @CONSOLE_CMDLINE@ plymouth.enable=0 ${IRONFLOCKOS_CMDLINE}"'* ]]
}

@test "the loader, the script and 0.17.0's script pass grub-script-check (where GRUB's tools are installed)" {
  real=$(PATH=${PATH#"$tmp/bin:"} command -v grub-script-check || true)
  [ -n "$real" ] || skip "grub-script-check not installed (grub-common)"
  . "$repo/build/lib.sh"
  for t in amd64-efi arm64-efi; do
    (
      load_conf "$repo/targets/$t/target.conf"
      for f in "$repo/targets/$t/grub/loader.cfg" "$repo/targets/$t/grub/boot.cfg" "$fixture"; do
        render "$f" >"$tmp/check.cfg"
        "$real" "$tmp/check.cfg"
      done
    )
  done
}

@test "0.17.0's script, the QEMU test's change-over fixture, is the release's own" {
  head -n 1 "$fixture" | grep -qx "# IronFlockOS boot script: A/B slot selection for RAUC's grub backend, after"
  ! grep -q 'ironflockos.boot_script' "$fixture"
  if git -C "$repo" cat-file -e v0.17.0:targets/amd64-efi/grub/grub.cfg 2>/dev/null; then
    git -C "$repo" show v0.17.0:targets/amd64-efi/grub/grub.cfg | cmp - "$fixture"
  fi
}

@test "a factory reset leaves the trial counts in grubenv: it gives no version its tries back" {
  r=$repo/overlay/usr/lib/ironflockos/factory-reset
  [ "$(grep -o 'for var in [A-Z_ ]*' "$r")" = "for var in IRONFLOCKOS_RT_CMDLINE IRONFLOCKOS_BOOT" ]
  ! grep -q 'IRONFLOCKOS_SCRIPT' "$r"
}
