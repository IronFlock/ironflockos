#!/usr/bin/env bats
# Jetson's boot firmware lane (WP-6.5): tegra-capsule against fake efivarfs
# files, a fake ESP and ESRT, NVIDIA's board specs in nv_boot_control.conf,
# and fake capsules that carry only the board specs NVIDIA's capsules carry
# (nothing in them is NVIDIA's); the RAUC backend with a staged capsule; and
# an update through a model of the firmware that applies or rejects the
# capsule as edk2-nvidia's capsule and boot chain code does.

repo="$BATS_TEST_DIRNAME/../.."
fixtures="$BATS_TEST_DIRNAME/fixtures/nvbootctrl"
lib="$repo/targets/jetson-orin/overlay/usr/lib/ironflockos"
tool="$lib/tegra-capsule"
backend="$lib/tegra-rootfs-ab"
trial_tool="$lib/tegra-slot-trial"
nvguid=781e084c-a330-417c-b678-38e696380cb9
gguid=8be4df61-93ca-11d2-aa0d-00e098032b8c
v3921=2556417 # 39.2.1 = 0x270201
v3920=2556416
v3930=2556672
v3910=2556160 # 39.1.0: another generation than 39.2.x
v3640=2360320 # 36.4.0
spec=3767--0003--1--jetson-orin-nano-devkit-
tnspec=3767-000-0003-G.0-1-1-jetson-orin-nano-devkit-nvme0n1p1

setup() {
  dir=$(mktemp -d)
  nv=$dir/nv
  efi=$nv/efivars
  mkdir -p "$efi" "$dir/bin" "$dir/esp/EFI/BOOT" "$dir/esrt/entries/entry0" "$dir/run"
  export FAKE_NV=$nv
  export IRONFLOCKOS_NVBOOTCTRL=$fixtures/fake-nvbootctrl
  export IRONFLOCKOS_EFIVARS=$efi
  export IRONFLOCKOS_ESRT=$dir/esrt
  export IRONFLOCKOS_ESP=$dir/esp
  export IRONFLOCKOS_ESP_FREE_KB=60000
  export IRONFLOCKOS_BOOT_CTRL_CONF=$dir/nv_boot_control.conf
  export IRONFLOCKOS_MAINTENANCE_CONF=$dir/maintenance.conf
  export IRONFLOCKOS_TEGRA_AB_STATE=$dir/data/rauc/state
  export IRONFLOCKOS_BOOT_ID=$dir/boot_id
  export IRONFLOCKOS_RUN=$dir/run
  export IRONFLOCKOS_PROC_CMDLINE=$dir/cmdline
  export IRONFLOCKOS_NOW=1800000000
  export IRONFLOCKOS_TEGRA_CAPSULE=$tool
  export IRONFLOCKOS_TEGRA_BACKEND=$backend
  printf '#!/bin/sh\necho "chattr $*" >>%s/chattr.log\n' "$dir" >"$dir/bin/chattr"
  export IRONFLOCKOS_CHATTR=$dir/bin/chattr
  # rauc status mark-good|mark-bad booted|other: the backend, as RAUC calls it.
  cat >"$dir/bin/rauc" <<EOF
#!/bin/sh
echo "rauc \$*" >>$dir/rauc.log
booted=\$(sed -n 's/.*rauc\\.slot=\\([AB]\\).*/\\1/p' $dir/cmdline)
slot=\$booted
if [ "\$3" = other ]; then if [ "\$booted" = A ]; then slot=B; else slot=A; fi; fi
case "\$2" in
  mark-good) exec "$backend" set-state "\$slot" good ;;
  mark-bad) exec "$backend" set-state "\$slot" bad ;;
esac
exit 2
EOF
  export IRONFLOCKOS_RAUC=$dir/bin/rauc
  printf '#!/bin/sh\necho reboot >>%s/reboot.log\n' "$dir" >"$dir/bin/reboot"
  export IRONFLOCKOS_REBOOT=$dir/bin/reboot
  chmod +x "$dir/bin/"*
  echo boot-1 >"$dir/boot_id"
  printf 'TNSPEC %s\nCOMPATIBLE_SPEC %s\nTEGRA_CHIPID 0x23\n' "$tnspec" "$spec" >"$dir/nv_boot_control.conf"
  echo launcher-old >"$dir/esp/EFI/BOOT/BOOTAA64.efi"
  # Both chains one generation behind the new slot (39.1 against 39.2):
  # the capsule is needed, and without it the slot is not switched to.
  module A "$v3910" "$v3910"
  new_slot "$dir/slot" 39 2.1
  # The running tree, for report.
  new_slot "$dir/running" 39 2.1
  export IRONFLOCKOS_ROOT=$dir/running
}

teardown() { rm -rf "$dir"; }

