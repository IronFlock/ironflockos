# ADR-0022: An OS update renews the boot script on the IRONFLOCKOS partition, with one trial boot

Status: accepted, 2026-11-17. First in the release after IronFlockOS 0.17.0.

## Context

On the EFI targets (`amd64-efi`, `arm64-efi`) GRUB's script was `EFI/BOOT/grub.cfg` on the
IRONFLOCKOS partition, next to `grubenv`. An OS update writes the other root slot and
never that partition, so a device kept the `grub.cfg` of the release it was installed
with for good: no change to the boot script (the kernel command line, the splash, the
menu, `fsck.repair=yes` of ADR-0020) reached a device in the field. A new installation
is no way out: `ironflock os install` refuses a machine that already runs IronFlockOS,
and the first machine in the field (the machine of ADR-0020, installed with 0.17.0) is
reached through a shell only, with nobody on site.

The Raspberry Pi and Jetson keep their boot files in the slot, which the update writes;
they are not affected.

## What GRUB does

Debian's signed GRUB 2.12 (trixie, `grub-efi-amd64-signed` and `grub-efi-arm64-signed`
from Debian's `grub2` source, `2.12-9+deb13u4` read), started by Debian's shim (16.1):

1. **Which file.** `grubx64.efi` is built by `debian/build-efi-images` with prefix
   `/EFI/debian`, a memdisk with the font only, and no embedded configuration.
   `grub-core/kern/main.c` (`grub_set_prefix_and_root`) sets `fw_path` from the loaded
   image's device and the folder of its file path; shim sets that file path to the second
   stage it starts (`shim.c`, `start_image`: `shim_li->FilePath = FileDevicePath(NULL,
   PathName)`), so `fw_path` is the IRONFLOCKOS partition's `/EFI/BOOT`, and `root` is
   that partition. `grub-core/normal/main.c` (`grub_cmd_normal`, Debian's patch
   `add-fw_path-variable-to-detect-config-file-on-efi`) then tries `$fw_path/grub.cfg`,
   then `$prefix/grub.cfg` (`/EFI/debian/grub.cfg`), then `/EFI/debian/grub.cfg` on every
   other disk, then starts the GRUB prompt without a file. A file is taken when
   `grub_file_open` succeeds, whatever it holds: an empty or cut `EFI/BOOT/grub.cfg` is
   run, and the second path is not tried. A file that defines no menu entry ends at the
   GRUB prompt, which waits for a person.
2. **Running a file.** `read_config_file` runs a file statement by statement; a syntax
   error drops that statement (to the end of the file for an `if` without `fi`), prints
   the error and goes on. `source` (`grub-core/commands/configfile.c`) runs a file in the
   same context and adds its entries to the current menu; a missing file is ignored
   (`grub_normal_execute` clears the error). `configfile` runs it in a new context and
   shows its menu, which, when every entry fails, waits for a person.
3. **Booting.** A script does not boot; it defines entries. When the top file has run,
   GRUB boots `default`, and when an entry returns, the entries `fallback` names, by
   number (`grub-core/normal/menu.c`). An entry fails when `linux` or `initrd` fails
   (missing file, or shim refuses the kernel) or `boot` returns. When all fail, GRUB
   says so, waits up to ten seconds and shows the menu without a timeout: it waits for a
   person. GRUB switches the firmware's watchdog off (`kern/efi/init.c`). A `submenu` is a
   menu of its own in a new context: run from an autoboot, it boots its own default and
   fallback, and when they fail it returns (`show_menu`: `if (autobooted) break`), and the
   outer menu goes on with its own fallback. Variables reach a submenu only when they are
   exported (`root`, `prefix`); functions are global. GRUB prints the error of every
   command right after it, also in an `if` condition (`grub_script_execute_cmdline`);
   inside a menu entry or submenu, a printed error makes it wait ten seconds
   (`grub_menu_execute_entry`, `grub_wait_after_message`).
4. **grubenv.** `save_env` (`grub-core/commands/loadenv.c`) reads the 1024-byte block,
   sets the variables in it (a new one goes into the `#` padding,
   `grub_envblk_set`), and writes the block's sectors in place through their block list;
   when a variable does not fit, nothing is written and the command fails. An unset
   variable is deleted from the block. It needs a disk device. With RAUC's variables, the
   display setting, a long real-time tuning, the QEMU tests' command line and the three
   variables below, the block holds about 470 of its 1024 bytes
   (`test/unit/boot-script.bats`).
