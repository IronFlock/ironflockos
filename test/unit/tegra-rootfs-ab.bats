#!/usr/bin/env bats
# Jetson's RAUC backend over nvbootctrl and its health gate (WP-6.3): every
# command of tegra-rootfs-ab and tegra-slot-trial against a fake nvbootctrl
# (fixtures/nvbootctrl: the format of r39.2.1's output, written from the
# tool's format strings), fake efivarfs files for RootfsStatusSlotA/B, and a
# model of NVIDIA's firmware that counts boots as L4TRootfsValidation.c of
# edk2-nvidia does.

repo="$BATS_TEST_DIRNAME/../.."
fixtures="$BATS_TEST_DIRNAME/fixtures/nvbootctrl"
lib="$repo/targets/jetson-orin/overlay/usr/lib/ironflockos"
backend="$lib/tegra-rootfs-ab"
trial_tool="$lib/tegra-slot-trial"
guid=781e084c-a330-417c-b678-38e696380cb9

setup() {
  dir=$(mktemp -d)
  nv=$dir/nv
  mkdir -p "$nv/efivars" "$dir/bin"
  export FAKE_NV=$nv
  export IRONFLOCKOS_NVBOOTCTRL=$fixtures/fake-nvbootctrl
  export IRONFLOCKOS_EFIVARS=$nv/efivars
  export IRONFLOCKOS_TEGRA_AB_STATE=$dir/data/rauc/state
  export IRONFLOCKOS_PROC_CMDLINE=$dir/cmdline
  export IRONFLOCKOS_TEGRA_BACKEND=$backend
  # chattr: efivarfs's immutable flag; here a log of what was asked.
  printf '#!/bin/sh\necho "chattr $*" >>%s/chattr.log\n' "$dir" >"$dir/bin/chattr"
  export IRONFLOCKOS_CHATTR=$dir/bin/chattr
  # rauc status mark-good|mark-bad booted: the backend on the booted slot,
  # as RAUC's custom backend calls it.
  cat >"$dir/bin/rauc" <<EOF
#!/bin/sh
echo "rauc \$*" >>$dir/rauc.log
[ -e $dir/rauc-busy ] && exit 1
slot=\$(sed -n 's/.*rauc\\.slot=\\([AB]\\).*/\\1/p' $dir/cmdline)
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
  flashed
}

teardown() { rm -rf "$dir"; }

# --- the model of the module ---------------------------------------------------
var() { echo "$nv/efivars/RootfsStatusSlot$1-$guid"; }
# set_var SLOT normal|unbootable: the variable as the firmware leaves it.
set_var() {
  local b='\x00'
  [ "$2" = normal ] || b='\xff'
  printf "\\x07\\x00\\x00\\x00$b\\x00\\x00\\x00" >"$(var "$1")"
}
var_byte() { od -An -tx1 -j4 -N1 "$(var "$1")" | tr -d ' \n'; }
# flashed: NVIDIA's flash with ROOTFS_AB=1, slot A booted for the first time.
flashed() {
  set_var A normal
  set_var B normal
  echo A >"$nv/current"
  echo A >"$nv/active"
  echo 2 >"$nv/retry_A"
  echo 3 >"$nv/retry_B"
  running A
}
# running SLOT: the kernel command line of a boot of SLOT.
running() {
  echo "console=ttyTCU0,115200 root=PARTUUID=x rw rauc.slot=$1" >"$dir/cmdline"
}
status_of() { if [ "$(var_byte "$1")" = ff ]; then echo unbootable; else echo normal; fi; }
other() { if [ "$1" = A ]; then echo B; else echo A; fi; }
# boot [cold]: NVIDIA's firmware starts the next boot (L4TRootfsValidation.c):
# a switch of the boot chain and a cold boot start the scratch register over
# (three tries for each slot that is not unbootable); each boot takes a try
# off the slot it starts; a slot without tries is marked unbootable and the
# other slot starts, or the recovery kernel when it has none either.
boot() {
  local cur act s
  cur=$(cat "$nv/current") act=$(cat "$nv/active")
  if [ "${1:-}" = cold ] || [ "$act" != "$cur" ]; then
    for s in A B; do
      if [ "$(status_of $s)" = normal ]; then echo 3; else echo 0; fi >"$nv/retry_$s"
    done
    cur=$act
  fi
  if [ "$(cat "$nv/retry_$cur")" -eq 0 ]; then
    set_var "$cur" unbootable
    cur=$(other "$cur")
    if [ "$(cat "$nv/retry_$cur")" -eq 0 ]; then
      echo recovery >"$nv/current"
      return 0
    fi
    for s in A B; do
      if [ "$(status_of $s)" = normal ]; then echo 3; else echo 0; fi >"$nv/retry_$s"
    done
  fi
  echo $(($(cat "$nv/retry_$cur") - 1)) >"$nv/retry_$cur"
  echo "$cur" >"$nv/current"
  echo "$cur" >"$nv/active"
  running "$cur"
}
state() { sed -n "s/^$1=//p" "$IRONFLOCKOS_TEGRA_AB_STATE" 2>/dev/null || true; }
nvlog() { cat "$nv/log" 2>/dev/null || true; }
reboots() { if [ -e "$dir/reboot.log" ]; then wc -l <"$dir/reboot.log" | tr -d ' '; else echo 0; fi; }
# install: what rauc install does with a bundle on the running slot.
install() {
  local target
  target=$(other "$(cat "$nv/current")")
  "$backend" set-state "$target" bad
  "$backend" set-primary "$target"
}