# --- the model --------------------------------------------------------------
le32() { printf '\\x%02x\\x%02x\\x%02x\\x%02x' $(($1 & 255)) $((($1 >> 8) & 255)) $((($1 >> 16) & 255)) $((($1 >> 24) & 255)); }
# fw_versions A B: SystemFwVersions as the firmware sets it at every boot.
fw_versions() {
  # shellcheck disable=SC2059
  printf "\\x06\\x00\\x00\\x00$(le32 "$1")$(le32 "$2")" >"$efi/SystemFwVersions-$nvguid"
}
rootfs_var() { # rootfs_var SLOT 00|ff
  printf "\\x07\\x00\\x00\\x00\\x$2\\x00\\x00\\x00" >"$efi/RootfsStatusSlot$1-$nvguid"
}
# module SLOT FW_A FW_B: a module flashed with rootfs A/B, slot SLOT running,
# the boot chains at these firmware versions.
module() {
  rootfs_var A 00
  rootfs_var B 00
  echo "$1" >"$nv/current"
  echo "$1" >"$nv/active"
  echo 2 >"$nv/retry_A"
  echo 3 >"$nv/retry_B"
  echo normal >"$nv/bl_status_A"
  echo normal >"$nv/bl_status_B"
  fw_versions "$2" "$3"
  local run=$2
  [ "$1" = A ] || run=$3
  echo 1 >"$dir/esrt/entries/entry0/fw_type"
  echo "$run" >"$dir/esrt/entries/entry0/fw_version"
  echo 0 >"$dir/esrt/entries/entry0/last_attempt_status"
  echo "$run" >"$dir/esrt/entries/entry0/last_attempt_version"
  running "$1"
}
running() { echo "console=ttyTCU0,115200 root=PARTUUID=x rw rauc.slot=$1" >"$dir/cmdline"; }
# fake_capsule FILE SPEC...: bytes around NVIDIA's board specs, NUL-padded as
# in a capsule's image table.
fake_capsule() {
  local f=$1 s
  shift
  printf 'FAKE-CAPSULE\000\000' >"$f"
  for s in "$@"; do printf '%s\000\000\000\000\177\001' "$s" >>"$f"; done
}
# new_slot ROOT R M.m: the slot RAUC has just written, built for L4T R.M.m.
new_slot() {
  local r=$1
  mkdir -p "$r/usr" "$r/etc" "$r/opt/ota_package/t23x"
  printf '# R%s (release), REVISION: %s, GCID: 1, BOARD: generic, EABI: aarch64, DATE: x\n' "$2" "$3" >"$r/etc/nv_tegra_release"
  fake_capsule "$r/opt/ota_package/t23x/TEGRA_BL_3767.Cap" \
    3767-000-0000--1-0-jetson-orin-nano-devkit- 3767-000-0003--1-0-jetson-orin-nano-devkit-
  fake_capsule "$r/opt/ota_package/t23x/TEGRA_BL_3767_super.Cap" 3767-000-0005--1-0-jetson-orin-nano-devkit-super-
  fake_capsule "$r/opt/ota_package/t23x/TEGRA_BL_3701_agx.Cap" 3701-300-0000--1-0-jetson-agx-orin-devkit-
  echo launcher-new >"$r/opt/ota_package/t23x/BOOTAA64.efi"
}
window() { printf '%s\n' "$@" >"$dir/maintenance.conf"; }
hex() { od -An -tx1 "$1" | tr -d ' \n'; }
staged() { [ -e "$dir/esp/EFI/UpdateCapsule/TEGRA_BL_3767.Cap" ]; }
not_staged() { [ ! -e "$dir/esp/EFI/UpdateCapsule/TEGRA_BL_3767.Cap" ]; }
state() { sed -n "s/^$1=//p" "$IRONFLOCKOS_TEGRA_AB_STATE" 2>/dev/null || true; }
osind() { hex "$efi/OsIndications-$gguid"; }

# --- stage: when the capsule is needed ------------------------------------------

@test "the boot chain of the slot already has its L4T release: no capsule, the update goes on" {
  module A "$v3921" "$v3921"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the boot firmware of slot B is L4T 39.2.1, as the slot needs: no capsule"* ]]
  not_staged
  [ ! -e "$efi/OsIndications-$gguid" ]
  [ -z "$(state capsule)" ]
}

@test "the version that counts is the target slot's boot chain, not the running one" {
  # Slot A runs on 39.2.1; chain B still has 39.1.0 from before (each capsule
  # writes only the chain of the slot it goes to).
  module A "$v3921" "$v3910"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the boot firmware of slot B is L4T 39.1.0, the slot needs L4T 39.2.1"* ]]
  module B "$v3910" "$v3921"
  run "$tool" stage A "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"slot A is L4T 39.1.0"* ]]
}

@test "another generation's firmware, no maintenance window: the update does not switch slots" {
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no maintenance window is open"* ]]
  [[ "$output" == *"not switching to slot B"* ]]
  not_staged
  [ ! -e "$efi/OsIndications-$gguid" ]
}

@test "the window file: boot-firmware=yes opens it, until= closes it in time" {
  window 'boot-firmware=no'
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not allow boot firmware updates (boot-firmware=no)"* ]]
  window '# the platform' 'boot-firmware = yes  # Tuesday night' "until=$((IRONFLOCKOS_NOW - 1))"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the maintenance window ended at"* ]]
  window 'boot-firmware=yes' "until=$((IRONFLOCKOS_NOW + 3600))"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  staged
}

@test "a window file it does not understand keeps the window closed" {
  for content in 'boot-firmware=maybe' 'firmware=yes' 'boot-firmware yes' 'until=tomorrow' \
    $'boot-firmware=yes\nboot-firmware=yes' $'boot-firmware=yes\nuntil=1\nuntil=2'; do
    printf '%s\n' "$content" >"$dir/maintenance.conf"
    run "$tool" stage B "$dir/slot"
    [ "$status" -eq 1 ] || { echo "accepted: $content"; return 1; }
    [[ "$output" == *"the window stays closed"* ]]
    not_staged
  done
  mkdir "$dir/maintenance.conf.d"
  rm "$dir/maintenance.conf"
  mv "$dir/maintenance.conf.d" "$dir/maintenance.conf"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a file of at most 4 KiB"* ]]
}

# --- stage: one generation, older firmware, no capsule ------------------------------