5. **Modules.** The image has `GRUB_MODULES` of `build-efi-images` built in, among them
   `configfile`, `loadenv`, `test`, `regexp`, `probe`, `linux`, `gzio`, `part_gpt`, `fat`,
   `ext2`, `true`; not `eval`. Under Secure Boot GRUB loads no other module.
6. **The kernel.** A kernel that does not find its root: the initramfs
   (`initramfs-tools`, `scripts/local`) waits 30 seconds and calls `panic`, which with
   `panic=10` on the command line restarts after ten seconds.
7. **The FAT driver** (an inference from Linux's `fs/fat` and `dosfstools`, not tried):
   a rename to a free name adds the new entry and then removes the old one, so a cut
   rename can leave both names on one cluster chain, and `fsck.fat -a` at the next boot
   truncates one of them to 0 bytes. A rename over an existing file, or a delete, frees
   the old file's clusters, and the FAT's and the folder's sectors reach the disk in no
   set order, so a cut can leave a name on freed clusters, which GRUB reads as an error
   and `fsck.fat` truncates. A sector is assumed to be written whole, as `save_env`
   assumes.

## Decision

### The files

On the IRONFLOCKOS partition, in `EFI/BOOT`:

- `grub.cfg` is the **loader** (`targets/amd64-efi/grub/loader.cfg`), a small file that
  is written as rarely as possible. `EFI/debian/grub.cfg`, GRUB's second path, is the
  same file. It loads `grubenv`, picks the script, runs it, and holds the last resort.
- `boot.cfg` is the **boot script** in use (`targets/amd64-efi/grub/boot.cfg`): what
  `grub.cfg` was up to 0.17.0, the slot choice from `ORDER`/`_OK`/`_TRY`, the kernel
  command line, the splash, the menu.
- `boot-next.cfg` is a newer script on trial.

Every root slot carries its release's script and loader in `/usr/lib/ironflockos/boot/`,
rendered for the target at build time; `build/mkimage.sh` puts these same files on the
partition of a new image and of the installer stick. Each file's first line names its
version (`# ironflockos-boot-script-version: N`, `# ironflockos-boot-loader-version: N`),
an integer that goes up whenever the file changes and never down; its last line marks it
whole. The script puts its version on the kernel command line
(`ironflockos.boot_script=N`), so the running system knows which script booted it:
none named is 0.17.0's script, `0` the loader's last resort.

`grubenv` gets three variables: `IRONFLOCKOS_SCRIPT_TRIAL` (`staged`, `tried`, `failed`,
`good` or empty), `IRONFLOCKOS_SCRIPT_SLOT` (the slot that staged the script) and
`IRONFLOCKOS_SCRIPT_FAILED` (the highest version whose trial failed).

### The loader

| `IRONFLOCKOS_SCRIPT_TRIAL` | and | the loader writes | GRUB runs |
|---|---|---|---|
| empty, `failed`, anything else, or `grubenv` unreadable | | | `boot.cfg` as `grub.cfg` ran before (its menu, timeout and fallback); when it set no `default` (missing, or it defined nothing), the last resort |
| `staged` | `boot-next.cfg` is there, `IRONFLOCKOS_SCRIPT_SLOT` is the first slot of `ORDER`, that slot is `_OK=1` and `_TRY=0`, and `save_env` works | `tried` | submenu `boot-next.cfg`; then submenu `boot.cfg`, which first writes `failed` and gives the slot back its try; then the last resort |
| `staged` | otherwise | | as empty |
| `tried` (the trial's boot was not confirmed) | | `failed`, and `_TRY=0` for `IRONFLOCKOS_SCRIPT_SLOT` | as empty |
| `good` (confirmed, `boot.cfg` not yet replaced) | | | submenu `boot-next.cfg`, then submenu `boot.cfg`, then the last resort |

The last resort is two menu entries at the end of every menu: the kernel of the first
slot of `ORDER`, then of the other slot, on text, with `IRONFLOCKOS_CMDLINE` and no try
accounting, so that the device comes online and the system can put its files right.

A missing script runs as one that boots nothing. The loader writes only `tried`,
`failed` and a `_TRY` flag, none longer than what it replaces, so `save_env` always
fits. A trial runs only on the slot that staged it, while that slot is GRUB's first
choice and good: a trial never shares a boot with a slot's trial.

### The service

`/usr/lib/ironflockos/boot-script` (`ironflockos-boot-script`):

- **At every boot** (`ironflockos-boot-script.service`, after the partition is mounted
  and checked): a `grub.cfg` that is missing or damaged is put back, from the second
  path, or from the slot when neither path holds a whole loader; the second path is made
  a copy of the first; a failed trial is recorded; a confirmed one finished.
- **When the booted slot is marked good** (`ironflockos-slot-proven.service`, on every
  change of `grubenv`) and **two minutes after `multi-user.target` on a proven slot**
  (`ironflockos-slot-keep.service`, after its `rauc status mark-good`): also the
  change-over below, a newer loader of the slot's (the second path first, then
  `grub.cfg`), and staging. Both need the booted slot proven, first in `ORDER`, good in
  this boot, and no update installed in this boot.
- **Staging:** when the slot's script is newer than `boot.cfg` (or `boot.cfg` is not
  whole, or the last resort booted this system), higher than
  `IRONFLOCKOS_SCRIPT_FAILED`, passes `grub-script-check` and no trial is open, it is
  written as `.boot-next.cfg.part`, synced, renamed to `boot-next.cfg`, the folder
  synced, and then `grubenv` gets `staged` and the slot.
