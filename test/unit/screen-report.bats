#!/usr/bin/env bats
# /usr/lib/ironflockos/screen-report (docs/build.md, "The screen";
# docs/testing.md, "Hardware checklist"): the report of a boot's screen, run
# against a tree that stands for a device's /, with fakes for the commands it
# asks (systemctl, journalctl, udevadm, docker, grub-editenv, uname, id).

repo="$BATS_TEST_DIRNAME/../.."
lib="$repo/overlay/usr/lib/ironflockos"
report="$lib/screen-report"

setup() {
  tmp=$(mktemp -d)
  r=$tmp/root
  mkdir -p "$tmp/bin" "$tmp/journal" "$r/proc" "$r/etc" "$r/sys/class/graphics/fb0" "$r/dev" "$r/boot/efi/EFI/BOOT" \
    "$r/usr/share/plymouth/themes/ironflockos" "$r/sys/class/tty/tty0" "$r/data/ironflockos/screen"
  : >"$tmp/props"
  # systemctl show -p PROPERTY --value [UNIT]: from $tmp/props, lines of
  # "UNIT PROPERTY VALUE" ("-" for systemd itself); list-units from $tmp/units.
  cat >"$tmp/bin/systemctl" <<SH
#!/bin/bash
case "\$1" in
  show) awk -v u="\${5:--}" -v p="\$3" '\$1 == u && \$2 == p { sub(/^[^ ]+ [^ ]+ /, ""); print }' "$tmp/props" ;;
  list-units) cat "$tmp/units" 2>/dev/null ;;
esac
exit 0
SH
  # journalctl ... [-u UNIT]: $tmp/journal/UNIT, or .../kernel.
  cat >"$tmp/bin/journalctl" <<SH
#!/bin/bash
u=kernel
while [ "\$#" -gt 0 ]; do [ "\$1" != -u ] || u=\$2; shift; done
cat "$tmp/journal/\$u" 2>/dev/null
exit 0
SH
  cat >"$tmp/bin/udevadm" <<SH
#!/bin/bash
f=\${!#}
cat "$tmp/udev/\${f##*/}" 2>/dev/null
SH
  cat >"$tmp/bin/docker" <<SH
#!/bin/bash
case "\$1" in
  ps) cat "$tmp/docker-ps" 2>/dev/null ;;
  inspect) cat "$tmp/docker-inspect" ;;
