# Target jetson-orin

NVIDIA Jetson AGX Orin, Orin NX and Orin Nano on Jetson Linux r39.2.1 (JetPack
7.2.1) with an Ubuntu 24.04 userspace (ADR-0008; Phase 6). Work in progress:
CI builds slot A's filesystem image and the RAUC bundle, checks the root tree
and makes the flash package without a module (WP-6.2). The RAUC backend over
`nvbootctrl` and the health gate are built and unit-tested (WP-6.3), and so is
the boot firmware lane with NVIDIA's capsules (WP-6.5); nobody has run them on
a module yet. The flash kit is built and runs in CI up to the flash itself
(WP-6.4, [Flashing a module](#flashing-a-module)); nobody has flashed a module
with it yet. IronFlock signed off the licence review on 2026-11-17 (WP-6.8), and
the release publishes the Jetson files while the repository variable
`JETSON_RELEASE` is `true` ([release.md](../release.md#jetson)): the owner
decided to publish them from the next release after 0.18.0. **Not yet proven
on hardware**: no module has started the image ([Tested hardware](#tested-hardware)).
Still to come:

- the first flash, the A/B switch, the forced fallback and a capsule update
  on a module (WP-6.6);
- there is no SD image for the Orin Nano Developer Kit (the review's
  question 1): the developer kit is flashed with the flash kit too.

## Tested hardware

None yet. No module has been flashed with the flash kit or has started
IronFlockOS; CI builds the image and runs the kit up to the flash itself
([Proven, and still to prove](#proven-and-still-to-prove)). A release that
publishes Jetson files says so in its notes while `HARDWARE_TESTED=no` in
`targets/jetson-orin/target.conf` (WP-6.6 sets it).

| Board | Firmware | Date | Result | Notes |
|-------|----------|------|--------|-------|
| none | | | | |

| | |
|---|---|
| Boot | NVIDIA's UEFI firmware in QSPI starts L4TLauncher, which reads the root slot's `/boot/extlinux/extlinux.conf` and boots its `/boot/Image` with `/boot/initrd` (see below) |
| A/B | NVIDIA's rootfs A/B: root slots `APP` and `APP_b`, switched through `nvbootctrl -t rootfs` by a RAUC `custom` backend (`/usr/lib/ironflockos/tegra-rootfs-ab`); NVIDIA's firmware falls back after three warm boots nobody verified (see below) |
| Distribution | `ubuntu-noble` (`distros/ubuntu-noble`): ports.ubuntu.com, Docker's noble repository |
| Kernel | `nvidia-l4t-kernel` 6.8.12 (`6.8.12-1021-tegra`) with NVIDIA's out-of-tree modules; Orin's GPU driver is `nvgpu` (`-nvgpu` packages; `-openrm` is Thor's) |
| GPU in containers | `nvidia-container-toolkit` 1.19.1 from NVIDIA's `common` repository; Docker's `nvidia` runtime (`ironflock bake` adds it); `nv-load-gpu-libs` links the board's `libcuda` and writes the container CSVs on each boot |
| Consoles | `ttyTCU0`, 115200 8N1 (the debug header), and the display (`tty0`) |
| Slot size | 8 GiB (`base`); only the base variant |
| Disk | NVIDIA's NVMe layout for rootfs A/B, plus `data` (see below); written by NVIDIA's flash tools |
| Image | `<image-id>-<version>.rootfs.ext4.zst`, slot A's filesystem (APP), and the bundle `<image-id>-<version>.raucb`; the flash kit `ironflockos-jetson-flash-kit-<version>.tar.gz` writes it to a module; `NVIDIA-LICENSE.txt` next to them in a release ([release.md](../release.md#jetson)) |

## Packages and pins

NVIDIA's repositories `https://repo.download.nvidia.com/jetson/{common,som}`,
suite `r39.2`, go into the image's sources (`nvidia-l4t.sources`) below Ubuntu:
for a package both have, Ubuntu's version wins. The repositories carry several
L4T releases, so `ironflockos-l4t.pref` holds every `nvidia-l4t-*` binary at
`L4T_PACKAGE_VERSION`, the kernel's binaries at `L4T_KERNEL_VERSION` and the
container toolkit at `L4T_CONTAINER_TOOLKIT_VERSION` (all in `target.conf`). The
build also pins the packages `targets/jetson-orin/packages` lists on mmdebstrap's
command line, so a version NVIDIA withdraws fails the build.

The repositories' key is `targets/jetson-orin/apt/jetson-ota-public.asc`
(fingerprint `3C6D1FF3100C8C3ABB0869C0E6543461A9996195`, checked by the unit
tests). It is the file `https://repo.download.nvidia.com/jetson/jetson-ota-public.asc`
serves: the key block of the file `nvidia-l4t-apt-source` 39.2.1 ships, without
that file's licence header (dearmored bytes identical). It signs both
repositories' `InRelease`.

`nvidia-l4t-bootloader` is in: its UEFI capsules of the QSPI firmware are what
an OS update brings to the boot chain ("Boot firmware updates" below). Its
post-install script, which would stage a capsule through fwupd, does nothing
in the build (the marker below).

Left out on purpose:

- `nvidia-l4t-extlinux`: the build writes `extlinux.conf`.
- `nvidia-l4t-apt-source`: the build writes the sources.
- `nvidia-l4t-configs`: desktop, Weston and cloud-init settings.

NVIDIA's packages check the board they are installed on and update its boot
firmware unless `/opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall`
exists. The build creates the marker before the packages go in and removes it
afterwards, as NVIDIA's own image build does.

## Services

IronFlockOS masks two of NVIDIA's boot-time services:

- `nv-l4t-bootloader-config` updates the QSPI firmware by itself, and runs
  `nvbootctrl verify` at every boot, which marks the boot successful. It would
  end the trial of every updated slot before the device-agent has reached the
  platform, and defeat the fallback. IronFlockOS's lane 2 updates the QSPI
  firmware (`tegra-capsule`, below); the health gate below verifies the boot.
- `nv-rootfs-validation-config` runs before it, and reboots when a user
  validation script (`/usr/sbin/user_rootfs_validation.sh`) fails: at every
  boot, without a bound. IronFlockOS has no such script.

Masking `nv-l4t-bootloader-config` also leaves out what else it does at boot:
writing NVIDIA's platform spec variables (`TegraPlatformSpec`,
`TegraPlatformCompatSpec`, which capsule updates check), the board spec in
`/etc/nv_boot_control.conf`, mounting the ESP (the image's `/etc/fstab` does)
and renaming old kernel partitions. `tegra-capsule` writes the two spec
variables, by NVIDIA's rule, when it stages a capsule, and `tegra-board-conf`
puts the module's `/etc/nv_boot_control.conf` in place at boot ("Boot
firmware updates", "The module's nv_boot_control.conf").

NVIDIA's `nvidia-l4t-init` also sets the hardware watchdog to 120 seconds
(`/etc/systemd/system.conf.d/watchdog.conf`), which comes after IronFlockOS's
60 seconds and wins. Either way a hung system is reset.

The rest of `nvidia-l4t-init` stays enabled as NVIDIA presets it: GPU libraries,
display modules, power model, fan control.

There is no `repart.d` on this target: NVIDIA's flash tools write the whole
layout, the `data` partition included.

## Names at login

The image is IronFlockOS, based on Ubuntu 24.04. It ships Canonical's packages
unchanged and shows IronFlockOS's names where Ubuntu's `base-files` puts
Ubuntu's (WP-6.8; [jetson-licence-review.md](../jetson-licence-review.md),
point 10):

| File | Says |
|------|------|
| `/etc/issue` (the login prompt) | `\S \n \l`: `PRETTY_NAME` of os-release, the host and the terminal, for example `IronFlockOS 0.18.0 (jetson-orin, base) ironflockos ttyTCU0`; the same on every target (`overlay/etc/issue`) |
| `/etc/issue.net` | `IronFlockOS` |
| `/etc/motd` | IronFlockOS's banner (`overlay/etc/motd`) |
| `/etc/lsb-release` | `DISTRIB_ID=IronFlockOS`, `DISTRIB_RELEASE=24.04`, `DISTRIB_CODENAME=noble`, `DISTRIB_DESCRIPTION="IronFlockOS <version>, based on Ubuntu 24.04"` (`build/branding.sh`) |
| `/usr/lib/os-release` | IronFlockOS's (`build/osrelease.sh`), `ID_LIKE="ubuntu debian"`, no `UBUNTU_*` field and no Ubuntu URL |

`lsb_release` (noble's `lsb-release` 12.0) answers from os-release, not from
`/etc/lsb-release`: `-i` says `IronFlockOS`, `-d` the `PRETTY_NAME`, `-r` the
IronFlockOS version, and `-c` says `n/a`, as the image's os-release has no
`VERSION_CODENAME`. The only reader of `DISTRIB_ID` in the image is NVIDIA's
`nvidia-bug-report-jetson.sh`, which prints an `apt-get` hint when it says
`Ubuntu`.

Gone: `/etc/legal` (Ubuntu's notice at the first login), Ubuntu's
`update-motd.d` scripts (`00-header`, `10-help-text` with Canonical's links,
`50-motd-news`), and the logos in `/usr/share/pixmaps`. `motd-news.timer` and
`motd-news.service` are masked, so nothing fetches `motd.ubuntu.com`.
`ubuntu-pro-client` is not installed: nothing the image lists depends on it,
and Recommends are not installed. Kept as Ubuntu's: the package names and
their `ubuntu` version strings, `/etc/dpkg/origins/ubuntu`, the apt sources
and Ubuntu's archive keyring.

## Booting a slot

Each root slot boots with its own `/boot/extlinux/extlinux.conf`, rendered
from `targets/jetson-orin/boot/extlinux.conf`. NVIDIA's initrd mounts the
last `root=` on the command line (`/dev/…`, `PARTUUID=` or `UUID=`). Under
rootfs A/B, NVIDIA's `flash.sh` gives each slot its own command line, with
`root=PARTUUID=` of `APP` or `APP_b`, and L4TLauncher does not rewrite it.
IronFlockOS does the same:

- The image's file names slot A: `root=PARTUUID=` of `APP`, derived from the
  image id (`uuid_for rootfs-a`, which the flash package gives `APP`), and
  `rauc.slot=A`.
- RAUC writes one image into either slot, so `rauc-post-install` runs
  `/usr/lib/ironflockos/tegra-extlinux` on the slot it has just written. That
  points the slot's `APPEND` line at its own PARTUUID and bootname, as
  `rpi-cmdline` does for the Pi's `cmdline.txt`.

The rest of the command line is NVIDIA's for the Orin modules (`TEGRA_CMDLINE`
in `target.conf`, from `CMDLINE_ADD` of `p3701.conf.common` and
`p3767.conf.common`). L4TLauncher fills in `${cbootargs}`.

## A/B with nvbootctrl

With rootfs A/B, NVIDIA's UEFI firmware (L4TLauncher, `L4TRootfsValidation.c`
in NVIDIA's edk2-nvidia, branch `r39.2.1-updates`) decides which root slot
boots. Slot A is `APP`, slot B `APP_b`; NVIDIA numbers them 0 and 1. What it
does:

- The root slot is tied to the boot chain of the QSPI firmware
  (`RootfsRedundancyLevel` 1): switching the slot switches the chain, through
  the variable `BootChainFwNext` and a reset.
- It counts boots in a scratch register of the PMC: two bits of tries per
  slot, the current slot, and a magic number. A cold boot (power on) and a
  switch of the boot chain start the register over, with
  `RootfsRetryCountMax` (3) tries for each slot that is not unbootable. Every
  boot takes one try off the slot it starts. A warm reboot (`reboot`, a kernel
  panic with `panic=10`, the hardware watchdog) keeps the register; that the
  watchdog's reset is warm is still to prove on a module.
- A slot without tries is marked unbootable (EFI variable
  `RootfsStatusSlotA`/`B` = `0xFF`), and the firmware switches to the other
  slot if that one has tries left. When both are unbootable it starts NVIDIA's
  recovery kernel, from which the device does not come online.
- `nvbootctrl verify` clears the register: the slot that runs has its three
  tries again at the next boot.

So the firmware falls back only after three boots of a slot, all warm, that
nobody verified, and a power cut resets the count. The backend and the health
gate below make an updated slot follow the EFI targets' rule instead.

### The backend

`/usr/lib/ironflockos/tegra-rootfs-ab` answers RAUC's custom backend
protocol, like the Raspberry Pi's `rpi-tryboot`:

| RAUC asks | The backend |
|-----------|-------------|
| `get-current` | `Current rootfs slot` of `nvbootctrl -t rootfs dump-slots-info` |
| `get-primary` | `Active rootfs slot` of the same: the slot the next boot starts |
| `get-state X` | `good` for the slot that runs; for the other `good` only if it was marked good while it ran (the backend's state file) and the firmware has not marked it unbootable since; else `bad` |
| `set-state X good` | on the slot that runs: `nvbootctrl verify`, the slot is good and its trial ends. On the other slot: nothing (only a slot that runs is vouched for) |
| `set-state X bad` | on the other slot (RAUC does this before it writes a slot): the next boot is the running slot's, and the slot is marked unbootable for the firmware, as NVIDIA's own update engine does. On the running slot: the next boot goes to the other slot, only if that one is known good; the running slot stays bootable for the firmware |
| `set-primary X` | on the other slot (RAUC does this after writing it): the slot is made bootable (`RootfsStatusSlotX` = 0), `nvbootctrl -t rootfs set-active-boot-slot N`, and the slot is on trial. On the running slot: a pending switch to the other slot is dropped |

The backend's own state is `/data/rauc/ironflockos-tegra-rootfs-ab.state`:
`A=` and `B=` (`good`, `bad`, `trying`), `trial=` (the slot on trial) and the
trial's counters.

Every answer comes from `nvbootctrl`'s output or the backend fails, with exit
code 1 and the reason on stderr; it never guesses:

- `nvbootctrl` missing or failing, output of another shape, or rootfs A/B not
  enabled (`RootFS A/B is not enabled.`);
- `set-primary`: efivarfs not there, the `RootfsStatusSlot` variable missing,
  `set-active-boot-slot` failing, or `nvbootctrl` not reporting the slot as
  the active one afterwards. The slot is then marked unbootable again and the
  running slot stays the next boot; RAUC's install fails;
- `set-state X bad` of the running slot when the other slot is not known
  good: the device would have no slot known to boot;
- `set-state` and `set-primary` when `nvbootctrl`'s current slot is not the
  `rauc.slot=` of the kernel command line: RAUC's target could be the slot
  that runs;
- `set-state X good` when `nvbootctrl verify` fails: the trial goes on.

`RootfsStatusSlotA`/`B` are written as efivarfs files: 4 bytes of attributes
(7: non-volatile, boot service and runtime access, as the firmware makes
them), then the 32-bit value; `chattr -i` before and `chattr +i` after, as
NVIDIA's own scripts do; read back afterwards. The backend writes them itself
because `nvbootctrl` r39.2.1 has no command for it (no
`set-slot-as-unbootable`, no `mark-boot-successful`; see "What nvbootctrl
r39.2.1 does" below).

### The health gate

The device-agent marks the booted slot good once it has reached the platform
(`rauc status mark-good`, device-agent 1.6.0), as on the other targets. On
Jetson that is `nvbootctrl verify`. The trial of an updated slot follows the
EFI targets' rule (`docs/build.md`, "Boot and A/B"; decided by Marko on
2026-11-16): the slot gets one boot. During that boot the agent has no time
limit, and nothing restarts the device because the agent has not marked the
slot good. If the device restarts for any reason, warm or cold, before the
mark, the slot the update came from boots next.

`ironflockos-tegra-keep.timer` runs `/usr/lib/ironflockos/tegra-slot-trial
keep` two minutes after `multi-user.target`:

- On a slot that is not on trial (a fresh flash, a slot the agent marked good,
  the slot an update came from), it marks the slot good through RAUC.
  Restarts without a connection never use it up: unlike GRUB, which starts
  over with a good slot when all were tried, NVIDIA's firmware ends in the
  recovery kernel.
- On the slot on trial, it counts the boot (`trial-boots`). On the second
  counted boot it marks the slot bad through RAUC, which hands the next boot
  to the slot the update came from, and reboots once. If RAUC refuses (that
  slot is not known good), the trial ends and the slot on trial stays.
- After the firmware fell back from a trial, it ends the trial; the slot
  tried reads as bad.

The one difference from the EFI targets: GRUB skips a tried slot before its
kernel starts, while the Jetson boots the tried slot once more, for two
minutes, and then restarts into the old one. NVIDIA's firmware cannot be told
to skip it. A slot that cannot boot at all never reaches the timer; it still
falls back through the firmware's three warm boots (`panic=10`, the hardware
watchdog).

The cases:

| Case | What happens |
|------|--------------|
| The updated slot does not boot (kernel panic, root not mounted, a hang) | `panic=10` or the hardware watchdog reboots warm; after three boots the firmware marks the slot unbootable and boots the slot the update came from, which is kept. The agent there reports the rollback |
| The updated slot boots, the agent never marks it good | the device stays up on the new slot; nothing restarts it. At its next restart, warm or cold, the new slot boots once more for two minutes, is marked bad, and the device restarts into the slot the update came from |
| No network at all after an update | as above: the device stays up on the new slot until its next restart, then returns to the old one and stays there, kept by the timer. The platform can offer the update again later |
| No network on a slot that is not on trial (a fresh flash, a proven slot) | nothing is rebooted; the slot is kept two minutes after every boot and never falls back by counting |
| A power cut during the trial | counts as any restart: the next boot is the trial's second, which returns to the old slot. The firmware's own count starts over at a cold boot; the gate's count does not |
| A power cut while RAUC writes the slot | the slot was marked unbootable before the write and the running slot is still the next boot: the device boots the old slot |
| The agent marks the slot good | `nvbootctrl verify`; the trial ends and the slot stays |

A device never loops: the gate restarts a device at most once per trial, to
return to the old slot, and never restarts a slot that is not on trial.

### What nvbootctrl r39.2.1 does

Nobody could run the tool on a module for this work. What the backend relies
on, and where it comes from:

| Fact | Source |
|------|--------|
| `nvbootctrl` is `/usr/sbin/nvbootctrl` in `nvidia-l4t-bootloader-utils` 39.2.1-20260806224157, an arm64 ELF binary | the package, unpacked |
| commands: `get-number-slots`, `get-current-slot`, `set-active-boot-slot SLOT` (zero-based), `dump-slots-info`, `verify`, `verify-bl`, `is-rootfs-ab-enabled` (says "not implemented"); option `-t bootloader\|rootfs`. No `mark-boot-successful`, `set-slot-as-unbootable` or `get-suffix` (older releases had them) | the binary's usage text (`strings`) |
| `-t rootfs dump-slots-info` prints `Current rootfs slot: %s`, `Active rootfs slot: %s`, `num_slots: %d`, and per slot `slot: %d,             retry_count: %d,             status: %s` with `normal` or `unbootable`; `RootFS A/B is not enabled.` without rootfs A/B | the binary's format strings; the slot letters as NVIDIA's `nv-l4t-bootloader-update.sh` reads the bootloader's line with the same format (`awk '{print $4}'` gives `A` or `B`) |
| the variables it reads and writes: `RootfsStatusSlotA`/`B`, `RootfsRetryCountMax`, `RootfsRedundancyLevel`, `BootChainFwCurrent`, `BootChainFwNext`, `BootChainFwStatus`, `BootChainOsCurrent`, GUID `781e084c-a330-417c-b678-38e696380cb9`; `chattr -i`/`+i` around writes; the scratch register fields `rootfs_retry_count_a`/`_b`, `rootfs_current`, `rootfs_sr_magic` | the binary's strings |
| status values `0` normal, `0xFF` unbootable; attributes non-volatile, boot service and runtime access; the counting, the fallback and the recovery kernel as described above | edk2-nvidia `r39.2.1-updates`: `L4TRootfsValidation.c`, `NVIDIAConfiguration.h`, `BootChainDxe.c`, `L4TLauncher.c` (BSD-2-Clause-Patent, read on GitHub) |
| the retry count is in a scratch register, initialised at cold boot, cleared by `nvbootctrl verify` (through `nv-l4t-bootloader-config`) | NVIDIA's developer guide, "Root File System Redundancy" (r36.4 and r38.2) |
| NVIDIA's update engine marks a slot unbootable before it writes it, then sets it active | `nv_update_engine`'s strings (`nvidia-l4t-tools`) |

Inferred, not proven: the exit codes (0 on success), the output of `set-active-boot-slot`, whether it makes an unbootable slot bootable itself or refuses it (the backend writes the variable first, so either works), that `set-active-boot-slot` sets `BootChainFwNext` and that the active slot then reads as that slot. The unit tests (`test/unit/tegra-rootfs-ab.bats`) run against a fake `nvbootctrl` with fixtures in this format (`test/unit/fixtures/nvbootctrl`, written by hand; nothing in them is NVIDIA's).

### To prove on a module (WP-6.6)

- `nvbootctrl -t rootfs dump-slots-info` prints what the fixtures hold, and
  `get-current-slot` agrees with `rauc.slot=`.
- The flash kit's QSPI run (`ROOTFS_AB=1`, see [Flash package](#flash-package))
  gives the firmware `RootfsRedundancyLevel` 1, and `RootfsStatusSlotA`/`B`
  exist after the first boot (the firmware makes them, or the backend's
  `set-primary` fails and says so). CI only records whether the QSPI images
  name `RootfsRedundancyLevel`.
- efivarfs is mounted read-write and the backend's writes of
  `RootfsStatusSlot` reach the firmware; `nvbootctrl` works with
  IronFlockOS's kernel and without `/etc/nv_boot_control.conf` (it falls back
  to the device tree for the chip id). The flash package does not put the
  file into the slots (see [Open points](#open-points)).
- `systemctl reboot`, a kernel panic and the hardware watchdog are warm
  resets that keep the scratch register; a power cut is cold.
- The A/B switch: `rauc install`, reboot, the agent marks the slot good,
  `rauc status` shows it booted and primary.
- The forced fallback: install a bundle whose slot panics (for example with
  `init=/bin/false` in its `extlinux.conf`); after three boots the module is
  back on the old slot, and `rauc status` shows the new one bad. And a slot
  that boots but has no network: it stays up; after a restart (warm, and once
  cold) it is up for two minutes, then the module restarts into the old slot.

## Boot firmware updates

The QSPI firmware (MB1, MB2, BPMP, SPE, RCE, OP-TEE, TF-A, UEFI) is lane 2 of
[ADR-0007](../adr/0007-update-mechanism-rauc-and-firmware-lanes.md): it
travels with the OS release. The capsule is NVIDIA's own, unchanged, from
`nvidia-l4t-bootloader` at the pinned version (licence review, point 6); none
is generated (`l4t_generate_soc_capsule.sh` waits for WP-6.8's legal check).
Nobody has run this on a module yet (WP-6.6).

### How NVIDIA's firmware applies a capsule

From edk2-nvidia, branch `r39.2.1-updates` (`PlatformBm.c`, `TegraFmp.c`,
`BootChainDxe.c`, `FwPackageLib.c`, `FmpVersionLibPartition.c`,
`L4TRootfsValidation.c`; BSD-2-Clause-Patent), and NVIDIA's own scripts in
`nvidia-l4t-bootloader` and `nvidia-l4t-bootloader-utils` 39.2.1:

- At boot, before the OS, UEFI looks for a capsule on the ESP when bit 2 of
  `OsIndications` is set (capsule on disk). It marks the running boot chain
  good, takes the capsule and resets, and the next start processes it, before
  anything else of the boot chain switch.
- The capsule writes the boot chain that does not run (it marks it bad
  first, writes and verifies every image, then good) and then makes it the
  active chain in the BR-BCT, and resets cold. It never writes the running
  chain.
- With rootfs A/B (`RootfsRedundancyLevel` 1) the root slot is the boot
  chain: chain A boots `APP`, chain B `APP_b`. So the capsule **is** the switch
  of the root slot: the reboot that applies the capsule boots the other root
  slot on the firmware just written. There is no separate switch.
- While `BootChainFwNext` or `BootChainFwStatus` exists, the firmware
  cancels the capsule (last attempt status `0x1813`) and with it the pending
  switch of `BootChainFwNext`. `nvbootctrl -t rootfs set-active-boot-slot`
  sets `BootChainFwNext`, and no firmware code deletes `BootChainFwStatus`
  after a switch. So with a capsule nobody may ask for a switch through
  `nvbootctrl`, and an old status has to go.
- The firmware picks the capsule's images by the board: each image carries
  a spec such as `3767-000-0003--1-0-jetson-orin-nano-devkit-`, matched field
  by field against `TegraPlatformCompatSpec` (an empty field matches any). An
  unset variable matches no board image, and the capsule is rejected (`0x1807`,
  image not in package) before anything is written.
  `nv-l4t-bootloader-config` sets the variable at every boot; IronFlockOS
  masks it.
- The firmware of both chains is in `SystemFwVersions` (set by the firmware at
  every boot from the chains' VER partitions: UINT32 A, UINT32 B, as
  `0xRRRRMMmm`, 39.2.1 = `0x270201`); the running one also in the ESRT
  (`/sys/firmware/efi/esrt/entries/entry0/fw_version`) and in DMI's
  `bios_version`. The ESRT's `last_attempt_version` and `last_attempt_status`
  say how the last capsule went.
- A capsule must not be older than the firmware's lowest supported version.
  NVIDIA's capsules of 39.2.1 give their own version as the lowest (their FMP
  payload header), so after one of them nothing older is taken (inferred from
  edk2's FmpDxe, which keeps the last capsule's lowest version). NVIDIA's own
  installer path refuses capsules on firmware older than R38: across
  generations a module is flashed.

NVIDIA's `nvidia-l4t-bootloader` ships capsules for NVIDIA's carrier boards
only, picked by the board name in `COMPATIBLE_SPEC` of
`/etc/nv_boot_control.conf`:

| Capsule | Boards (the specs inside) |
|---------|---------------------------|
| `TEGRA_BL_3767.Cap` | Orin NX and Orin Nano (P3767 SKUs 0000 to 0005) on the Orin Nano developer kit carrier (`jetson-orin-nano-devkit`) |
| `TEGRA_BL_3767_super.Cap` | the same in the developer kit's "super" configuration |
| `TEGRA_BL_3767_nanoe8gb.Cap`, `_nanoe8gb_super.Cap` | `jetson-orin-nanoe8gb-devkit` |
| `TEGRA_BL_3701_agx.Cap`, `_000.Cap`, `_agx_super.Cap`, `_agx_ind.Cap` | AGX Orin developer kit (fab 300, fab 000 and older, super, industrial) |

A module on another carrier board gets no capsule from NVIDIA; for it the
lane needs a generated one (WP-6.8 first).

### The module's nv_boot_control.conf

`/etc/nv_boot_control.conf` names the module: `TNSPEC` (board id, fab, SKU,
revision, fuse level, chip revision, the board configuration flashed, the
root device), `COMPATIBLE_SPEC` (the same with NVIDIA's normalisation: for an
Orin Nano 8GB on the developer kit `3767--0003--1--jetson-orin-nano-devkit-`)
and `TEGRA_CHIPID` (`0x23`), and a few deprecated or IGX-only lines.
`nvbootctrl` reads the chip id from it (else the device tree);
`tegra-capsule` chooses the capsule by `COMPATIBLE_SPEC` and writes the
platform spec variables from it.

NVIDIA's `flash.sh` writes it for the module it flashes. The device cannot
make all of it by itself: board id, SKU, fab and revision are in the module's
EEPROM, but the board configuration (`jetson-orin-nano-devkit` or `-super`,
which changes the firmware in the capsule), the fuse level and the root
device are the flash's. NVIDIA's own boot script (`nv-l4t-bootloader-config`)
only refreshes the EEPROM's fields of a file that is already there, and
exits without one. Run without `-l` and `-v` it would also rename partitions,
rewrite `/etc/fstab` when the ESP is not mounted, and update the QSPI firmware
by itself on an Orin Nano developer kit (SKU 5); IronFlockOS keeps it masked.

So the flash kit puts the file `flash.sh` wrote onto the package's ESP, next
to the `.flock` ("Flashing a module", step 8), and
`ironflockos-tegra-board-conf.service` runs
`/usr/lib/ironflockos/tegra-board-conf` at every boot, before the capsule
report and the health gate: when the ESP holds an `nv_boot_control.conf` of
NVIDIA's shape (text of at most 4 KiB naming `TNSPEC`, `COMPATIBLE_SPEC` and
`TEGRA_CHIPID` once each) and `/etc` has none or another, it copies it to
`/etc`. The slot images carry none: they are the release's, for every module.
The ESP outlives OS updates, and a new flash brings a new file. Without a
file on the ESP the device runs as before, `/etc`'s stays, and the journal
says that no capsule can be staged. It never fails or holds the boot.
Computing the file on the device from the EEPROM (NVIDIA reads it over I2C,
bus 0, address 0x50, bytes 25 to 41 on T234) could replace the ESP's copy
later, for modules flashed some other way; it would still lack the board
configuration.

### What an OS update does

The lock-step rule: the firmware of the chain of slot X is the L4T release
slot X was built for. The flash writes both chains from the BSP pin
(`bsp.conf`), and an update keeps the rule for the slot it writes. After RAUC
has written the other slot, `rauc-post-install` carries
`/etc/nv_boot_control.conf` into it and runs
`/usr/lib/ironflockos/tegra-capsule stage <slot> <mount>`, before the switch:

| The chain of the new slot | Window | What happens |
|---------------------------|--------|--------------|
| has the slot's L4T release (`/etc/nv_tegra_release` of the slot) and is not marked failed | any | no capsule; RAUC switches the slot through `nvbootctrl`, as before |
| another release, unknown, or failed | open, and a capsule can be staged | NVIDIA's capsule for this board, from the new slot's `/opt/ota_package/t23x`, is staged (below); the capsule switches the slot |
| an older release of the same generation (39.2.0 for a 39.2.1 slot) | closed, or no capsule can be staged | no capsule; RAUC switches the slot through `nvbootctrl`, and the slot runs on the older firmware until an OS update inside a window brings the firmware up; the journal says so |
| another generation (39.1 for 39.2), unknown, or failed | closed, or no capsule can be staged | the install fails with the reason: the slot is not switched to, the device stays on the slot it runs |
| newer than the slot, a lowest supported version (ESRT) above the slot's release, another L4T release (R36 for R39), or the slot names no release | any | the install fails: no capsule goes back, and across releases a module is flashed |

A **generation** is an L4T release and major number: 39.2.x is one, 39.3.x the
next (NVIDIA's `0xRRRRMMmm` without the minor byte).

Staging, as NVIDIA's `nv_bootloader_capsule_updater.sh` and the package's
post-install script do it:

1. `BootChainFwNext` and `BootChainFwStatus` are deleted (above);
2. `TegraPlatformSpec` is written from `TNSPEC` if it does not exist, and
   `TegraPlatformCompatSpec` from `COMPATIBLE_SPEC` whenever it differs
   (attributes 7, the string, `chattr +i`): NVIDIA's rule, but only here, so
   nothing verifies the boot;
3. the capsule goes to `EFI/UpdateCapsule/` on the ESP under its own name
   (`TEGRA_BL_3767.Cap`), written to a temporary name and renamed; NVIDIA's
   L4TLauncher of the same release to `EFI/BOOT/BOOTAA64.efi`;
4. `OsIndications` is written as NVIDIA writes it: attributes 7, the UINT64 4
   (bit 2, file capsule delivery);
5. the backend's state on `/data` names the slot, the capsule and the boot.

The backend (`tegra-rootfs-ab set-primary`) then sees the capsule: it makes
the slot bootable and puts it on trial as always, but leaves the switch to the
capsule; `get-primary` names that slot until the restart. RAUC writing the
slot again (`set-state bad`) or keeping the running slot withdraws the capsule
(file and bit). A capsule never outlives the restart it was staged for.

The capsule is chosen by the firmware's own rule: of the new slot's
`TEGRA_BL_<board id>*.Cap`, the one whose board specs match `COMPATIBLE_SPEC`
field by field. None or more than one: no capsule for this board.

Reasons a needed capsule is not staged (the journal, and RAUC's error when
the install fails, name it):

- no maintenance window open, or a window file it does not understand
  (below);
- no `COMPATIBLE_SPEC` in `/etc/nv_boot_control.conf`, or no capsule for this
  board in the new slot (every carrier board but NVIDIA's developer kits);
- the ESP is not mounted at `/boot/efi`, or has less room than the capsule,
  L4TLauncher and 1 MiB (NVIDIA's capsules of 39.2.1 are 12 to 52 MB);
- `OsIndicationsSupported` without bit 2;
- writing the platform spec variables, the capsule, L4TLauncher or
  `OsIndications` failed (what was written of the capsule is taken off the
  ESP again; if that fails too, the install fails).

Within one generation, on older firmware, each of them leads to the switch
without the capsule; otherwise to a failed install. Without efivarfs the
chains' firmware cannot be read, so the version is unknown and the install
fails.

Because a capsule writes only the chain it switches to, the chain of the slot
an update leaves keeps its old firmware: that is the rollback. After a new
L4T release, the next update into the other slot needs the window again, to
bring that chain up too.

The firmware follows only with an OS update: a capsule is staged by an
update's hook, never on its own. A slot that took a minor update without the
window runs on the older firmware (`report`: `firmware-behind=yes`) until the
next OS update inside a window, and that update brings up only the chain of
the slot it goes to; the other chain follows with the update after it.

**A new slot on old firmware.** NVIDIA makes no compatibility statement for
an L4T root filesystem on the boot firmware of another minor release. The
kernel boots with the device tree the firmware hands over (the image's
`extlinux.conf` names no `FDT`), so firmware and kernel come from different
releases there. NVIDIA's own flows never run that way for long: apt
upgrades stage the capsule before the reboot, and its developer kit's SD
image updates the QSPI firmware on its first boot when it is older (which
shows that a newer minor release does start on older firmware, at least that
far). Within one generation IronFlockOS relies on that (decided by Marko
on 2026-11-16): without a window, a slot of 39.2.1 is switched to on a
chain of 39.2.0. If it does not boot there, NVIDIA's firmware counts three
tries and falls back to the old slot ("The health gate"); if it boots and
the agent never marks it good, the health gate takes the device back. Across
generations IronFlockOS does not switch without the capsule: the update
waits for a window.

### The maintenance window

A device setting from the platform, off by default:
`/etc/ironflockos/maintenance.conf`, which links to
`/data/ironflockos/maintenance.conf`. Nothing in the platform writes it: the
maintenance window is a feature of the whole platform and gets its own plan
(Marko, 2026-11-17). Until then this file is the image's provisional side
only, and that plan may replace it. Without the file no capsule is ever
staged. What the image reads today:

```ini
boot-firmware=yes    # yes: an OS update may update the boot firmware; no (default)
until=1763625600     # optional: the window ends then, in seconds since 1970 (UTC)
```

- No file, `boot-firmware=no`, a time past `until`, or a file it does not
  understand (another key, a value twice, more than 4 KiB): the window is
  closed, and the journal says why.
- It is read when an OS update is installed. A capsule staged inside the
  window is applied at the next restart, which `perform_os_update` does right
  after the install; so the platform opens the window, runs the update with
  its restart, and closes the window by removing the file. A staged capsule
  that the firmware has not taken by the next restart is removed then.
- A factory reset removes it with the rest of `/data/ironflockos`.
- Updates that need no firmware do not read it. Without the window, an
  update to a newer release of the same generation goes ahead without the
  firmware (the slot runs on the older firmware, `firmware-behind=yes`); one
  that needs another generation's firmware fails. So the platform opens a
  window when `firmware-behind=yes`, or before an update to another
  generation, and the next OS update brings the firmware.

### After the restart

`ironflockos-tegra-capsule.service` runs `tegra-capsule report` at every
boot, before the health gate's timer. For a capsule staged in an earlier
boot it decides, in this order:

| Result | When |
|--------|------|
| `applied` | the device runs the capsule's slot, and the ESRT's firmware version is the capsule's; or the ESRT's last attempt was the capsule's version with status 0 and the device fell back afterwards |
| `not-processed` | the capsule is still on the ESP |
| `failed` | otherwise; with the ESRT's last attempt status when it is the capsule's version |

It then removes any capsule from the ESP and bit 2 from `OsIndications`, and
for a result other than `applied` marks the capsule's slot bad through RAUC
(`rauc status mark-bad other`): the slot was written for firmware it did not
get, so neither the firmware nor RAUC may switch to it. The result is in the
journal and in `/run/ironflockos/boot-firmware`, rewritten at every boot,
which the device-agent can read:

```ini
slot-release=39.2.1           # the running slot's L4T release (/etc/nv_tegra_release)
firmware-behind=no            # yes: its chain's firmware is older; unknown
slot-a-firmware=39.2.1        # SystemFwVersions, or unknown
slot-b-firmware=39.2.1
running-firmware=39.2.1       # the ESRT
last-attempt-version=39.2.1
last-attempt-status=0         # the ESRT's; NVIDIA's codes from 0x1800 (6144)
capsule-result=applied        # of the last capsule: applied, not-processed, failed, or empty
capsule-slot=B
capsule-version=39.2.1
```

`report` never fails the boot.

### When it fails

| Case | What happens |
|------|--------------|
| The firmware rejects the capsule (wrong board spec, version below the lowest supported, cancelled, bad signature) | nothing is written; the chain and the root slot stay; the device boots the old slot on the old firmware. `report`: `failed`, the slot is marked bad. The health gate finds the trial's slot not booted and keeps the old one |
| A write or verify of the capsule fails | the inactive chain stays marked failed; the active chain is untouched and boots the old slot. As above; the next update into that slot needs a capsule again (the chain reads as failed) |
| Power lost while the capsule is written | the active chain is untouched (the capsule writes only the other); the next start boots it, and the capsule is lost or taken again. Field reports of boot loops after such a power loss on r36.4.0 are why the window exists; to prove on r39.2.1 (WP-6.6) |
| The new chain does not start (MB1, MB2 or UEFI fails) | NVIDIA's boot ROM and MB1 are to fall back to the other chain after failed starts (bootloader redundancy as NVIDIA's developer guide describes it; the code is closed and was not checked); that chain boots the old slot. `report`: `failed`. UEFI marks a chain good as soon as it reaches its boot manager, so this covers only firmware that fails before that |
| The new chain starts, the new slot does not boot | L4TLauncher counts three warm boots, marks the slot unbootable and switches through `BootChainFwNext` to the old chain, with the old firmware and the old slot. `report`: `applied`, fell back |
| The new slot boots, the agent never marks it good | the health gate as above ("The health gate"): the old slot, through `BootChainFwNext`, on its old chain |
| A minor update without the window: the new slot does not boot on the older firmware of its chain | as an update that does not boot: L4TLauncher counts three warm boots and falls back to the old slot, with its chain; the health gate marks the trial bad. No firmware was written |
| A minor update without the window: the new slot boots on the older firmware | it runs; `report` says `firmware-behind=yes` at every boot until an OS update inside a window brings the firmware |
| Power lost after staging, before RAUC's switch | the capsule applies and switches to the new slot, which RAUC marked unbootable before writing it: L4TLauncher switches back to the old chain and slot at once |

No case loops: the firmware's own fallbacks are bounded, `report` restarts
nothing, and the health gate restarts at most once per trial.

### To prove on a module (WP-6.6)

- `SystemFwVersions`, the ESRT and DMI read as above on a flashed module, both
  chains 39.2.1; the flash writes `TegraPlatformCompatSpec`, or `stage` writes
  it; `flash.sh` writes `nv_boot_control.conf` in a real flash as in the CI's
  offline one, with the `COMPATIBLE_SPEC` NVIDIA's `nv-l4t-bootloader-config`
  would compute, and it reaches `/etc` from the ESP;
- the update across an L4T release with a capsule: the firmware writes the
  other chain and boots the other slot on the same reboot; `report` says
  `applied`; and the rollback to the old pair;
- a rejected capsule (a module whose spec the capsule lacks): the device stays
  on the old slot, `report` says `failed`;
- whether `nvbootctrl -t rootfs set-active-boot-slot` deletes
  `BootChainFwStatus`, and which words `nvbootctrl dump-slots-info` prints for
  a failed bootloader slot;
- the L4TLauncher copy: NVIDIA's updater copies it with the capsule; whether
  the old chain starts the new L4TLauncher after a rollback;
- a power loss during the capsule write, several times.

### At build time

`build/tegra-capsules.sh` checks the tree after the packages are in: capsules
for boards 3767 and 3701 and L4TLauncher in `/opt/ota_package/t23x`; every
capsule a UEFI FMP capsule whose firmware version (its FMP payload header) is
`L4T_VERSION` of `bsp.conf`, the BSP the flash kit writes the QSPI firmware
from; `nvidia-l4t-bootloader` at `L4T_PACKAGE_VERSION`; the tree's
`/etc/nv_tegra_release` at `L4T_VERSION`; NVIDIA's licence texts of the
package. Any difference fails the build: QSPI and root file system stay in
lock-step. It cannot compare the capsule's images with the ones the flash kit
makes from the BSP; on a module, the ESRT's version after a flash and after a
capsule is the comparison that remains.

It then writes the FreeRTOS statement the licence review asks for (point 6):
`/usr/share/doc/ironflockos/FreeRTOS-source-offer.txt`, from
`targets/jetson-orin/freertos-offer.txt`, with the FreeRTOS version (V8.1.2)
of the SPE firmware in the capsules and the offer of its source at the source
mirror of the release (`<DL_BASE>/ironflockos/sources/l4t-<version>/`,
WP-6.8). It is in the image and so in every bundle, next to NVIDIA's own texts
that come with the package: the Driver License Agreement
(`/usr/share/doc/nvidia-l4t-bootloader/copyright`) and the FreeRTOS licence
(`LICENSE.bl_update_payload.gz`).

## Partition layout

NVIDIA's flash tools partition and write a Jetson's disk; IronFlockOS does not
make a disk image for it. `build/tegra-layout.py` takes the BSP's
`tools/kernel_flash/flash_l4t_t234_nvme_rootfs_ab.xml` and adds IronFlockOS's
`data` partition after `APP_b`. That partition grows to the end of the disk
(allocation attribute `0x808`, as NVIDIA's single-slot layout grows `APP`) and
is mounted at `/data` (`PARTLABEL=data`). NVIDIA's layout files are under
NVIDIA's licence, so the layout is generated from the BSP when the flash
package is made, never copied into this repository. The script refuses a
layout of another shape, so a BSP that changes it fails instead of flashing
something unexpected. The partitions:

| Partition | Content |
|-----------|---------|
| `A_kernel`, `B_kernel`, `A_kernel-dtb`, `B_kernel-dtb`, recovery | NVIDIA's, from the BSP (the fallback when the root slot does not boot) |
| `esp` | the EFI system partition with L4TLauncher; `/boot/efi`, where the `.flock` to enroll with goes |
| `APP`, `APP_b` | root slots A and B (`SLOT_SIZE_BASE`) |
| `data` | `/data`, to the end of the disk; GPT entry 17 (explicit: counted on from `APP_b`'s 2, it would take `A_kernel`'s 3) |

The ESP keeps NVIDIA's name `esp`, because `flash.sh` makes its image only
under that name. On the other targets that role belongs to `IRONFLOCKOS`, so the
build points `/boot/efi` in this target's `/etc/fstab` at `PARTLABEL=esp`.

The build's image is slot A's filesystem, `<image-id>-<version>.rootfs.ext4.zst`
(`build/mkimage-tegra.sh`), with an `extlinux.conf` that boots slot A. The
flash package takes it for `APP`, and a copy pointed at slot B for `APP_b`
(`tegra-extlinux`); NVIDIA's tools' `-r` option reuses prebuilt slot images,
so `flash.sh` does not rebuild them from a tree with its own kernel and
command line.

## Flash package

`build/tegra-flash-package.sh` makes the flash package of an Orin on NVMe on
the flashing host (x86_64 Ubuntu with the BSP's
`tools/l4t_flash_prerequisites.sh`). It follows NVIDIA's workflow for rootfs
A/B on NVMe (Jetson Linux r39.2.1 Developer Guide, "Flashing Support"): two
runs of `l4t_initrd_flash.sh --no-flash`, both with `ROOTFS_AB=1` and `-r`:

```sh
l4t_initrd_flash.sh --showlogs --no-flash -r -p "-c bootloader/generic/cfg/flash_t234_qspi.xml" --network usb0 <board> internal
l4t_initrd_flash.sh --showlogs --no-flash -r --external-device nvme0n1 -c <layout> -S <slot size> --external-only --append --network usb0 <board> external
```

The first makes the QSPI firmware's images (`images/internal`): only the
QSPI, also on an AGX Orin, whose eMMC is not written. With `ROOTFS_AB=1`
NVIDIA's tools give its UEFI the rootfs A/B setting. The second adds the
NVMe's (`images/external`), after preparing the unpacked BSP:

- the layout from `build/tegra-layout.py`;
- `bootloader/system.img` (APP) from the slot image, and `system.img_b`
  (APP_b), the same pointed at slot B through `debugfs` (no mount);
- the slots' PARTUUIDs, the ones their `extlinux.conf` names (`uuid_for
  rootfs-a`/`rootfs-b`), in `flash.sh`'s UUID files `l4t-rootfs-uuid.txt_ext`
  and `_b_ext`;
- `rootfs/`: slot A's tree, which NVIDIA's tools read (the board's
  compatible spec), plus what the flashing initrd and the recovery ramdisk
  take from it and the image does not carry: `mtd-utils`, `file`, `parted`,
  `nvidia-l4t-optee`, `busybox`, `fdisk`, `gdisk`, `libnsl2`, `libpcre3`,
  `isc-dhcp-client`, installed into that copy (a chroot through qemu-user)
  from the image's own sources and pins;
- a fix of NVIDIA's `-r` option: `l4t_initrd_flash.func` and
  `l4t_create_images_for_kernel_flash.sh` declare it with an argument in
  their getopts strings, though it takes none, so it swallows the next option
  and every later option is lost. The script makes it a flag, and fails where
  the BSP's string is not the known one. With `-r` in both runs neither
  builds `system.img` from the tree over the slot images.

The board's identity comes from the module, attached in recovery mode, as
NVIDIA's tools read it. With a board ID and SKU on the command line the
package is made offline instead, without a module (`FAB`, `BOARDREV`,
`CHIP_SKU` and `RAMCODE` from the environment); CI does that.

The package lands in the BSP's `tools/kernel_flash/images`: the QSPI images,
and the NVMe's GPT and flash index, ESP, boot and recovery images, and
APP/APP_b. `l4t_initrd_flash.sh --flash-only` writes it to a module in
recovery mode. The flash kit does all of that on the user's host; IronFlockOS
does not publish the package (licence review, point 4). CI makes it for an
Orin Nano 8GB (`3767`/`0003`, chip SKU `00:00:00:D5`) on
`jetson-orin-nano-devkit` on every pull request (`jetson-flash`), through the
flash kit, with the BSP tarball cached by its pin; there
`l4t_initrd_flash.sh` gets an empty USB bus in a mount namespace of its own,
as it fails where there is none even with `--no-flash`.

## Flashing a module

A module is flashed from a Linux PC with the **flash kit**,
`ironflockos-jetson-flash-kit-<version>.tar.gz`: IronFlockOS's own scripts
and nothing of NVIDIA's (licence review, points 4 and 7). On the PC, the kit
downloads the pinned Jetson Linux BSP from NVIDIA, makes the flash package
with NVIDIA's tools from it and the IronFlockOS slot image, and writes the
module's QSPI firmware and NVMe with NVIDIA's `l4t_initrd_flash.sh`. The
Orin Nano Developer Kit is flashed the same way: it has no SD image of
IronFlockOS (see the start of this page).

CI packs the kit on every pull request (`build/jetson-flash-kit.sh`, the
artifact `jetson-flash-kit` of the `jetson-flash` job). A release publishes
it next to the slot image and NVIDIA's Agreement while `JETSON_RELEASE` is
`true` ([release.md](../release.md#jetson)), at
`https://instance-registry.ironflock.com/dl/ironflockos/<version>/`. Before
the first such release, take the kit from that artifact, or run
`build/jetson-flash.sh` from a clone of this repository; with no published
image, give it the slot image of the `image-jetson-orin-base` artifact with
`--image` and its line of that artifact's `SHA256SUMS` with `--sha256`.

### What you need

- A PC with an x86-64 CPU and **Ubuntu 22.04 or 24.04** (the host
  distributions of Jetson Linux r39.2's release notes; the kit warns on
  others), not a virtual machine, with internet access, `sudo`, and about
  25 GB of free disk: the BSP tarball, its unpacked copy and the package.
  NVIDIA's tools reach the module over USB networking and NFS on the IPv6
  range `fc00:1:1::/48`; a firewall must let that through.
- A USB cable from the PC to the carrier board's flashing port, without a
  hub: the USB-C port next to the 40-pin header on the AGX Orin Developer
  Kit, the USB-C port of the Orin Nano Developer Kit.
- An NVMe drive in the carrier board's M.2 slot. The flash erases it, and
  writes the module's QSPI firmware.
- The device's `.flock` from IronFlock.

The kit knows these boards (NVIDIA's board configurations of the BSP and
NVIDIA's recovery-mode USB ids, from its Quick Start; on another carrier
board, the configuration its maker names):

| `--board` | Modules | Recovery USB id |
|-----------|---------|-----------------|
| `jetson-orin-nano-devkit` | Orin NX 16GB (P3767-0000) and 8GB (-0001), Orin Nano 8GB (-0003, -0005) and 4GB (-0004), on the Orin Nano Developer Kit carrier (P3768) | `0955:7323`, `7423`, `7523`, `7623` |
| `jetson-orin-nano-devkit-super` | the same, with the Super power modes | the same |
| `jetson-agx-orin-devkit` | AGX Orin (P3701-0000, -0004, -0005) on the AGX Orin Developer Kit carrier (P3737) | `0955:7023`, `7223` |
| `jetson-agx-orin-devkit-super` | AGX Orin 32GB (P3701-0004), Super power modes | `0955:7223` |
| `jetson-agx-orin-devkit-industrial` | AGX Orin Industrial (P3701-0008) | `0955:7023` |

IronFlockOS goes onto the NVMe on every board. eMMC, USB drives and SD cards
are not supported: `build/tegra-layout.py` knows NVIDIA's NVMe layout only.
On an AGX Orin the eMMC keeps what it holds, an older system included.
**Not yet proven on the AGX Orin:** that its firmware then starts IronFlockOS
from the NVMe and not the system on the eMMC; nobody has flashed one yet
(WP-6.6). Flash an AGX Orin only to try this out until then.

### Step by step

1. **Recovery mode.** Orin Nano Developer Kit carrier (Orin Nano, Orin NX):
   unplug the power, put a jumper across the REC and GND pins of the button
   header, plug the power in. AGX Orin Developer Kit: with it off, hold the
   Force Recovery button, press and release Power, release Force Recovery.
   Connect the flashing port to the PC. `lsusb -d 0955:` lists the module
   with one of the ids above.
2. **Unpack the kit and run it**, with the board and the device's `.flock`:

   ```sh
   tar -xzf ironflockos-jetson-flash-kit-<version>.tar.gz
   cd ironflockos-jetson-flash-kit-<version>
   sudo ./ironflockos-jetson-flash --board jetson-orin-nano-devkit --flock ~/my-device.flock
   ```

   `--help` lists the options. The kit works in `./ironflockos-jetson`
   (`--work`), and keeps its downloads in `./ironflockos-jetson/cache`
   (`--cache`) for the next run.
3. **NVIDIA's Agreement.** The kit downloads NVIDIA's Driver License
   Agreement from NVIDIA (`BSP_LICENSE_URL` in `bsp.conf`), checks it against
   its pinned SHA-256 and NVIDIA's list, shows it, and asks: type `yes` to
   accept. Anything else ends the kit before anything of NVIDIA's is
   downloaded, unpacked or run. `--accept-nvidia-license` accepts it without
   the question, for scripts; the kit still prints it.
4. **The image.** The kit downloads the release catalog, checks its Ed25519
   signature with the catalog key it carries (`pki/ironflockos-catalog.pub`),
   as the device-agent and FlockFlasher do, and downloads the slot image
   `ironflockos-jetson-orin-base-<version>.rootfs.ext4.zst` it names, checked
   against the catalog's SHA-256 and size. `--image FILE` takes a file
   instead, checked against the catalog, or against `--sha256 HEX`.
5. **The BSP.** The kit downloads `Jetson_Linux_R39.2.1_aarch64.tbz2` from
   NVIDIA, checks its SHA-256 and SHA-1 against `bsp.conf` and NVIDIA's list
   (`build/fetch-bsp.sh`), and only then unpacks it. It runs NVIDIA's
   `tools/l4t_flash_prerequisites.sh` and installs `zstd`, `e2fsprogs`,
   `mtools` and `usbutils` (`--skip-prerequisites` leaves the host's packages
   alone).
6. **The module.** Exactly one Jetson in recovery mode must be on USB, of the
   board named; else the kit says what it found and how to get into recovery
   mode.
7. **The package** (above), with the module's identity read from it.
8. **The `.flock`.** The kit copies it into the package's ESP image (`esp`,
   the device's `/boot/efi`, where `ironflockos-enroll` looks at the first
   boot), reads it back, and gives NVIDIA's flash index the image's new
   SHA-1 (`build/tegra-flash-flock.sh`). It refuses a file that is not a
   device's `.flock` before anything is downloaded. Without `--flock` the
   device boots and waits for one, as an image from FlockFlasher without one
   does. The same way the kit puts the `nv_boot_control.conf` that NVIDIA's
   `flash.sh` wrote for the module onto the ESP, which the device copies to
   `/etc` at every boot ("The module's nv_boot_control.conf"); without one
   the kit warns and goes on, and the device cannot update its boot
   firmware.
9. **The flash:** `l4t_initrd_flash.sh --showlogs --network usb0 --flash-only
   --erase-all` from the BSP, with NVIDIA's own output, about 15 minutes:
   the QSPI firmware, then the NVMe.
10. **The end.** The kit takes the `.flock` and the conf off the package again, whether
    the flash worked or not, so no copy of it stays on the PC. It says
    `flashed: the module restarts into IronFlockOS <version>, slot A`. On the
    Orin Nano Developer Kit carrier, unplug the power, remove the jumper and
    plug the power in. The module boots slot A, enrolls with the `.flock` and
    comes online in IronFlock; the device-agent marks the slot good.

### When it fails

| What the kit says | What to do |
|-------------------|------------|
| `unknown board` | Take a name from the list it prints |
| `has to be accepted before anything of NVIDIA's is unpacked or run` | Run it in a terminal and type `yes`, or read the Agreement and add `--accept-nvidia-license` |
| `does not match the pinned SHA-256 and SHA-1`, `republished` | The download is not the file the kit was made for, and nothing was unpacked. Try again; if it stays, NVIDIA changed the file and the kit needs a new release |
| `signature does not verify`, `has no IronFlockOS <version>` | The catalog is not IronFlock's, or the release has no Jetson image; check `--catalog` and `--version` |
| `does not have the SHA-256` | The slot image is damaged or not the release's; the kit deletes a download and fetches it again on the next run |
| `no Jetson in recovery mode` | Put the module into recovery mode (step 1); check the cable and that no hub is between |
| `is no module of <board>` | The module on USB belongs to another board: name that one |
| an error inside NVIDIA's tools | Their output is above it; NVIDIA's logs are in `ironflockos-jetson/Linux_for_Tegra/initrdlog`. Put the module into recovery mode again and run the kit again |

### Flashing again

Put the module into recovery mode and run the same command. The kit unpacks
the BSP afresh each time (from its cache) and makes the package again, so a
run that failed halfway leaves nothing behind that the next run uses. The
flash erases the NVMe: `/data` and the enrollment are gone, and the device
enrolls again with the `.flock` given.

### Proven, and still to prove

CI (`jetson-flash`) runs the packed kit from its archive with `--no-flash`
on every pull request: the Agreement from NVIDIA with
`--accept-nvidia-license`, the build's slot image against its SHA-256, the
BSP from the cache checked before it is unpacked, NVIDIA's prerequisites,
both package runs offline for an Orin Nano 8GB, a test `.flock` and
`flash.sh`'s `nv_boot_control.conf` put on the ESP and read back, and the
package without them at the end. The unit tests
(`test/unit/jetson-flash-kit.bats`) cover the kit's own decisions with fakes.

Only a module can prove (WP-6.6):

- that the `--no-flash` runs read the module's identity in recovery mode,
  and `--flash-only --erase-all` then writes it without the module being put
  into recovery mode again;
- that the QSPI-only layout `flash_t234_qspi.xml` is the right one for every
  board above, the AGX Orin's included, and that its UEFI then boots the
  NVMe (on an AGX Orin with an eMMC that still holds a system, too);
- that the QSPI images carry rootfs A/B (`RootfsRedundancyLevel` 1);
- that the ESP's image in the package is a plain FAT image, that the device
  side of NVIDIA's flash checks it against the index's SHA-1 and nothing
  else, and that the `.flock` and `nv_boot_control.conf` arrive on
  `/boot/efi`;
- the recovery-mode steps and USB ids above;
- a flash from a host with Ubuntu 22.04 and one with 24.04.

## Tests

`test/unit/tegra-rootfs-ab.bats` tests the backend and the health gate
without a module: every command of the backend in every state and failure,
against a fake `nvbootctrl` and fake efivarfs files, and the cases above
against a model of NVIDIA's firmware that counts boots as
`L4TRootfsValidation.c` does. `test/unit/tegra-capsule.bats` tests the boot
firmware lane the same way: every case of `stage` (each reason to skip or
refuse, the variables' bytes, the capsule's place and name, the window file),
the backend with a staged capsule, an update through a model of the firmware
that applies or rejects the capsule, `report`, the build's check, and
`tegra-board-conf` (the ESP's file to `/etc`, a file that is not NVIDIA's, no
file, `/etc` not writable).
`test/unit/jetson.bats` checks the target's files.
`test/unit/jetson-flash-kit.bats` tests the flash kit with fakes of
NVIDIA's BSP and Agreement, a release catalog signed with a throwaway key and
a fake ESP image: the order of its steps (nothing of NVIDIA's before the
Agreement is accepted, nothing unpacked before the checksums), the boards,
the `.flock` and `nv_boot_control.conf` on the ESP, and the archive.

`just build jetson-orin base` builds the image and leaves the tree in
`<work>/ironflockos-jetson-orin-base/rootfs`. On an arm64 host,
`sudo test/image/jetson-rootfs-check.sh <work>/ironflockos-jetson-orin-base/rootfs`
checks it: the versions, the sources and pins, kernel, initrd (the one
`initrd.sources` lists the Ubuntu programs of) and `nvgpu`,
units and masks, the RAUC backend and the health gate's timer, the capsules
(unchanged against the package's checksums), the FreeRTOS statement and the
boot firmware report, the baked agent and the `nvidia` runtime, the
`copyright` file of every installed `nvidia-l4t-*` package, and the names at
login ([above](#names-at-login)). Given the
bundle as well, it checks that the bundle's `rootfs.ext4` carries the
capsules, the statement and `tegra-capsule`. It also runs the tree's binaries in a chroot:
dpkg and apt consistency, systemd, Docker, containerd, RAUC, the backend,
`ironflock`, `nvidia-ctk` and `nvidia-container-cli`. CI runs both on every
pull request (`jetson-rootfs` in `ci.yml`, with the bundle), and makes the
flash package from the image with the flash kit (`jetson-flash`, above).
`jetson-release` runs the release path on the image in its dry mode
(`test/image/jetson-release-check.sh`, [release.md](../release.md#jetson)):
what would be published, the release notes rule, the catalog, the source
mirror, and the FreeRTOS statement in the slot image against the mirror and
the contact. The three jobs run when the repository variable `JETSON_CI` is
`true`, and `ci-ok` needs them. `test/unit/jetson-release.bats` covers the
switch, the published files, the notes rule, the source decisions and the
contact.

## Open points

- `/etc/nv_boot_control.conf`: `flash.sh` writes it for the module into the
  BSP's `rootfs/`, and with `-r` it does not reach the slot images (the
  `jetson-flash` job prints the one it wrote). `nvbootctrl` reads the chip id
  from it and falls back to the device tree without it (its strings);
  NVIDIA's OTA tools and capsule scripts need it, and so does
  `tegra-capsule` (`COMPATIBLE_SPEC`, `TNSPEC`). The slot images do not
  carry it (it describes the module); the flash kit puts it onto the ESP,
  and `tegra-board-conf` copies it to `/etc` at every boot ("The module's
  nv_boot_control.conf"; `rauc-post-install` also carries it into the slot
  it writes). A module flashed another way has none until it is flashed
  with the kit: it runs, but its boot firmware cannot be updated.
- The first flash of a module, the A/B switch, the forced fallback and a
  capsule update (WP-6.6, above).
- eMMC as the system disk (AGX Orin without NVMe): `build/tegra-layout.py`
  knows NVIDIA's NVMe layout only.
- Licences ([jetson-licence-review.md](../jetson-licence-review.md); done
  2026-11-07, signed off by IronFlock 2026-11-17). Jetson Linux is under the NVIDIA
  Driver License Agreement: NVIDIA's binaries may be redistributed only
  unchanged, and every recipient must get the Agreement. What follows for this
  target:
  - the build keeps NVIDIA's packages and their `/usr/share/doc` unchanged;
    the rootfs check fails when an installed `nvidia-l4t-*` package has no
    `copyright` file (built);
  - `apt/jetson-ota-public.asc` is the key as `repo.download.nvidia.com`
    serves it, without NVIDIA's licence header (built);
  - the image shows IronFlockOS's names, not Ubuntu's, and keeps Ubuntu's
    technical references (built, [Names at login](#names-at-login));
  - the flash package stays a CI test, and users get the flash kit, which
    downloads the BSP and the Agreement from NVIDIA and asks for acceptance
    (WP-6.4, [Flashing a module](#flashing-a-module));
  - the QSPI capsule comes unchanged from `nvidia-l4t-bootloader` (WP-6.5,
    built: "Boot firmware updates");
  - a release publishes `NVIDIA-LICENSE.txt` (the BSP's Agreement, fetched
    from NVIDIA as `bsp.conf` pins it) next to the Jetson files, and its
    notes link it; the image carries the Agreement byte for byte in
    `nvidia-l4t-core`'s documentation (built, WP-6.8);
  - the release mirrors NVIDIA's `public_sources.tbz2` and the
    `libnvidia-container` source to `ironflockos/sources/l4t-39.2.1/`, and
    the Ubuntu source packages of the image to the release's pool; the
    FreeRTOS statement offers the source there and names IronFlock GmbH,
    its postal address and legal@ironflock.com (built, WP-6.8);
  - NVIDIA's initrd (`nvidia-l4t-initrd`) carries Ubuntu programs under
    the GPL and LGPL that NVIDIA does not name; `targets/jetson-orin/initrd.sources`
    lists their Ubuntu packages and versions, found by content with
    `tools/initrd-sources.py`, and the release publishes their source
    packages; the build fails when `/boot/initrd` is not the initrd the
    list was made from (built, WP-6.8).