- **Confirmation:** only at the two minutes, when this boot ran the script on trial
  (the command line names its version) on its slot and `rauc status mark-good` has
  marked the slot good: `grubenv` gets `good`, `boot-next.cfg` is copied over `boot.cfg`,
  the trial is cleared, `boot-next.cfg` removed.
- **Failure:** `failed`, or `tried` in a boot that did not run the script on its slot:
  the trial is cleared with its version in `IRONFLOCKOS_SCRIPT_FAILED` (when the script
  booted the other slot, its slot gets its try back, as the loader does), and
  `boot-next.cfg` is removed. The journal says so (`boot-script: the trial of boot script
  N failed ...`), and `/run/ironflockos/boot-script` names `failed=N`. Only a higher
  version is staged again.
- **An update installed** (RAUC's post-install handler, `boot-script cancel`): a staged
  script or an open trial goes, a confirmed one is finished, a failed one recorded, and
  nothing is staged or changed over until the next boot. The new slot's first boot runs
  the script in use; the new slot stages its own script once it has proven itself, so
  the two trials never share a boot.
- Every failure is a journal line; the device runs on the files it has; the units never
  fail. `/run/ironflockos/boot-script` holds `booted=`, `installed=`, `slot=`, `loader=`,
  `trial=`, `trial-version=`, `failed=` and `result=` (what this boot did), for the agent
  and the screen report.

The confirmation uses `ironflockos-slot-keep`'s proof, not the agent's connection: a
device that runs but cannot reach the platform (no network at the site, the platform
down) would otherwise never confirm, and its next restart, maybe weeks later, would count
a good script as failed. The two minutes are what keeps a proven slot from falling back,
so a script that boots its slot that far is as good as the slot.

### The change-over of a device installed with 0.17.0

Once, after the new slot is proven, when `grub.cfg` is a whole IronFlockOS script (it
has `rauc.slot=` and `menuentry`) and `EFI/debian/grub.cfg` is the file 0.17.0 wrote
(`source ($root)/EFI/BOOT/grub.cfg`) or already the loader:

1. `EFI/debian/grub.cfg` becomes the loader (written aside, synced, renamed over it).
   GRUB still reads `EFI/BOOT/grub.cfg`, 0.17.0's script, at every instant of this step.
2. `EFI/BOOT/grub.cfg` is renamed to `boot.cfg`: the bytes that booted this device,
   unchanged. From the moment the old name is gone, GRUB cannot open
   `EFI/BOOT/grub.cfg` and reads the loader at the second path, which runs `boot.cfg`.
   Before, it reads the old script; a cut rename may leave both names, either of which
   boots.
3. The loader is written as `.grub.cfg.part`, synced and renamed to the free name
   `grub.cfg`.

Then the slot's script is staged, and the next boot is its trial. Nothing is removed
and no clusters are freed until GRUB has a whole file at the path it reads; each step
waits for the one before to be on the disk. A cut after step 1 or 2 leaves a state the
next boot boots, and the service goes on from it (a missing `grub.cfg` is put back at
the next boot whatever the slot's proof). The one window left is fact 7: a rename cut
between its two folder sectors, then `fsck.fat` truncating `grub.cfg` rather than the
other name. GRUB booted the boot after the cut from the intact file; `fsck` runs in that
boot, and `ironflockos-boot-script.service` puts `grub.cfg` back from the second path in
the same boot, a second after the partition is mounted. Only a second power cut in that
second leaves a device that stops at GRUB's prompt. A later renewal of the loader uses
the same order: the second path, then `grub.cfg` aside by a rename, then the new one
under the free name.

A partition laid out before ADR-0011 (no `EFI/debian`) is not changed over, and keeps
its script.

### Compatibility

Script versions never go down: after a rollback to an older slot, the newer script
stays. Two rules follow, for every release and its tests:

- A release's slot boots with the scripts of the releases before it, from 0.17.0 on:
  the kernel and initramfs stay `/vmlinuz` and `/initrd.img` at the slot's root, the
  slot takes the command line those scripts give (`root=PARTUUID=`, `rauc.slot=`,
  nothing it needs that they lack), and its services take a boot without
  `ironflockos.boot_script=` as one of 0.17.0's script. The QEMU test boots this build's
  slot with 0.17.0's script before the change-over.
- A release's script boots the slots of the releases before it, from 0.17.0 on. The
  QEMU test boots the slot of the released 0.17.0 image with this build's script
  (amd64-efi base, under KVM).

Loaders follow the same rules for scripts, and every loader understands every value of
`IRONFLOCKOS_SCRIPT_TRIAL` written before it.

## Not covered

- shim, GRUB and MokManager on the partition are still never updated: a device keeps
  the boot loader binaries it was installed with (their SBAT level, their fixes). That
  is an open point; the same two-path order may carry it later, but a binary has no
  trial in this design.
- The Raspberry Pi and Jetson keep their boot files in the slot.
- GRUB has no watchdog: a script that hangs GRUB (a loop, a command that hangs on some
  firmware) hangs the trial's boot until a person or a power cycle; after that the
  loader runs `boot.cfg`. A script that boots a kernel that hangs before the initramfs
  gives up, without a hardware watchdog, likewise.
- `boot.cfg` in use is not protected by a trial: when GRUB cannot load the kernel of any
  of its entries, it waits in its menu as before, and the last resort is then only in
  the menu.
- A trial boot cut short (a power cut, or a restart by someone, in its first two
  minutes) counts as failed: that version is not tried again on that device.
- A script run in a submenu (a trial's boot) that prints an error, for example
  `serial` on a machine without the port its target names, makes GRUB wait ten seconds
  before its menu, with a message on the screen.
- In a trial's boot, Esc in the drawn menu leaves it, and GRUB goes on with the next
  choice: the script in use, which counts the trial as failed.
- `grubenv` is written by RAUC, the display setting, the real-time tuning and this
  service with `grub-editenv`, which rewrites the file; two writers at the same moment
  can lose one write, as before.

## Alternatives considered

- **An app writes `grub.cfg`.** Rejected (the owner's decision): the boot script
  belongs to the OS, which tests it with the slots it boots, and an app has no way to
  fall back when it is wrong.
- **Replace `grub.cfg` once the slot is proven, without a trial.** A script that does not
  boot on one kind of hardware would leave such devices unbootable, with nobody on site.
  Only the change-over, which keeps the bytes that boot the device, does without a trial.
- **Try the script together with the slot**, in the slot's first boot. A failure could
  not be told apart: a slot that falls back because of its script would fall back to
  the old slot with the new script, and two things change at once. Staging after the
  slot is proven keeps the new slot's first boot on the script that booted the old one.
- **One file whose old copy GRUB falls back to by itself.** GRUB takes the first file it
  can open, so it cannot fall back from a broken `grub.cfg`; the decision has to be in a
  file that does not change, the loader.
- **The loader runs every script in a submenu**, also `boot.cfg` without a trial. It
  would add the last resort to every boot, but it changes what a person and the screen
  see in every boot (the ten-second wait after an error, Esc), so only a trial's boot
  runs that way.

## Consequences

- Every release's script reaches every device from 0.17.0 on with an ordinary update,
  one trial boot after the updated slot has proven itself. A device installed with
  0.17.0 changes over by itself; the first machine needs nothing but the update.
- A script that fails on some hardware costs those devices one boot (one restart more
  when the kernel does not find its root) and is not tried again; the failure is in the
  journal and in `/run/ironflockos/boot-script`.
- Boot-script changes are cheap from now on, and the picture GRUB draws (WP-8.8, parked)
  can come this way.
- Each release keeps both compatibility rules, and the QEMU test proves them.