# --- the fake against the fixtures -------------------------------------------------

@test "the fake prints dump-slots-info as the fixtures have it" {
  run "$IRONFLOCKOS_NVBOOTCTRL" -t rootfs dump-slots-info
  [ "$status" -eq 0 ]
  echo 3 >"$nv/retry_A"
  diff <("$IRONFLOCKOS_NVBOOTCTRL" -t rootfs dump-slots-info) "$fixtures/dump-slots-info.flashed"
  set_var B unbootable
  echo 2 >"$nv/retry_A"
  echo 0 >"$nv/retry_B"
  diff <("$IRONFLOCKOS_NVBOOTCTRL" -t rootfs dump-slots-info) "$fixtures/dump-slots-info.fallen-back"
  touch "$nv/ab-disabled"
  diff <("$IRONFLOCKOS_NVBOOTCTRL" -t rootfs dump-slots-info || true) "$fixtures/dump-slots-info.ab-disabled"
}

@test "the backend reads every fixture: slots, primary, states" {
  for f in flashed fallen-back; do
    printf '#!/bin/sh\ncat %s\n' "$fixtures/dump-slots-info.$f" >"$dir/bin/nvbootctrl-$f"
    chmod +x "$dir/bin/nvbootctrl-$f"
  done
  IRONFLOCKOS_NVBOOTCTRL=$dir/bin/nvbootctrl-flashed run "$backend" get-current
  [ "$status" -eq 0 ]
  [ "$output" = A ]
  IRONFLOCKOS_NVBOOTCTRL=$dir/bin/nvbootctrl-flashed run "$backend" get-primary
  [ "$status" -eq 0 ]
  [ "$output" = A ]
  mkdir -p "$dir/data/rauc" && echo B=good >"$IRONFLOCKOS_TEGRA_AB_STATE"
  IRONFLOCKOS_NVBOOTCTRL=$dir/bin/nvbootctrl-flashed run "$backend" get-state B
  [ "$output" = good ]
  # The firmware gave B up: whatever the state file says, B is bad.
  IRONFLOCKOS_NVBOOTCTRL=$dir/bin/nvbootctrl-fallen-back run "$backend" get-state B
  [ "$status" -eq 0 ]
  [ "$output" = bad ]
  IRONFLOCKOS_NVBOOTCTRL=$dir/bin/nvbootctrl-fallen-back run "$backend" get-state A
  [ "$output" = good ]
}

# --- the protocol ------------------------------------------------------------------

@test "get-current and get-primary are nvbootctrl's current and active rootfs slot" {
  run "$backend" get-current
  [ "$status" -eq 0 ]
  [ "$output" = A ]
  run "$backend" get-primary
  [ "$status" -eq 0 ]
  [ "$output" = A ]
  echo B >"$nv/active"
  run "$backend" get-primary
  [ "$output" = B ]
  run "$backend" get-current
  [ "$output" = A ]
  [[ "$(nvlog)" == *"-t rootfs dump-slots-info"* ]]
}

@test "get-state: the running slot is good, an unknown, tried or unbootable one bad" {
  run "$backend" get-state A
  [ "$status" -eq 0 ]
  [ "$output" = good ]
  run "$backend" get-state B
  [ "$output" = bad ]
  "$backend" set-primary B
  run "$backend" get-state B
  [ "$output" = bad ]
  boot
  run "$backend" get-state B
  [ "$output" = good ]
  run "$backend" get-state A
  [ "$output" = good ]
}