@test "one generation, no window: the slot is switched to without the capsule, on older firmware" {
  module A "$v3920" "$v3920"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the boot firmware of slot B is L4T 39.2.0, the slot needs L4T 39.2.1, and no maintenance window is open"* ]]
  [[ "$output" == *"switching to slot B without the capsule; it runs on the older boot firmware L4T 39.2.0 until an OS update inside a maintenance window brings L4T 39.2.1"* ]]
  not_staged
  [ ! -e "$efi/OsIndications-$gguid" ]
  [ -z "$(state capsule)" ]
  # RAUC then switches as for an update without new firmware.
  "$backend" set-state B bad
  "$backend" set-primary B
  grep -qx -- '-t rootfs set-active-boot-slot 1' "$nv/log"
  [ "$(state trial)" = B ]
}

@test "one generation, window closed or not understood, or open with no capsule to stage: switched to without it" {
  module A "$v3920" "$v3920"
  for content in 'boot-firmware=no' 'boot-firmware=maybe' "boot-firmware=yes"$'\n'"until=1"; do
    printf '%s\n' "$content" >"$dir/maintenance.conf"
    run "$tool" stage B "$dir/slot"
    [ "$status" -eq 0 ] || { echo "refused: $content"; return 1; }
    [[ "$output" == *"switching to slot B without the capsule"* ]]
  done
  window 'boot-firmware=yes'
  # a carrier board NVIDIA ships no capsule for
  printf 'COMPATIBLE_SPEC 3767--0003--1--acme-carrier-\n' >"$dir/nv_boot_control.conf"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no capsule (or more than one) for this board"*"switching to slot B without the capsule"* ]]
  # no board specs at all
  rm "$dir/nv_boot_control.conf"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"names no COMPATIBLE_SPEC"*"without the capsule"* ]]
  printf 'TNSPEC %s\nCOMPATIBLE_SPEC %s\nTEGRA_CHIPID 0x23\n' "$tnspec" "$spec" >"$dir/nv_boot_control.conf"
  # no room on the ESP, no ESP, firmware without capsules on disk
  IRONFLOCKOS_ESP_FREE_KB=900 run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the ESP has 900 KiB free"*"without the capsule"* ]]
  printf '\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >"$efi/OsIndicationsSupported-$gguid"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OsIndicationsSupported"*"without the capsule"* ]]
  rm "$efi/OsIndicationsSupported-$gguid"
  # Without efivarfs the chains' firmware cannot be read: refused, as unknown.
  IRONFLOCKOS_EFIVARS=$dir/no-efivars run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is unknown (SystemFwVersions)"*"not switching"* ]]
  not_staged
}

@test "one generation, window open and a capsule for the board: the capsule, as before" {
  module A "$v3920" "$v3920"
  window 'boot-firmware=yes'
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged NVIDIA's TEGRA_BL_3767.Cap"* ]]
  staged
}

@test "still refused within one generation: a downgrade, a capsule below the lowest supported version" {
  module A "$v3921" "$v3921"
  new_slot "$dir/slot" 39 2.0
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not take the firmware back to an older version"* ]]
  module A "$v3920" "$v3920"
  new_slot "$dir/slot" 39 2.1
  echo "$v3930" >"$dir/esrt/entries/entry0/lowest_supported_fw_version"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the ESRT's lowest supported version"* ]]
}

@test "still refused within one generation: the chain's firmware unknown or marked failed" {
  rm "$efi/SystemFwVersions-$nvguid"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is unknown (SystemFwVersions), and no maintenance window is open"*"not switching"* ]]
  module A "$v3921" "$v3921"
  echo unbootable >"$nv/bl_status_B"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is marked failed, and no maintenance window is open"*"not switching"* ]]
}

@test "report: a slot running on older firmware shows the firmware behind" {
  module A "$v3920" "$v3920"
  run "$tool" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"slot A runs L4T 39.2.1 on the older boot firmware L4T 39.2.0: an OS update inside a maintenance window brings the firmware up"* ]]
  grep -qx 'firmware-behind=yes' "$dir/run/boot-firmware"
  grep -qx 'slot-release=39.2.1' "$dir/run/boot-firmware"
  module A "$v3921" "$v3920"
  run "$tool" report
  grep -qx 'firmware-behind=no' "$dir/run/boot-firmware"
  rm "$dir/running/etc/nv_tegra_release"
  run "$tool" report
  [ "$status" -eq 0 ]
  grep -qx 'firmware-behind=unknown' "$dir/run/boot-firmware"
}

# --- stage: what it writes --------------------------------------------------------

@test "staged as NVIDIA's updater does it: the capsule by its name in EFI/UpdateCapsule, bit 2 of OsIndications" {
  window 'boot-firmware=yes'
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged NVIDIA's TEGRA_BL_3767.Cap (L4T 39.2.1) on the ESP"* ]]
  cmp "$dir/slot/opt/ota_package/t23x/TEGRA_BL_3767.Cap" "$dir/esp/EFI/UpdateCapsule/TEGRA_BL_3767.Cap"
  [ "$(ls "$dir/esp/EFI/UpdateCapsule")" = TEGRA_BL_3767.Cap ]
  # attributes 7 (non-volatile, boot service, runtime), then the UINT64 4
  [ "$(osind)" = 070000000400000000000000 ]
  # NVIDIA's L4TLauncher of the same release goes with it
  [ "$(cat "$dir/esp/EFI/BOOT/BOOTAA64.efi")" = launcher-new ]
  [ "$(state capsule)" = B ]
  [ "$(state capsule-boot)" = boot-1 ]
  [ "$(state capsule-file)" = TEGRA_BL_3767.Cap ]
  [ "$(state capsule-version)" = 39.2.1 ]
}

