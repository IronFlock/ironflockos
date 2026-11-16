# Target jetson-orin

NVIDIA Jetson AGX Orin, Orin NX and Orin Nano on Jetson Linux r39.2.1 (JetPack
7.2.1) with an Ubuntu 24.04 userspace (ADR-0008; Phase 6). Work in progress:
CI builds slot A's filesystem image and the RAUC bundle, checks the root tree
and makes the flash package without a module (WP-6.2). The RAUC backend over
`nvbootctrl` and the health gate are built and unit-tested (WP-6.3); nobody
has run them on a module yet. Still to come:

- the flash kit and the SD image (WP-6.4);
- the QSPI lane (WP-6.5);
- the A/B switch and the forced fallback on a module (WP-6.6).

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
| Image | `<image-id>-<version>.rootfs.ext4.zst`, slot A's filesystem (APP), and the bundle `<image-id>-<version>.raucb` |

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
tests). It is the file `nvidia-l4t-apt-source` 39.2.1 ships, byte for byte the
copy in the pinned BSP tarball, and it signs both repositories' `InRelease`.

Left out on purpose:

- `nvidia-l4t-bootloader`: the QSPI payloads; the QSPI firmware has its own lane (WP-6.5).
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
  firmware (WP-6.5); the health gate below verifies the boot.
- `nv-rootfs-validation-config` runs before it, and reboots when a user
  validation script (`/usr/sbin/user_rootfs_validation.sh`) fails: at every
  boot, without a bound. IronFlockOS has no such script.

Masking `nv-l4t-bootloader-config` also leaves out what else it does at boot:
writing NVIDIA's platform spec variables (`TegraPlatformSpec`,
`TegraPlatformCompatSpec`, which capsule updates check), the board spec in
`/etc/nv_boot_control.conf`, mounting the ESP (the image's `/etc/fstab` does)
and renaming old kernel partitions. The capsule lane has to do the spec
variables (WP-6.5).

NVIDIA's `nvidia-l4t-init` also sets the hardware watchdog to 120 seconds
(`/etc/systemd/system.conf.d/watchdog.conf`), which comes after IronFlockOS's
60 seconds and wins. Either way a hung system is reset.

The rest of `nvidia-l4t-init` stays enabled as NVIDIA presets it: GPU libraries,
display modules, power model, fan control.

There is no `repart.d` on this target: NVIDIA's flash tools write the whole
layout, the `data` partition included.

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
- The flash with `ROOTFS_AB=1` sets `RootfsRedundancyLevel` 1 and creates
  `RootfsStatusSlotA`/`B` (the flash package, WP-6.4).
- efivarfs is mounted read-write and the backend's writes of
  `RootfsStatusSlot` reach the firmware; `nvbootctrl` works with
  IronFlockOS's kernel and without `/etc/nv_boot_control.conf` (it falls back
  to the device tree for the chip id), or the flash package adds the file.
- `systemctl reboot`, a kernel panic and the hardware watchdog are warm
  resets that keep the scratch register; a power cut is cold.
- The A/B switch: `rauc install`, reboot, the agent marks the slot good,
  `rauc status` shows it booted and primary.
- The forced fallback: install a bundle whose slot panics (for example with
  `init=/bin/false` in its `extlinux.conf`); after three boots the module is
  back on the old slot, and `rauc status` shows the new one bad. And a slot
  that boots but has no network: it stays up; after a restart (warm, and once
  cold) it is up for two minutes, then the module restarts into the old slot.

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
`tools/l4t_flash_prerequisites.sh`), offline: no Jetson needs to be attached,
the module is named by its board ID and SKU. It runs NVIDIA's
`ROOTFS_AB=1 l4t_initrd_flash.sh --no-flash -r --external-device nvme0n1 -c <layout> --external-only <board> external`
after preparing the unpacked BSP:

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
  the BSP's string is not the known one.

The package lands in the BSP's `tools/kernel_flash/images`: the external
device's GPT and flash index, ESP, boot and recovery images, and APP/APP_b as
NVIDIA's tarballs. `l4t_initrd_flash.sh --flash-only` writes it to a module in
recovery mode (WP-6.4). CI makes it for an Orin Nano 8GB (`3767`/`0003`) on
`jetson-orin-nano-devkit` on every pull request (`jetson-flash`), with the
BSP tarball cached by its pin; there `l4t_initrd_flash.sh` gets an empty USB
bus in a mount namespace of its own, as it fails where there is none even
with `--no-flash`.

## Tests

`test/unit/tegra-rootfs-ab.bats` tests the backend and the health gate
without a module: every command of the backend in every state and failure,
against a fake `nvbootctrl` and fake efivarfs files, and the cases above
against a model of NVIDIA's firmware that counts boots as
`L4TRootfsValidation.c` does. `test/unit/jetson.bats` checks the target's
files.

`just build jetson-orin base` builds the image and leaves the tree in
`<work>/ironflockos-jetson-orin-base/rootfs`. On an arm64 host,
`sudo test/image/jetson-rootfs-check.sh <work>/ironflockos-jetson-orin-base/rootfs`
checks it: the versions, the sources and pins, kernel, initrd and `nvgpu`,
units and masks, the RAUC backend and the health gate's timer, the baked
agent and the `nvidia` runtime. It also runs the tree's binaries in a chroot:
dpkg and apt consistency, systemd, Docker, containerd, RAUC, the backend,
`ironflock`, `nvidia-ctk` and `nvidia-container-cli`. CI runs both on every
pull request (`jetson-rootfs` in `ci.yml`, with the bundle), and makes the
flash package from the image (`jetson-flash`, above). Both jobs run when the
repository variable `JETSON_CI` is `true`, and `ci-ok` needs them.

## Open points

- `/etc/nv_boot_control.conf`: `flash.sh` writes it for the module into the
  BSP's `rootfs/`, and with `-r` it does not reach the slot images.
  `nvbootctrl` reads the chip id from it and falls back to the device tree
  without it (its strings); NVIDIA's OTA tools and capsule scripts need it.
  The flash package has to put it into APP and APP_b (WP-6.4), and updates
  have to keep it.
- The A/B switch and the forced fallback on a module (WP-6.6, above).
- The internal storage (QSPI) images: `--external-only` leaves them out. A
  module needs them once (r39 bootloader; NVIDIA's two-step `--no-flash
  --reuse ... internal`, then `--external-only --append`) (WP-6.4).
- The `.flock` on the ESP for enrollment (WP-6.4).
- Licences ([jetson-licence-review.md](../jetson-licence-review.md); done
  2026-11-07, legal sign-off in WP-6.8). Jetson Linux is under the NVIDIA
  Driver License Agreement: NVIDIA's binaries may be redistributed only
  unchanged, and every recipient must get the Agreement. What follows for this
  target:
  - the build keeps NVIDIA's packages and their `/usr/share/doc` unchanged
    (a rootfs check will enforce it);
  - `apt/jetson-ota-public.asc` is replaced with the key as
    `repo.download.nvidia.com` serves it, without NVIDIA's licence header;
  - the flash package stays a CI test, and users get a flash kit that
    downloads the BSP from NVIDIA (WP-6.4);
  - the QSPI capsule comes unchanged from `nvidia-l4t-bootloader` (WP-6.5).