@test "set-primary of the other slot makes it bootable and the next boot, on trial" {
  set_var B unbootable
  run "$backend" set-primary B
  [ "$status" -eq 0 ]
  [ "$(var_byte B)" = 00 ]
  [ "$(cat "$nv/active")" = B ]
  [ "$(state trial)" = B ]
  [ "$(state trial-boots)" = 0 ]
  [ "$(state B)" = trying ]
  [ "$(state A)" = good ]
  grep -qx -- '-t rootfs set-active-boot-slot 1' "$nv/log"
  grep -qx "chattr +i $(var B)" "$dir/chattr.log"
  # 7 (non-volatile, boot service, runtime), then the UINT32 0
  [ "$(od -An -tx1 "$(var B)" | tr -s ' \n' ' ')" = " 07 00 00 00 00 00 00 00 " ]
}

@test "set-primary works whether nvbootctrl refuses an unbootable slot or not" {
  touch "$nv/refuse-unbootable"
  set_var B unbootable
  run "$backend" set-primary B
  [ "$status" -eq 0 ]
  [ "$(cat "$nv/active")" = B ]
}

@test "set-primary of the running slot drops a pending switch and its trial" {
  "$backend" set-primary B
  run "$backend" set-primary A
  [ "$status" -eq 0 ]
  [ "$(cat "$nv/active")" = A ]
  [ -z "$(state trial)" ]
  # Nothing to do when the running slot is the next boot already.
  : >"$nv/log"
  run "$backend" set-primary A
  [ "$status" -eq 0 ]
  run grep -q set-active-boot-slot "$nv/log"
  [ "$status" -ne 0 ]
}

@test "set-primary fails cleanly when nvbootctrl cannot switch: the running slot stays, the other is unbootable" {
  touch "$nv/fail-set-active-boot-slot"
  run "$backend" set-primary B
  [ "$status" -ne 0 ]
  [[ "$output" == *"set-active-boot-slot 1 failed"* ]]
  [ "$(cat "$nv/active")" = A ]
  [ "$(var_byte B)" = ff ]
  [ -z "$(state trial)" ]
}

@test "set-primary fails when nvbootctrl says yes and changes nothing" {
  touch "$nv/ignore-set-active"
  run "$backend" set-primary B
  [ "$status" -ne 0 ]
  [[ "$output" == *"reports slot A as the next one"* ]]
  [ "$(var_byte B)" = ff ]
  [ -z "$(state trial)" ]
}

@test "set-primary fails without the EFI variables or efivarfs" {
  rm "$(var B)"
  run "$backend" set-primary B
  [ "$status" -ne 0 ]
  [[ "$output" == *"RootfsStatusSlotB is missing"* ]]
  [ "$(cat "$nv/active")" = A ]
  IRONFLOCKOS_EFIVARS=$dir/none run "$backend" set-primary B
  [ "$status" -ne 0 ]
  [[ "$output" == *"efivarfs not mounted"* ]]
  [ "$(cat "$nv/active")" = A ]
}

@test "set-state good on the running slot verifies the boot and ends its trial" {
  "$backend" set-primary B
  boot
  [ "$(cat "$nv/retry_B")" = 2 ]
  run "$backend" set-state B good
  [ "$status" -eq 0 ]
  grep -qx verify "$nv/log"
  [ "$(cat "$nv/retry_B")" = 3 ]
  [ "$(state B)" = good ]
  [ -z "$(state trial)" ]
  [ -z "$(state trial-boots)" ]
}

@test "set-state good on a slot that does not run changes nothing" {
  run "$backend" set-state B good
  [ "$status" -eq 0 ]
  [ -z "$(state B)" ]
  run grep -qx verify "$nv/log"
  [ "$status" -ne 0 ]
}

@test "set-state good fails when nvbootctrl verify fails, and the trial goes on" {
  "$backend" set-primary B
  boot
  touch "$nv/fail-verify"
  run "$backend" set-state B good
  [ "$status" -ne 0 ]
  [[ "$output" == *"nvbootctrl verify failed"* ]]
  [ "$(state trial)" = B ]
  [ "$(state B)" = trying ]
}

@test "set-state bad on the other slot: unbootable for the firmware, the next boot stays" {
  run "$backend" set-state B bad
  [ "$status" -eq 0 ]
  [ "$(var_byte B)" = ff ]
  [ "$(state B)" = bad ]
  [ "$(cat "$nv/active")" = A ]
  # A pending switch to it goes back to the running slot (an install over it).
  set_var B normal
  "$backend" set-primary B
  run "$backend" set-state B bad
  [ "$status" -eq 0 ]
  [ "$(cat "$nv/active")" = A ]
  [ "$(var_byte B)" = ff ]
  [ -z "$(state trial)" ]
}