@test "the platform specs the firmware picks the capsule's images by, as nv-l4t-bootloader-config writes them" {
  window 'boot-firmware=yes'
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [ "$(hex "$efi/TegraPlatformCompatSpec-$nvguid")" = "07000000$(printf '%s' "$spec" | od -An -tx1 | tr -d ' \n')" ]
  [ "$(hex "$efi/TegraPlatformSpec-$nvguid")" = "07000000$(printf '%s' "$tnspec" | od -An -tx1 | tr -d ' \n')" ]
  grep -q "chattr +i $efi/TegraPlatformCompatSpec-$nvguid" "$dir/chattr.log"
  # The platform spec is written once; the compatible spec when it differs.
  printf '\x07\x00\x00\x00other-spec' >"$efi/TegraPlatformSpec-$nvguid"
  printf '\x07\x00\x00\x003767-old' >"$efi/TegraPlatformCompatSpec-$nvguid"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [ "$(tail -c +5 "$efi/TegraPlatformSpec-$nvguid")" = other-spec ]
  [ "$(tail -c +5 "$efi/TegraPlatformCompatSpec-$nvguid")" = "$spec" ]
}

@test "a pending switch of the boot chain and an old switch's status go: the firmware would cancel the capsule" {
  window 'boot-firmware=yes'
  printf '\x07\x00\x00\x00\x01\x00\x00\x00' >"$efi/BootChainFwNext-$nvguid"
  printf '\x07\x00\x00\x00\x00\x00\x00\x00' >"$efi/BootChainFwStatus-$nvguid"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BootChainFwNext was 1; deleting it"* ]]
  [ ! -e "$efi/BootChainFwNext-$nvguid" ]
  [ ! -e "$efi/BootChainFwStatus-$nvguid" ]
  grep -q "chattr -i $efi/BootChainFwStatus-$nvguid" "$dir/chattr.log"
}

@test "each board gets its own capsule, picked by the firmware's spec rule" {
  window 'boot-firmware=yes'
  printf 'COMPATIBLE_SPEC 3701-300-0000--1--jetson-agx-orin-devkit-\n' >"$dir/nv_boot_control.conf"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [ "$(ls "$dir/esp/EFI/UpdateCapsule")" = TEGRA_BL_3701_agx.Cap ]
  printf 'COMPATIBLE_SPEC 3767--0005--1--jetson-orin-nano-devkit-super-\n' >"$dir/nv_boot_control.conf"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [ "$(ls "$dir/esp/EFI/UpdateCapsule")" = TEGRA_BL_3767_super.Cap ]
}

@test "a board NVIDIA ships no capsule for, or no board at all: not switching" {
  window 'boot-firmware=yes'
  printf 'COMPATIBLE_SPEC 3767--0003--1--acme-carrier-\n' >"$dir/nv_boot_control.conf"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"carries no capsule (or more than one) for this board (3767--0003--1--acme-carrier-)"* ]]
  not_staged
  rm "$dir/nv_boot_control.conf"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names no COMPATIBLE_SPEC: the board is unknown"* ]]
}

@test "two capsules for one board are ambiguous: not switching" {
  window 'boot-firmware=yes'
  cp "$dir/slot/opt/ota_package/t23x/TEGRA_BL_3767.Cap" "$dir/slot/opt/ota_package/t23x/TEGRA_BL_3767_copy.Cap"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no capsule (or more than one)"* ]]
}

@test "no ESP, or too little room on it: not switching" {
  window 'boot-firmware=yes'
  IRONFLOCKOS_ESP_FREE_KB=900 run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the ESP has 900 KiB free, the capsule needs"* ]]
  rm -rf "$dir/esp/EFI"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the ESP is not at $dir/esp"* ]]
}