esac
SH
  printf '#!/bin/bash\n[ "$2" = list ] && cat "$1"\n' >"$tmp/bin/grub-editenv"
  printf '#!/bin/bash\necho "${FAKE_UID:-0}"\n' >"$tmp/bin/id"
  printf '#!/bin/bash\ncase "$1" in -r) echo 6.12.0-rt-amd64 ;; -v) echo "#1 SMP PREEMPT_RT Debian" ;; esac\n' >"$tmp/bin/uname"
  printf '#!/bin/bash\nshift\nexec "$@"\n' >"$tmp/bin/timeout"
  printf '#!/bin/bash\necho "Startup finished in 1.5s (kernel) + 20s (userspace) = 21.5s"\n' >"$tmp/bin/systemd-analyze"
  chmod +x "$tmp/bin"/*
}
teardown() { rm -rf "$tmp"; }

screen_report() {
  PATH="$tmp/bin:$PATH" IRONFLOCKOS_ROOT=$r run bash "$report" "$@"
}

# framebuffer W H BPP PIXEL BOX_X BOX_Y BOX_W BOX_H BOX_PIXEL: $r/dev/fb0, a
# W x H screen of PIXEL (hex, little-endian as in memory) with a box of
# BOX_PIXEL, and its sysfs entries (the fake file has no ioctl).
framebuffer() {
  local w=$1 h=$2 bpp=$3
  perl -e '
    my ($w, $h, $bpp, $px, $bx, $by, $bw, $bh, $bpx, $out) = @ARGV;
    open(my $o, ">", $out) or die; binmode $o;
    for my $y (0 .. $h - 1) { for my $x (0 .. $w - 1) {
      print $o pack("H*", ($x >= $bx && $x < $bx + $bw && $y >= $by && $y < $by + $bh) ? $bpx : $px) } }
  ' "$@" "$r/dev/fb0"
  echo "$w,$h" >"$r/sys/class/graphics/fb0/virtual_size"
  echo "$bpp" >"$r/sys/class/graphics/fb0/bits_per_pixel"
  echo $((w * bpp / 8)) >"$r/sys/class/graphics/fb0/stride"
  echo testdrmfb >"$r/sys/class/graphics/fb0/name"
}

# splash W H RED GREEN BLUE: the theme's picture (only its IHDR) and colour.
splash() {
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR%b%b\x08\x06\x00\x00\x00' \
    "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' 0 0 0 "$1")" "$(printf '\\x%02x\\x%02x\\x%02x\\x%02x' 0 0 0 "$2")" \
    >"$r/usr/share/plymouth/themes/ironflockos/ironflock.png"
  printf '// --- settings ---\nbackground_red = %d;\nbackground_green = %d;\nbackground_blue = %d;\nanimation = "fade";\n' \
    "$3" "$4" "$5" >"$r/usr/share/plymouth/themes/ironflockos/ironflockos.script"
}

# a_boot: a device after a boot with the splash.
a_boot() {
  echo 'NAME="IronFlockOS"
IMAGE_ID=ironflockos-amd64-efi-base-rt
IMAGE_VERSION=0.17.0
BUILD_ID=20261116T000000Z-gabcdef0' >"$r/etc/os-release"
  echo 'root=PARTUUID=x rauc.slot=A quiet splash plymouth.ignore-serial-consoles fbcon=map:9 console=ttyS0,115200' >"$r/proc/cmdline"
  echo tty1 >"$r/sys/class/tty/tty0/active"
  cat >"$tmp/props" <<'P'
- UserspaceTimestampMonotonic 2100000
- FirmwareTimestampMonotonic 0
- LoaderTimestampMonotonic 0
plymouth-quit.service ExecMainStartTimestampMonotonic 14200000
plymouth-quit.service ExecMainExitTimestampMonotonic 14600000
ironflockos-enroll.service ExecMainExitTimestampMonotonic 14100000
docker.service ActiveState active
docker.service ActiveEnterTimestampMonotonic 9800000
ironflock-device-agent.service ActiveState active
ironflock-device-agent.service ActiveEnterTimestampMonotonic 14300000
multi-user.target ActiveEnterTimestampMonotonic 15000000
ironflockos-splash.service ActiveState inactive
ironflockos-splash.service Result success
P
  echo 'keep-splash: Plymouth (pid 312) started 1.84 s after the kernel' >"$tmp/journal/plymouth-quit.service"
  echo 'secureboot: Secure boot disabled' >"$tmp/journal/kernel"
  printf 'abc\ndef\n' >"$tmp/docker-ps"
  printf '/kiosk-app-1 400 0\n/other 500 2\n' >"$tmp/docker-inspect"
  mkdir -p "$r/proc/400" "$r/proc/500"
  echo '400 (chrome main) S 1 400 400 0 -1 4194560 100 0 0 0 0 0 0 0 20 0 1 0 2512 1000' >"$r/proc/400/stat"
  echo '500 (other) S 1 500 500 0 -1 4194560 100 0 0 0 0 0 0 0 20 0 1 0 1800 1000' >"$r/proc/500/stat"
  # Splash at 64x40, XRGB with the X byte set, a 10x6 picture centred.
  splash 10 6 32 64 96
  framebuffer 64 40 32 604020ff 27 17 10 6 ffffffff
}

@test "screen-report: usage errors, --help, and root only" {
  screen_report --bogus
  [ "$status" -eq 2 ] && [[ "$output" == "usage: screen-report [--app NAME] [--screenshot FILE]" ]]
  screen_report --app
  [ "$status" -eq 2 ]
  screen_report --screenshot ""
  [ "$status" -eq 2 ]
  screen_report --help
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "  screen-report [--app NAME] [--screenshot FILE]" ]]
  [[ "$output" == *"--screenshot FILE  the framebuffer device's picture into FILE"* ]]
  FAKE_UID=1000 screen_report
  [ "$status" -eq 1 ] && [ "$output" = "screen-report: run as root" ]
}

@test "screen-report: the timeline in order, from the kernel's start and from the reset by FPDT" {
  a_boot
  mkdir -p "$r/sys/firmware/acpi/fpdt/boot"
  echo 500000000 >"$r/sys/firmware/acpi/fpdt/boot/firmware_start_ns"
  echo 7000000000 >"$r/sys/firmware/acpi/fpdt/boot/bootloader_launch_ns"
  echo 9500000000 >"$r/sys/firmware/acpi/fpdt/boot/exitbootservice_end_ns"
  screen_report --app kiosk
  [ "$status" -eq 0 ]
  t=$(sed -n '/^== The boot.s timeline/,/^$/p' <<<"$output")
  echo "$t"
  [[ "$t" == *"    -9.00       0.50  the firmware runs (FPDT)"* ]]
  [[ "$t" == *"    -2.50       7.00  the boot loader starts: shim, GRUB, its 2 s (FPDT)"* ]]
  [[ "$t" == *"     0.00       9.50  the kernel takes over from the firmware (FPDT: ExitBootServices)"* ]]
  [[ "$t" == *"     1.84      11.34  Plymouth starts (keep-splash's record in the journal)"* ]]
  [[ "$t" == *"     2.10      11.60  the initramfs ends: systemd starts in the root filesystem"* ]]
  [[ "$t" == *"    14.20      23.70  keep-splash takes the screen over from Plymouth"* ]]
  [[ "$t" == *"    25.12      34.62  the container kiosk-app-1 starts (--app; its first process, /proc; restarted 0 times)"* ]]
  [[ "$t" == *"    18.00      27.50  the first container now running starts: other (its first process, /proc)"* ]]
  # In time order.
  [ "$(grep -oE '^ +-?[0-9]+\.[0-9]{2}' <<<"$t" | tr -d ' ')" = "$(grep -oE '^ +-?[0-9]+\.[0-9]{2}' <<<"$t" | tr -d ' ' | sort -g)" ]
  # GRUB hands systemd no times, and the -rt kernel has no EFI runtime services: said, not guessed.
  [[ "$t" == *"the firmware's and the boot loader's times by systemd: not available: GRUB hands systemd none (LoaderTimeExecUSec) (the -rt kernel turns the EFI runtime services off)"* ]]
  [[ "$output" == *"system: IronFlockOS 0.17.0, image ironflockos-amd64-efi-base-rt, build 20261116T000000Z-gabcdef0"* ]]
  [[ "$output" == *"slot: A"* ]]
  [[ "$output" == *"Secure Boot: secureboot: Secure boot disabled"* ]]
}

@test "screen-report: without FPDT, Plymouth or containers, each is not available with why; an --app that matches nothing lists the containers" {
  a_boot
  rm "$tmp/journal/plymouth-quit.service"
  screen_report --app nothing-like-it
  [ "$status" -eq 0 ]
  [[ "$output" == *"     0.00          -  the kernel starts"* ]]
  [[ "$output" == *"power-on: not available: the firmware reports no times in ACPI's FPDT (/sys/firmware/acpi/fpdt/boot)"* ]]
  [[ "$output" == *"Plymouth's start: not available: keep-splash recorded none this boot"* ]]
  [[ "$output" == *"the container of --app nothing-like-it: not available: no running container's name contains it; running: kiosk-app-1 other"* ]]
  : >"$tmp/docker-ps"
  screen_report
  [[ "$output" == *"the first container's start: not available: no container runs"* ]]
  # An empty device: every item said, the report written.
  rm -rf "$r" "$tmp/props" "$tmp/journal" && mkdir -p "$r" && : >"$tmp/props"
  screen_report
  [ "$status" -eq 0 ]
  [[ "$output" == *"framebuffer: not available: no /dev/fb0 with its geometry"* ]]
  [[ "$output" == *"the framebuffer's pixels: not available"* ]]
  [[ "$output" == *"board, firmware: not available: no DMI table"* ]]
  [[ "$output" == *"Plymouth crashed this boot: no"* ]]
}

@test "screen-report: the framebuffer's background share, the rest's box against the splash's place, and the screenshot" {
  a_boot
  screen_report --screenshot "$tmp/shot.ppm"
  [ "$status" -eq 0 ]
  [[ "$output" == *"framebuffer: /dev/fb0 testdrmfb, 64x40 shown of 64x40 from 0,0, 32 bits a pixel (red 16/8, green 8/8, blue 0/8), 256 bytes a line (sysfs; the format assumed)"* ]]
  [[ "$output" == *"its place: x 27..36, y 17..22 (10x6, centred)"* ]]
  [[ "$output" == *"corner pixel: #204060"* ]]
  # 2560 pixels, 60 of the picture.
  [[ "$output" == *"background #204060: 97.66 % of the 2560 pixels"* ]]
  [[ "$output" == *"the rest: x 27..36, y 17..22 (10x6): inside the splash's place"* ]]
  [[ "$output" == *"screenshot: $tmp/shot.ppm (PPM, 64x40)"* ]]
  [ "$(head -c 13 "$tmp/shot.ppm")" = "$(printf 'P6\n64 40\n255\n')" ]
  [ "$(wc -c <"$tmp/shot.ppm" | tr -d ' ')" -eq $((13 + 64 * 40 * 3)) ]
  [ "$(od -An -tx1 -j 13 -N 3 "$tmp/shot.ppm" | tr -d ' \n')" = 204060 ]
  [ "$(od -An -tx1 -j $((13 + (17 * 64 + 27) * 3)) -N 3 "$tmp/shot.ppm" | tr -d ' \n')" = ffffff ]
  # A picture out of its place, and a screen of the background only.
  framebuffer 64 40 32 604020ff 0 0 4 4 ffffffff
  screen_report
  [[ "$output" == *"the rest: x 0..3, y 0..3 (4x4): outside it"* ]]
  framebuffer 64 40 32 60402000 0 0 0 0 00
  screen_report
  [[ "$output" == *"background #204060: 100.00 %"* ]] && [[ "$output" == *"the rest: nothing, the background only"* ]]
  # A picture larger than the screen is made smaller to fit, then centred.
  splash 128 20 32 64 96
  screen_report
  [[ "$output" == *"its place: x 0..63, y 15..24 (64x10, centred)"* ]]
}

@test "screen-report: 16 bits a pixel: the background within one step of each channel" {
  a_boot
  # #204060 in RGB565 rounded (0x2208 + blue 12) and a pixel one blue step off.
  framebuffer 32 8 16 0c22 0 0 1 1 0b22
  splash 4 4 32 64 96
  screen_report
  [[ "$output" == *"16 bits a pixel (red 11/5, green 5/6, blue 0/5)"* ]]
  [[ "$output" == *"background #204060: 100.00 % of the 256 pixels"* ]]
  framebuffer 32 8 16 0c22 31 7 1 1 ffff
  screen_report
  [[ "$output" == *"the rest: x 31..31, y 7..7 (1x1): outside it"* ]]
}

@test "screen-report: whether the framebuffer device is what the screen shows, by debugfs, else by /proc" {
  a_boot
  mkdir -p "$r/sys/kernel/debug/dri/0"
  state() {
    printf 'plane[31]: plane 1A\n\tcrtc=pipe A\n\tfb=%s\n\t\tallocated by = %s\n\t\trefcount=2\n\t\tsize=1920x1080\n\tcrtc-pos=1920x1080+0+0\n' "$1" "$2"
    printf 'plane[40]: cursor A\n\tcrtc=(null)\n\tfb=0\n\tcrtc-pos=0x0+0+0\n'
    printf 'crtc[51]: pipe A\n\tenable=1\n\tactive=1\n\tmode: "1920x1080": 60 148500 1920 2008 2052 2200 1080 1084 1089 1125 0x48 0x5\n'
    printf 'connector[236]: eDP-1\n\tcrtc=pipe A\nconnector[240]: DP-1\n\tcrtc=(null)\n'
  }
  state 100 '[fbcon]' >"$r/sys/kernel/debug/dri/0/state"
  # The card, its driver and its connector, as sysfs links them.
  mkdir -p "$r/sys/devices/pci0000:00/0000:00:02.0" "$r/sys/bus/pci/drivers/i915" "$r/sys/class/drm/card0" "$r/sys/class/drm/card0-eDP-1"
  ln -s ../../../bus/pci/drivers/i915 "$r/sys/devices/pci0000:00/0000:00:02.0/driver"
  echo 0x8086 >"$r/sys/devices/pci0000:00/0000:00:02.0/vendor" && echo 0x9a49 >"$r/sys/devices/pci0000:00/0000:00:02.0/device"
  ln -s ../../../devices/pci0000:00/0000:00:02.0 "$r/sys/class/drm/card0/device"
  echo connected >"$r/sys/class/drm/card0-eDP-1/status" && echo enabled >"$r/sys/class/drm/card0-eDP-1/enabled"
  echo On >"$r/sys/class/drm/card0-eDP-1/dpms" && printf '1920x1080\n1680x1050\n' >"$r/sys/class/drm/card0-eDP-1/modes"
  screen_report
  [[ "$output" == *"card0: driver i915, device 0000:00:02.0 (0x8086:0x9a49)"* ]]
  [[ "$output" == *"  card0-eDP-1: connected, enabled, dpms On, preferred mode 1920x1080"* ]]
  [[ "$output" == *"  CRTC pipe A: active=1, mode 1920x1080 at 60 Hz"* ]]
  [[ "$output" == *"  connector eDP-1 on pipe A"* ]] && [[ "$output" != *"connector DP-1"* ]]
  [[ "$output" == *"  plane plane 1A on pipe A: framebuffer of [fbcon], 1920x1080+0+0"* ]]
  [[ "$output" == *"shown: the framebuffer device: the planes on the screen show its framebuffer, [fbcon] (debugfs)"* ]]
  state 120 chrome >"$r/sys/kernel/debug/dri/0/state"
  screen_report
  [[ "$output" == *"shown: NOT the framebuffer device: a program draws, chrome (the planes' framebuffers in debugfs)"* ]]
  # Without debugfs: who has the graphics device open.
  rm -r "$r/sys/kernel/debug"
  screen_report
  [[ "$output" == *"modes on the screen: not available: no readable debugfs state"* ]]
  [[ "$output" == *"shown: the framebuffer device: no process has the graphics device open (/proc)"* ]]
  mkdir -p "$r/proc/77/fd" && echo cage >"$r/proc/77/comm" && ln -s /dev/dri/card0 "$r/proc/77/fd/9"
  screen_report
  [[ "$output" == *"shown: perhaps not the framebuffer device: the graphics device is open in cage(77)"* ]]
}

@test "screen-report: input devices with udev's ID_INPUT properties, which is a touch screen and which a keyboard" {
  a_boot
  mkdir -p "$r/sys/class/input/event0/device" "$r/sys/class/input/event1/device" "$tmp/udev"
  echo 'USB Touch Panel' >"$r/sys/class/input/event0/device/name"
  echo 'USB Keyboard' >"$r/sys/class/input/event1/device/name"
  printf 'ID_INPUT=1\nID_INPUT_TOUCHSCREEN=1\nID_BUS=usb\nID_VENDOR_ID=0eef\n' >"$tmp/udev/event0"
  printf 'ID_INPUT=1\nID_INPUT_KEY=1\nID_INPUT_KEYBOARD=1\nID_BUS=usb\n' >"$tmp/udev/event1"
  screen_report
  [[ "$output" == *"event0: USB Touch Panel; ID_INPUT=1: touchscreen; ID_BUS=usb ID_VENDOR_ID=0eef"* ]]
  [[ "$output" == *"event1: USB Keyboard; ID_INPUT=1: key,keyboard; ID_BUS=usb"* ]]
}

@test "screen-report: the keys: GRUB's menu entries, the console password without its hash, the firmware's setup" {
  a_boot
  . "$repo/build/lib.sh"
  load_conf "$repo/targets/amd64-efi/target.conf"
  render "$repo/targets/amd64-efi/grub/grub.cfg" >"$r/boot/efi/EFI/BOOT/grub.cfg"
  hash='$6$saltsalt$ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZabcdefgh'
  mkdir -p "$r/opt/ironflock/device-init"
  echo '{"user": {"name": "owner"}}' >"$r/opt/ironflock/device-init/installed.json"
  printf 'root:*:20000::::::\nowner:%s:20000::::::\n' "$hash" >"$r/etc/shadow"
  echo "$hash" >"$r/data/ironflockos/console-password"
  chmod 600 "$r/data/ironflockos/console-password"
  echo "getty@tty2.service loaded active running Getty on tty2" >"$tmp/units"
  screen_report
  [[ "$output" == *'boot menu "Start with messages": in grub.cfg'* ]]
  [[ "$output" == *'boot menu "Firmware setup": in grub.cfg'* ]]
  [[ "$output" == *"grub.cfg: with the splash"* ]]
  [[ "$output" == *"login prompts: getty@tty2.service (logind"* ]]
  [[ "$output" == *"console password: owner's password is a SHA-512 hash; the file: -rw-------"* ]]
  [[ "$output" != *saltsalt* ]]
  [[ "$output" == *"restart into the firmware's setup: not available: no EFI variables (the -rt kernel turns the EFI runtime services off)"* ]]
  mkdir -p "$r/sys/firmware/efi/efivars"
  printf '\x06\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00' >"$r/sys/firmware/efi/efivars/OsIndicationsSupported-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  screen_report
  [[ "$output" == *"restart into the firmware's setup: supported (OsIndicationsSupported)"* ]]
}

@test "screen-report: the splash's files and services, the last refusal, and a splash changed during this boot" {
  a_boot
  printf 'background=#204060\nanimation=none\n' >"$r/data/ironflockos/screen/splash.conf"
  echo 'no picture' >"$r/data/ironflockos/screen/splash.png"
  printf 'IRONFLOCKOS_SPLASH_BACKGROUND=#204060\n' >"$r/boot/efi/EFI/BOOT/splash.env"
  echo 'splash: refused: splash.png is not a PNG; the splash stays as it was' >"$tmp/journal/ironflockos-splash.service"
  screen_report
  [[ "$output" == *"splash.png: 11 bytes, splash: splash.png is not a PNG"* ]]
  [[ "$output" == *"splash.conf: 34 bytes, taken"* ]] && [[ "$output" == *"  animation=none"* ]]
  [[ "$output" == *"splash.env, GRUB's colour: IRONFLOCKOS_SPLASH_BACKGROUND=#204060"* ]]
  [[ "$output" == *"splash.cpio: none (IronFlock's logo on black)"* ]]
  [[ "$output" == *"ironflockos-splash.service: inactive (), result success"* ]]
  [[ "$output" == *"last refusal: splash: refused: splash.png is not a PNG"* ]]
  [[ "$output" != *"the splash changed during this boot"* ]]
  echo "splash: the splash from the next boot on: the device's picture, background #204060, animation none" >>"$tmp/journal/ironflockos-splash.service"
  screen_report
  [[ "$output" == *"note: the splash changed during this boot"* ]]
}

@test "screen-report changes nothing on the device, and nothing runs it at boot" {
  a_boot
  mkdir -p "$r/sys/kernel/debug/dri/0" && echo 'crtc[1]: x' >"$r/sys/kernel/debug/dri/0/state"
  before=$(cd "$r" && find . -print0 | sort -z | xargs -0 ls -ld | cksum; find . -type f -exec cksum {} + | sort)
  screen_report --app kiosk --screenshot "$tmp/shot.ppm"
  [ "$status" -eq 0 ]
  [ "$(cd "$r" && find . -print0 | sort -z | xargs -0 ls -ld | cksum; find . -type f -exec cksum {} + | sort)" = "$before" ]
  [ -x "$report" ]
  ! grep -rl 'screen-report' "$repo/overlay/usr/lib/systemd" "$repo/overlay/usr/lib/udev" "$repo/overlay/etc" \
    "$repo/profiles" "$repo/targets" "$repo/build"
}