@test "set-state bad on the running slot hands the next boot to a slot known to boot" {
  "$backend" set-primary B
  boot
  run "$backend" set-state B bad
  [ "$status" -eq 0 ]
  [ "$(cat "$nv/active")" = A ]
  [ "$(state B)" = bad ]
  [ -z "$(state trial)" ]
  # It stays bootable for the firmware: a fallback to it boots.
  [ "$(var_byte B)" = 00 ]
}

@test "set-state bad refuses to strand the device on a slot not known to boot" {
  run "$backend" set-state A bad
  [ "$status" -ne 0 ]
  [[ "$output" == *"only one known to boot"* ]]
  [ "$(cat "$nv/active")" = A ]
  [ -z "$(state A)" ]
  # Known good once, but the firmware gave it up since.
  mkdir -p "$dir/data/rauc" && echo B=good >"$IRONFLOCKOS_TEGRA_AB_STATE"
  set_var B unbootable
  run "$backend" set-state A bad
  [ "$status" -ne 0 ]
  [ "$(cat "$nv/active")" = A ]
}

@test "slots are not changed when NVIDIA and the kernel command line disagree on the running slot" {
  running B
  run "$backend" set-state B bad
  [ "$status" -ne 0 ]
  [[ "$output" == *"rauc.slot=B"* ]]
  run "$backend" set-primary B
  [ "$status" -ne 0 ]
  [ "$(cat "$nv/active")" = A ]
  [ "$(var_byte B)" = 00 ]
}

@test "nvbootctrl failing, missing, without rootfs A/B or with output of another shape: an error, never a guess" {
  touch "$nv/fail-dump-slots-info"
  for cmd in get-primary get-current "get-state A" "set-primary B" "set-state B bad"; do
    # shellcheck disable=SC2086 # the command and its slot
    run "$backend" $cmd
    [ "$status" -ne 0 ]
    [[ "$output" == *"dump-slots-info failed"* ]]
  done
  rm "$nv/fail-dump-slots-info"
  touch "$nv/ab-disabled"
  run "$backend" get-primary
  [ "$status" -ne 0 ]
  [[ "$output" == *"rootfs A/B is not enabled"* ]]
  printf '#!/bin/sh\necho "Current rootfs slot: C"\n' >"$dir/bin/odd"
  chmod +x "$dir/bin/odd"
  IRONFLOCKOS_NVBOOTCTRL=$dir/bin/odd run "$backend" get-current
  [ "$status" -ne 0 ]
  [[ "$output" == *"unexpected output"* ]]
  IRONFLOCKOS_NVBOOTCTRL=$dir/none run "$backend" get-current
  [ "$status" -ne 0 ]
  [[ "$output" == *"nvidia-l4t-bootloader-utils"* ]]
}

@test "usage errors" {
  run "$backend"
  [ "$status" -ne 0 ]
  run "$backend" frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
  run "$backend" set-primary C
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown slot"* ]]
  run "$backend" set-state B maybe
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown state"* ]]
  run "$backend" get-state
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: tegra-rootfs-ab get-state SLOT"* ]]
  run "$backend" get-primary A
  [ "$status" -ne 0 ]
  [ ! -e "$nv/log" ]
}

# --- the health gate: tegra-slot-trial with the firmware model --------------------

# up: the timer of a boot that stays up two minutes.
up() { "$trial_tool" keep; }

@test "keep: a slot not on trial is marked good, so restarts never use it up" {
  run "$trial_tool" keep
  [ "$status" -eq 0 ]
  grep -qx 'rauc status mark-good booted' "$dir/rauc.log"
  [ "$(state A)" = good ]
  [ "$(cat "$nv/retry_A")" = 3 ]
  # Ten warm restarts without a connection: slot A stays.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    boot
    up
  done
  [ "$(cat "$nv/current")" = A ]
  [ "$(var_byte A)" = 00 ]
  [ "$(reboots)" = 0 ]
}

@test "an update that the agent marks good stays" {
  up
  install
  boot
  [ "$(cat "$nv/current")" = B ]
  : >"$dir/rauc.log"
  up
  [ "$(state trial-boots)" = 1 ]
  # On trial the boot is counted, not kept.
  [ ! -s "$dir/rauc.log" ]
  [ "$(tail -n 1 "$nv/log")" != verify ]
  # The device-agent reached the platform, after however long.
  "$backend" set-state B good
  [ -z "$(state trial)" ]
  boot
  up
  boot cold
  up
  [ "$(cat "$nv/current")" = B ]
  [ "$(reboots)" = 0 ]
  [ "$("$backend" get-primary)" = B ]
  [ "$("$backend" get-state A)" = good ]
  [ "$("$backend" get-state B)" = good ]
}