@test "no capsule across L4T generations, and none back to an older release" {
  window 'boot-firmware=yes'
  module A "$v3640" "$v3640"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not cross L4T releases (R36 to R39): the module needs a flash"* ]]
  module A "$v3930" "$v3930"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not take the firmware back to an older version"* ]]
  not_staged
  # The running chain's lowest supported version (the ESRT) counts as well.
  module A "$v3930" "$v3920"
  echo "$v3930" >"$dir/esrt/entries/entry0/lowest_supported_fw_version"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the firmware takes no capsule older than L4T 39.3.0 (the ESRT's lowest supported version)"* ]]
  not_staged
}

@test "the chain's version unknown, or the chain marked failed: the capsule is needed" {
  window 'boot-firmware=yes'
  rm "$efi/SystemFwVersions-$nvguid"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the version of the boot firmware of slot B is unknown"* ]]
  staged
  module A "$v3921" "$v3921"
  echo unbootable >"$nv/bl_status_B"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the boot firmware of slot B is marked failed"* ]]
  staged
}

@test "a slot without an L4T release, or firmware that takes no capsules from disk: not switching" {
  window 'boot-firmware=yes'
  rm "$dir/slot/etc/nv_tegra_release"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names no L4T release"* ]]
  new_slot "$dir/slot" 39 2.1
  printf '\x06\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >"$efi/OsIndicationsSupported-$gguid"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not take capsules from the ESP"* ]]
  printf '\x06\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00' >"$efi/OsIndicationsSupported-$gguid"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  staged
}

@test "a capsule left from an earlier install never outlives the next one" {
  window 'boot-firmware=yes'
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  staged
  module A "$v3921" "$v3921"
  echo stale >"$dir/esp/EFI/UpdateCapsule/fwupd-other.cap"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  [ -z "$(ls "$dir/esp/EFI/UpdateCapsule")" ]
  [ "$(osind)" = 070000000000000000000000 ]
  [ -z "$(state capsule)" ]
}

# --- pending and withdraw ----------------------------------------------------------

@test "pending: only for the slot it was staged for, and only in the boot that staged it" {
  window 'boot-firmware=yes'
  run "$tool" pending B
  [ "$status" -eq 1 ]
  "$tool" stage B "$dir/slot"
  "$tool" pending B
  run "$tool" pending A
  [ "$status" -eq 1 ]
  echo boot-2 >"$dir/boot_id"
  run "$tool" pending B
  [ "$status" -eq 1 ]
}

@test "withdraw takes the capsule off the ESP and clears only bit 2 of OsIndications" {
  window 'boot-firmware=yes'
  "$tool" stage B "$dir/slot"
  printf '\x07\x00\x00\x00\x05\x00\x00\x00\x00\x00\x00\x00' >"$efi/OsIndications-$gguid"
  run "$tool" withdraw
  [ "$status" -eq 0 ]
  [[ "$output" == *"the capsule staged for slot B is withdrawn"* ]]
  not_staged
  [ "$(osind)" = 070000000100000000000000 ]
  [ -z "$(state capsule)" ]
  [ -z "$(state capsule-boot)" ]
  [ -z "$(state capsule-file)" ]
  run "$tool" withdraw
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the RAUC backend with a staged capsule ------------------------------------------

@test "set-primary with a capsule: the slot is made bootable and on trial, and nvbootctrl switches nothing" {
  window 'boot-firmware=yes'
  "$backend" set-state B bad
  "$tool" stage B "$dir/slot"
  : >"$nv/log"
  run "$backend" set-primary B
  [ "$status" -eq 0 ]
  [[ "$output" == *"slot B boots next, through the capsule staged for its boot chain"* ]]
  [ -z "$(grep set-active-boot-slot "$nv/log")" ]
  [ ! -e "$efi/BootChainFwNext-$nvguid" ]
  [ "$(od -An -tx1 -j4 -N1 "$efi/RootfsStatusSlotB-$nvguid" | tr -d ' \n')" = 00 ]
  [ "$(state trial)" = B ]
  [ "$(state B)" = trying ]
  # RAUC sees the slot the capsule goes to as the next one.
  [ "$("$backend" get-primary)" = B ]
  echo boot-2 >"$dir/boot_id"
  [ "$("$backend" get-primary)" = A ]
}

@test "RAUC writing the slot again, or keeping the running one, withdraws the capsule" {
  window 'boot-firmware=yes'
  "$tool" stage B "$dir/slot"
  "$backend" set-state B bad
  not_staged
  [ -z "$(state capsule)" ]
  "$tool" stage B "$dir/slot"
  "$backend" set-primary B
  "$backend" set-primary A
  not_staged
  [ -z "$(state trial)" ]
  [ "$(osind)" = 070000000000000000000000 ]
}

@test "without a capsule the backend switches through nvbootctrl, as before" {
  module A "$v3921" "$v3921"
  "$backend" set-state B bad
  "$tool" stage B "$dir/slot"
  "$backend" set-primary B
  grep -qx -- '-t rootfs set-active-boot-slot 1' "$nv/log"
  [ "$("$backend" get-primary)" = B ]
}

# --- report, after the restart ---------------------------------------------------------

# install: what rauc install does: set-state bad, write, post-install
# (stage), set-primary.
install() {
  "$backend" set-state B bad
  "$tool" stage B "$dir/slot"
  "$backend" set-primary B
}
# firmware_applies: the next boot as edk2-nvidia does it with a capsule on the
# ESP: the capsule goes, the inactive chain is written and becomes the active
# one (cold reset), and with RootfsRedundancyLevel 1 its root slot boots.
firmware_applies() {
  rm -f "$dir/esp/EFI/UpdateCapsule/"*
  printf '\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >"$efi/OsIndications-$gguid"
  fw_versions "$v3920" "$v3921"
  echo B >"$nv/current" && echo B >"$nv/active"
  echo "$v3921" >"$dir/esrt/entries/entry0/fw_version"
  echo 0 >"$dir/esrt/entries/entry0/last_attempt_status"
  echo "$v3921" >"$dir/esrt/entries/entry0/last_attempt_version"
  running B
  echo boot-2 >"$dir/boot_id"
}
# firmware_rejects CODE: the capsule is refused (CheckImage) or its writes
# fail: the chain stays, so does the root slot.
firmware_rejects() {
  rm -f "$dir/esp/EFI/UpdateCapsule/"*
  printf '\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >"$efi/OsIndications-$gguid"
  echo "$1" >"$dir/esrt/entries/entry0/last_attempt_status"
  echo "$v3921" >"$dir/esrt/entries/entry0/last_attempt_version"
  running A
  echo boot-2 >"$dir/boot_id"
}

@test "an update with a capsule: the firmware writes chain B and boots slot B, on trial" {
  window 'boot-firmware=yes'
  install
  firmware_applies
  run "$tool" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEGRA_BL_3767.Cap for slot B (L4T 39.2.1): applied, slot B runs on boot chain B with L4T 39.2.1"* ]]
  [ "$(state capsule-result)" = applied ]
  [ -z "$(state capsule)" ]
  grep -qx 'slot-a-firmware=39.2.0' "$dir/run/boot-firmware"
  grep -qx 'slot-b-firmware=39.2.1' "$dir/run/boot-firmware"
  grep -qx 'capsule-result=applied' "$dir/run/boot-firmware"
  [ ! -e "$dir/rauc.log" ]
  # The health gate counts the trial; the agent's mark ends it.
  "$trial_tool" keep
  [ "$(state trial)" = B ]
  [ "$(state trial-boots)" = 1 ]
  "$IRONFLOCKOS_RAUC" status mark-good booted
  [ -z "$(state trial)" ]
  [ "$(state B)" = good ]
}

@test "a capsule the firmware rejects leaves slot A booting, and slot B marked bad" {
  window 'boot-firmware=yes'
  install
  firmware_rejects 6151 # 0x1807: no image in the capsule for this board's spec
  run "$tool" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"failed, the firmware rejected or could not write the capsule: image-not-in-package (6151)"* ]]
  grep -qx 'rauc status mark-bad other' "$dir/rauc.log"
  [ "$(od -An -tx1 -j4 -N1 "$efi/RootfsStatusSlotB-$nvguid" | tr -d ' \n')" = ff ]
  [ "$(state B)" = bad ]
  [ -z "$(state trial)" ]
  grep -qx 'capsule-result=failed' "$dir/run/boot-firmware"
  grep -qx 'last-attempt-status=6151' "$dir/run/boot-firmware"
  # The health gate keeps slot A, and restarts nothing.
  "$trial_tool" keep
  [ ! -e "$dir/reboot.log" ]
  [ "$(state A)" = good ]
}

@test "a capsule the firmware never took is taken off the ESP after the restart" {
  window 'boot-firmware=yes'
  install
  running A
  echo boot-2 >"$dir/boot_id"
  run "$tool" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"not-processed, the firmware did not take TEGRA_BL_3767.Cap"* ]]
  not_staged
  [ "$(osind)" = 070000000000000000000000 ]
}

@test "the capsule applied, but slot B did not boot: the firmware fell back to chain and slot A" {
  window 'boot-firmware=yes'
  install
  firmware_applies
  echo A >"$nv/current"
  echo A >"$nv/active"
  running A
  echo "$v3920" >"$dir/esrt/entries/entry0/fw_version"
  run "$tool" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"applied, boot chain B has L4T 39.2.1, but the device fell back to slot A"* ]]
}

@test "report without a capsule, or without any firmware interface, never fails" {
  run "$tool" report
  [ "$status" -eq 0 ]
  grep -qx 'capsule-result=' "$dir/run/boot-firmware"
  rm -rf "$efi" "$dir/esrt"
  run "$tool" report
  [ "$status" -eq 0 ]
  grep -qx 'slot-a-firmware=unknown' "$dir/run/boot-firmware"
}

@test "the command line" {
  run "$tool"
  [ "$status" -eq 1 ]
  run "$tool" stage C "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown slot 'C'"* ]]
  run "$tool" stage B "$dir/nowhere"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is not a root tree"* ]]
  run "$tool" frobnicate
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown command"* ]]
}

# --- the build: NVIDIA's capsules in the tree, in lock-step -----------------------

# fmp_capsule FILE VERSION [LOWEST]: a UEFI FMP capsule's first bytes:
# EFI_FMP_CAPSULE_GUID, filler where the authentication header is, then the
# FMP payload header "MSS1" (signature, header size, version, lowest version).
fmp_capsule() {
  # shellcheck disable=SC2059
  printf "\\xed\\xd5\\xcb\\x6d\\x2d\\xe8\\x44\\x4c\\xbd\\xa1\\x71\\x94\\x19\\x9a\\xd9\\x2a$(printf 'x%.0s' $(seq 1 300))MSS1$(le32 16)$(le32 "$2")$(le32 "${3:-$2}")rest" >"$1"
}
# built_tree: a root tree as the build leaves it, with nvidia-l4t-bootloader
# at the pins of target.conf and bsp.conf.
built_tree() {
  local r=$dir/tree t=$dir/tree/opt/ota_package/t23x
  mkdir -p "$t" "$r/usr/share/doc/nvidia-l4t-bootloader" "$r/var/lib/dpkg" "$r/etc"
  for c in TEGRA_BL_3767.Cap TEGRA_BL_3767_super.Cap TEGRA_BL_3701_agx.Cap TEGRA_BL_3701_000.Cap; do
    fmp_capsule "$t/$c" "$v3921"
  done
  echo launcher >"$t/BOOTAA64.efi"
  printf 'Package: nvidia-l4t-core\nVersion: 1\n\nPackage: nvidia-l4t-bootloader\nStatus: install ok installed\nVersion: %s\n\n' \
    "$(sed -n 's/^L4T_PACKAGE_VERSION=//p' "$repo/targets/jetson-orin/target.conf")" >"$r/var/lib/dpkg/status"
  printf '# R39 (release), REVISION: 2.1, GCID: 1, BOARD: generic, EABI: aarch64, DATE: x\n' >"$r/etc/nv_tegra_release"
  echo "NVIDIA Driver License Agreement" >"$r/usr/share/doc/nvidia-l4t-bootloader/copyright"
  echo FreeRTOS | gzip >"$r/usr/share/doc/nvidia-l4t-bootloader/LICENSE.bl_update_payload.gz"
}