@test "an update never marked good: no time limit, and the next restart returns to the old slot" {
  up
  install
  boot
  up
  # Nothing restarts the device for want of a mark.
  [ "$(reboots)" = 0 ]
  [ "$(cat "$nv/current")" = B ]
  [ "$(state trial)" = B ]
  # The site's restart (warm here): the second boot of the trial gives it up.
  boot
  [ "$(cat "$nv/current")" = B ]
  run "$trial_tool" keep
  [ "$status" -eq 0 ]
  [[ "$output" == *"giving it up"* ]]
  grep -qx 'rauc status mark-bad booted' "$dir/rauc.log"
  [ "$(reboots)" = 1 ]
  [ "$(cat "$nv/active")" = A ]
  [ -z "$(state trial)" ]
  boot
  up
  [ "$(cat "$nv/current")" = A ]
  [ "$(reboots)" = 1 ]
  [ "$("$backend" get-state B)" = bad ]
  [ "$("$backend" get-primary)" = A ]
  # The slot it came from stays, and the next update can use B again.
  boot
  up
  [ "$(reboots)" = 1 ]
  install
  [ "$(var_byte B)" = 00 ]
  [ "$(state trial)" = B ]
}

@test "a cold restart during the trial counts as a warm one does" {
  up
  install
  boot cold
  up
  [ "$(state trial-boots)" = 1 ]
  [ "$(reboots)" = 0 ]
  # A power cut: the firmware starts its count over, the gate does not.
  boot cold
  [ "$(cat "$nv/current")" = B ]
  [ "$(cat "$nv/retry_B")" = 2 ]
  up
  [ "$(reboots)" = 1 ]
  [ "$(cat "$nv/active")" = A ]
  boot
  up
  [ "$(cat "$nv/current")" = A ]
  [ "$("$backend" get-state B)" = bad ]
}

@test "an update that does not boot: the firmware falls back after three warm boots" {
  up
  install
  for _ in 1 2 3; do
    boot
    [ "$(cat "$nv/current")" = B ]
    # The kernel panics: panic=10 reboots warm before the timer.
  done
  boot
  [ "$(cat "$nv/current")" = A ]
  up
  [ -z "$(state trial)" ]
  [ "$(state B)" = bad ]
  [ "$("$backend" get-state B)" = bad ]
  [ "$(reboots)" = 0 ]
}

@test "the trial gives up without a slot known to boot: the slot on trial stays" {
  up
  install
  boot
  up
  # Meanwhile the firmware has given up the slot the update came from.
  set_var A unbootable
  boot
  run "$trial_tool" keep
  [ "$status" -eq 0 ]
  [[ "$output" == *"slot B stays"* ]]
  [ "$(cat "$nv/active")" = B ]
  [ -z "$(state trial)" ]
  [ "$(reboots)" = 0 ]
  # Not on trial any more: kept from now on, no reboots.
  boot
  up
  [ "$(cat "$nv/current")" = B ]
  [ "$(reboots)" = 0 ]
  [ "$(cat "$nv/retry_B")" = 3 ]
}

@test "a pending update is not a fallback: the trial waits for its boot" {
  "$trial_tool" keep
  install
  # The device has not rebooted into B yet; the timer runs on A.
  up
  [ "$(state trial)" = B ]
  [ "$(cat "$nv/active")" = B ]
  [ "$(reboots)" = 0 ]
}

@test "without /data there is no trial: the slot is kept" {
  export IRONFLOCKOS_TEGRA_AB_STATE=$dir/missing/state
  run "$trial_tool" keep
  [ "$status" -eq 0 ]
  grep -qx 'rauc status mark-good booted' "$dir/rauc.log"
}

@test "keep fails when RAUC is busy, and nothing else happens" {
  touch "$dir/rauc-busy"
  run "$trial_tool" keep
  [ "$status" -ne 0 ]
  [ "$(reboots)" = 0 ]
}

@test "tegra-slot-trial: usage, and nothing without rauc.slot=" {
  run "$trial_tool"
  [ "$status" -eq 2 ]
  run "$trial_tool" frobnicate
  [ "$status" -eq 2 ]
  run "$trial_tool" deadline
  [ "$status" -eq 2 ]
  echo "console=ttyTCU0" >"$dir/cmdline"
  run "$trial_tool" keep
  [ "$status" -eq 0 ]
  [[ "$output" == *"no rauc.slot="* ]]
  [ ! -e "$dir/rauc.log" ]
}