@test "build: NVIDIA's capsules of the pinned release pass, and the FreeRTOS statement is written" {
  grep -qx 'L4T_VERSION=39.2.1' "$repo/targets/jetson-orin/bsp.conf" || skip "the fake capsules are 39.2.1"
  built_tree
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 capsules of L4T 39.2.1 from nvidia-l4t-bootloader 39.2.1-"* ]]
  offer=$dir/tree/usr/share/doc/ironflockos/FreeRTOS-source-offer.txt
  grep -q 'FreeRTOS V8.1.2' "$offer"
  grep -q '/ironflockos/sources/l4t-39.2.1/$' "$offer"
  grep -q '^  https://' "$offer"
  ! grep -qE '@[A-Z][A-Z0-9_]*@' "$offer"
}

@test "build: the statement offers the source at the mirror the release fills, and names the contact of release/contact" {
  grep -qx 'L4T_VERSION=39.2.1' "$repo/targets/jetson-orin/bsp.conf" || skip "the fake capsules are 39.2.1"
  built_tree
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -eq 0 ]
  offer=$dir/tree/usr/share/doc/ironflockos/FreeRTOS-source-offer.txt
  # shellcheck source=build/lib.sh
  . "$repo/build/lib.sh"
  load_conf "$repo/build/release.conf"
  load_conf "$repo/targets/jetson-orin/bsp.conf"
  # the mirror's place, as build/sources.sh puts NVIDIA's sources there
  grep -qxF "  $DL_BASE/ironflockos/sources/$(l4t_sources_dir)/" "$offer"
  [ "$(l4t_sources_dir)" = l4t-39.2.1 ]
  # the contact as IronFlock gave it, the entity as the one that offers
  grep -qx '  IronFlock GmbH' "$offer"
  grep -qx '  Taunusanlage 8' "$offer"
  grep -qx '  60329 Frankfurt am Main' "$offer"
  grep -q 'legal@ironflock.com' "$offer"
  grep -q '^Offer of the source code: IronFlock GmbH provides the FreeRTOS source code' "$offer"
  # the facts stay; no promise the owner has not made
  grep -q 'FreeRTOS V8.1.2' "$offer"
  grep -q 'FreeRTOSV8.1.2_src.tbz2 and spe-freertos-bsp.tbz2' "$offer"
  ! grep -qiE 'three years|valid for|charge|cost' "$offer"
}

@test "build: an emptied contact, or a statement without the mirror or the contact, fails it" {
  grep -qx 'L4T_VERSION=39.2.1' "$repo/targets/jetson-orin/bsp.conf" || skip "the fake capsules are 39.2.1"
  built_tree
  sed 's/^CONTACT_EMAIL=.*/CONTACT_EMAIL=/' "$repo/release/contact" >"$dir/contact"
  IRONFLOCKOS_CONTACT=$dir/contact run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"the contact of the source offers is incomplete (empty: CONTACT_EMAIL)"* ]]
  sed 's/^\(CONTACT_[A-Z]*\)=.*/\1=/' "$repo/release/contact" >"$dir/contact"
  IRONFLOCKOS_CONTACT=$dir/contact run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty: CONTACT_NAME CONTACT_STREET CONTACT_CITY CONTACT_EMAIL"* ]]
  # a statement that names another place than the mirror
  sed 's|@L4T_SOURCES_DIR@|l4t-@L4T_VERSION@-old|' "$repo/targets/jetson-orin/freertos-offer.txt" >"$dir/offer.txt"
  IRONFLOCKOS_FREERTOS_OFFER=$dir/offer.txt run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not offer the source at the mirror"* ]]
  # a statement without the postal address
  grep -v '@CONTACT_STREET@' "$repo/targets/jetson-orin/freertos-offer.txt" >"$dir/offer.txt"
  IRONFLOCKOS_FREERTOS_OFFER=$dir/offer.txt run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not name the contact's \"Taunusanlage 8\""* ]]
}

@test "build: a capsule of another release fails it (lock-step with the BSP pin)" {
  grep -qx 'L4T_VERSION=39.2.1' "$repo/targets/jetson-orin/bsp.conf" || skip "the fake capsules are 39.2.1"
  built_tree
  fmp_capsule "$dir/tree/opt/ota_package/t23x/TEGRA_BL_3767.Cap" "$v3930"
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TEGRA_BL_3767.Cap is L4T 39.3.0, the BSP pin is L4T 39.2.1 (bsp.conf): QSPI and rootfs stay in lock-step"* ]]
}

@test "build: a tree without capsules, without one board's, or with a file that is no capsule fails it" {
  built_tree
  rm "$dir/tree/opt/ota_package/t23x/TEGRA_BL_3701"*
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no capsule for board 3701"* ]]
  built_tree
  echo "not a capsule" >"$dir/tree/opt/ota_package/t23x/TEGRA_BL_3767.Cap"
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TEGRA_BL_3767.Cap is not a UEFI FMP capsule"* ]]
  rm -rf "$dir/tree/opt"
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nvidia-l4t-bootloader is not in the tree"* ]]
}

@test "build: the package's version, the tree's L4T release and the licence texts are checked" {
  grep -qx 'L4T_VERSION=39.2.1' "$repo/targets/jetson-orin/bsp.conf" || skip "the fake capsules are 39.2.1"
  built_tree
  sed -i.bak 's/^Version: 39.*/Version: 39.2.0-1/' "$dir/tree/var/lib/dpkg/status"
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nvidia-l4t-bootloader is 39.2.0-1, the pin is"* ]]
  built_tree
  printf '# R39 (release), REVISION: 3.0, GCID: 1\n' >"$dir/tree/etc/nv_tegra_release"
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"/etc/nv_tegra_release does not name L4T 39.2.1"* ]]
  built_tree
  rm "$dir/tree/usr/share/doc/nvidia-l4t-bootloader/LICENSE.bl_update_payload.gz"
  run bash "$repo/build/tegra-capsules.sh" "$dir/tree"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lacks NVIDIA's licence texts"* ]]
}

@test "the image: the package, the check, the report unit, the window's link, the post-install hook" {
  grep -q 'enable ironflockos-tegra-board-conf.service' "$repo/build/customize.sh"
  grep -qx 'enable ironflockos-tegra-board-conf.service' "$repo/targets/jetson-orin/overlay/usr/lib/systemd/system-preset/10-ironflockos-tegra.preset"
  grep -qx 'ExecStart=-/usr/lib/ironflockos/tegra-board-conf' "$repo/targets/jetson-orin/overlay/usr/lib/systemd/system/ironflockos-tegra-board-conf.service"
  grep -qx 'Before=ironflockos-tegra-capsule.service ironflockos-tegra-keep.service' "$repo/targets/jetson-orin/overlay/usr/lib/systemd/system/ironflockos-tegra-board-conf.service"
  grep -qx nvidia-l4t-bootloader "$repo/targets/jetson-orin/packages"
  grep -q 'bash "$here/tegra-capsules.sh" "$ROOT"' "$repo/build/customize.sh"
  grep -q 'enable ironflockos-tegra-capsule.service' "$repo/build/customize.sh"
  grep -q 'ln -sfn /data/ironflockos/maintenance.conf "$ROOT/etc/ironflockos/maintenance.conf"' "$repo/build/customize.sh"
  grep -qx 'enable ironflockos-tegra-capsule.service' "$repo/targets/jetson-orin/overlay/usr/lib/systemd/system-preset/10-ironflockos-tegra.preset"
  grep -qx 'ExecStart=-/usr/lib/ironflockos/tegra-capsule report' "$repo/targets/jetson-orin/overlay/usr/lib/systemd/system/ironflockos-tegra-capsule.service"
  [ -x "$tool" ]
  pi=$repo/overlay/usr/lib/ironflockos/rauc-post-install
  grep -q 'files="/etc/machine-id /etc/hostname /etc/nv_boot_control.conf"' "$pi"
  grep -q '"$capsule_tool" stage "$bootname" "$mnt" || fail' "$pi"
}

# --- the module's nv_boot_control.conf from the ESP ----------------------------

board="$repo/targets/jetson-orin/overlay/usr/lib/ironflockos/tegra-board-conf"
esp_conf() {
  printf 'TNSPEC %s\nCOMPATIBLE_SPEC %s\nTEGRA_LEGACY_UPDATE false\nTEGRA_CHIPID 0x23\n' "$tnspec" "$spec" >"$dir/esp/nv_boot_control.conf"
}

@test "board conf: the ESP's file goes to /etc when /etc has none, or another" {
  rm "$dir/nv_boot_control.conf"
  esp_conf
  run "$board"
  [ "$status" -eq 0 ]
  [[ "$output" == *"copied the module's nv_boot_control.conf from the ESP to $dir/nv_boot_control.conf ($spec)"* ]]
  cmp "$dir/esp/nv_boot_control.conf" "$dir/nv_boot_control.conf"
  [ "$(stat -c %a "$dir/nv_boot_control.conf" 2>/dev/null || stat -f %Lp "$dir/nv_boot_control.conf")" = 644 ]
  run "$board"
  [ "$status" -eq 0 ]
  [[ "$output" == *"is the module's ($spec)"* ]]
  printf 'TNSPEC old\nCOMPATIBLE_SPEC old\nTEGRA_CHIPID 0x23\n' >"$dir/nv_boot_control.conf"
  run "$board"
  [ "$status" -eq 0 ]
  cmp "$dir/esp/nv_boot_control.conf" "$dir/nv_boot_control.conf"
  [ ! -e "$dir/nv_boot_control.conf.new" ]
}

@test "board conf: no file on the ESP, or one that is not NVIDIA's, leaves /etc as it is and never fails" {
  cp "$dir/nv_boot_control.conf" "$dir/before"
  run "$board"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no nv_boot_control.conf on the ESP; $dir/nv_boot_control.conf stays as it is"* ]]
  cmp "$dir/before" "$dir/nv_boot_control.conf"
  for bad in 'TNSPEC x' $'TNSPEC x\nCOMPATIBLE_SPEC y\nTEGRA_CHIPID 0x23\nTNSPEC z' $'TNSPEC x y\nCOMPATIBLE_SPEC y\nTEGRA_CHIPID 0x23'; do
    printf '%s\n' "$bad" >"$dir/esp/nv_boot_control.conf"
    run "$board"
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not NVIDIA's nv_boot_control.conf"* ]]
    cmp "$dir/before" "$dir/nv_boot_control.conf"
  done
  rm "$dir/esp/nv_boot_control.conf" "$dir/nv_boot_control.conf"
  run "$board"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no nv_boot_control.conf on the ESP or in /etc: nvbootctrl uses its fallback, and no boot firmware capsule can be staged"* ]]
  esp_conf
  IRONFLOCKOS_BOOT_CTRL_CONF=$dir/nowhere/nv_boot_control.conf run "$board"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not write $dir/nowhere/nv_boot_control.conf"* ]]
}

@test "board conf, then a capsule: on a module flashed with the kit, /etc gets the specs the capsule is chosen by" {
  rm "$dir/nv_boot_control.conf"
  esp_conf
  window 'boot-firmware=yes'
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 1 ]
  [[ "$output" == *"names no COMPATIBLE_SPEC"* ]]
  "$board"
  run "$tool" stage B "$dir/slot"
  [ "$status" -eq 0 ]
  staged
}
