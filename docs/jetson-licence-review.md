# Jetson licence review

Status: technical review of 2026-11-07 (WP-6.1); signed off by IronFlock on
2026-11-17 (WP-6.8), with the answers in "Questions for legal". The sign-off meets the
condition of [ADR-0008](adr/0008-jetson-orin-bsp-jetpack-7.md).

This document is not legal advice. It collects what the licence texts of Jetson Linux
r39.2.1 say, what IronFlockOS distributes, and what IronFlockOS does to meet the terms. The
texts were read from the files NVIDIA ships, not from summaries.

Evidence for the eight questions at the end (primary texts, NVIDIA's and Canonical's
public statements, what other distributors visibly do, export rules) is collected in
[jetson-licence-research.md](jetson-licence-research.md) (2026-11-17). It answers none
of them; it says where the evidence points and what to ask whom.

## What was read

- The **NVIDIA Driver License Agreement**: the BSP's
  `Tegra_Software_License_Agreement-Tegra-Linux.txt` of r39.2.1 (SHA-1
  `e331f3658ad9569817848036b6889d2bedcab18a`, as in NVIDIA's `release_sha_hashes.txt`).
  The file keeps its old name, but its text is the Driver License Agreement. The
  `copyright` file of every `nvidia-l4t-*` package IronFlockOS installs carries the same
  text, and so does `/usr/share/doc/nvidia-l4t-core/`. NVIDIA's JetPack EULA page
  names the same agreement (v. 2023-11-23) for "JetPack OS". Its section 1.1(d) says
  "operating systems", while the r39.2.1 copy (v. 2025-02-25) says "operating system
  kernels"; this review uses the r39.2.1 copy. That copy names NVIDIA's contact for
  questions about the Agreement, `driver-licensing@nvidia.com` (section 20).
- The per-component `LICENSE.*` and `NOTICE.*` files of the 22 packages in
  `targets/jetson-orin/packages`, of `nvidia-l4t-bootloader`, and of the BSP tarball
  (`bootloader/`, `kernel/`, `generate_capsule/`, `tools/`, `nv_tegra/`).
- `NVIDIA_Trademark_License_Addendum_SW.pdf` in `nvidia-l4t-tools`.
- The contents of NVIDIA's `public_sources.tbz2` of r39.2.1.
- Canonical's intellectual property policy, because the userspace is Ubuntu.

## What IronFlockOS distributes

| Artefact | NVIDIA content | Channel | State |
|----------|----------------|---------|-------|
| Slot image `<image-id>-<version>.rootfs.ext4.zst` and bundle `.raucb` | The `nvidia-l4t-*` packages the target lists and their dependencies, and the container toolkit, installed by dpkg from NVIDIA's repositories | Download server `ironflockos/<version>/`, appliance OS mirror, the device-agent; the flash kit takes the slot image | Built in CI (WP-6.2); in the release pipeline behind `JETSON_RELEASE`, with `NVIDIA-LICENSE.txt` and the source mirror (WP-6.8) |
| Flash package | Bootloader binaries, BCTs and partition images that NVIDIA's tools make from the BSP; NVIDIA's host flash tools; two NVIDIA scripts with IronFlockOS's `-r` fix; the layout `build/tegra-layout.py` makes from NVIDIA's XML | None: made on the user's host by the flash kit | Built in CI as a test, never published (questions 1 and 2) |
| Flash kit `ironflockos-jetson-flash-kit-<version>.tar.gz` | None: IronFlockOS's scripts, which download the BSP and the Agreement from NVIDIA on the user's host (point 4) | Download server `ironflockos/<version>/` | Built in CI (WP-6.4); in the release pipeline behind `JETSON_RELEASE` (WP-6.8) |
| `NVIDIA-LICENSE.txt` | NVIDIA's Driver License Agreement, byte for byte the BSP's, fetched from NVIDIA by the build | Download server `ironflockos/<version>/`, next to the Jetson files (point 2) | In the release pipeline behind `JETSON_RELEASE` (WP-6.8) |
| Source mirror `ironflockos/sources/l4t-<L4T version>/` | NVIDIA's `public_sources.tbz2` and the `libnvidia-container` source of its tag | Download server (point 3) | In the release pipeline behind `JETSON_RELEASE` (WP-6.8) |
| Orin Nano SD image | The same for an SD card: kernel, DTB, ESP with L4TLauncher, recovery | None | Not made (question 1) |
| QSPI capsules `TEGRA_BL_*.Cap` | The bootloader binaries (MB1, MB2, BPMP, SPE, RCE, UEFI, OP-TEE, TF-A) in one capsule per carrier board, NVIDIA's own from `nvidia-l4t-bootloader` | In the slot image and the bundle (`/opt/ota_package/t23x`, WP-6.5) | Built in CI (WP-6.5) |
| Repository | `targets/jetson-orin/apt/jetson-ota-public.asc`, NVIDIA's apt key as `repo.download.nvidia.com` serves it, without a licence header (point 7) | GitHub, public, Apache-2.0 | Now |

IronFlockOS does not distribute NVIDIA's sample root filesystem (ADR-0008). It also does not
distribute the JetPack SDK components (CUDA toolkit, cuDNN, TensorRT). These have their
own agreements, such as the CUDA EULA with its list of distributable files. Containers
bring these components. `nvidia-l4t-cuda` is the driver's `libcuda`, under the Driver
License Agreement. If the image gets a JetPack SDK component later, that component needs
a review of its own.

## The NVIDIA Driver License Agreement

The section numbers are those of the r39.2.1 text.

| Section | Says | For IronFlockOS |
|---------|------|-------------|
| 1.1(d) | You may distribute the SOFTWARE for use with operating system kernels under an OSI-approved open source licence, provided that (i) the binary files are not modified in any way (except for uncompressing compressed files) and (ii) this Agreement is provided to each SOFTWARE recipient | This is the grant IronFlockOS depends on. Linux is GPLv2, so it qualifies. NVIDIA's binaries must stay unchanged, and everyone who gets an image must get the Agreement |
| 1.1(b) | You may modify and create derivative works of the parts NVIDIA delivers in source code form | The layout IronFlockOS generates from NVIDIA's XML (`LicenseRef-NvidiaProprietary`) is such a change (question 2). The two flash scripts IronFlockOS fixes are not under this section: in r39.2.1 they carry `SPDX-License-Identifier: MIT` (`l4t_initrd_flash.func`, `l4t_create_images_for_kernel_flash.sh`) |
| 2.1 | Only for NVIDIA's chips (the "NVIDIA Platform"); firmware only on them | The packages go only into `jetson-orin` images, and `nvidia-l4t-core` refuses other boards |
| 2.2, 2.3, 2.4 | No reverse engineering, no changes to or derivative works of binaries, no modified headers | |
| 2.5 | Keep copyright and proprietary notices; a modified file must carry a prominent notice that it was changed | `/usr/share/doc/nvidia-l4t-*` stays in the image |
| 2.6 | Do not bypass technical limits or security mechanisms | Masking `nv-l4t-bootloader-config` and `nv-rootfs-validation-config` disables no security mechanism; IronFlockOS's lane 2 and health gate do their work |
| 2.7 | Except as granted, you may not sell, rent, sublicense, distribute or transfer the SOFTWARE, or provide commercial hosting services with it. The licence is non-sublicensable | The recipient's licence comes from NVIDIA through the Agreement, not from IronFlockOS. IronFlockOS's Apache-2.0 does not cover NVIDIA's parts |
| 2.9 | Do not use the SOFTWARE in a way that would make it subject to an open source licence | An image that holds NVIDIA's binaries next to GPL programs is an aggregate; IronFlockOS links nothing to NVIDIA's binaries |
| 2.10 | Not tested or certified for Critical Applications (avionics, navigation, autonomous vehicles, automotive, military, medical, life support); the licensee is responsible for safety and redundancy | Applies to IronFlock's customers |
| 2.11 | The licensee defends and indemnifies NVIDIA against claims from products or services developed with or using the SOFTWARE | A business risk for IronFlock |
| 7 | Ends automatically on a breach; earlier distributions are not affected | |
| 14, 18 | No assignment without NVIDIA's written consent; the Agreement changes only in a writing signed by both parties | A forum answer by NVIDIA's staff changes nothing; a written confirmation would (questions 1, 2, 8) |
| 8 | Cooperate with NVIDIA to verify compliance | |
| 12 | NVIDIA's liability is limited to US$5 | |
| 15 | Comply with export, import and sanctions law | |
| 10 | Arbitration (JAMS, Santa Clara), Delaware law | |

## Other licences inside

| Component | Licence | What it asks |
|-----------|---------|--------------|
| Kernel `Image`, out-of-tree modules, DTBs (`nvidia-l4t-kernel`, `-kernel-oot-modules`, `-kernel-nvgpu`, `-kernel-dtbs`) | GPL-2.0; `nvgpu` GPL-2.0-only with MIT parts | The corresponding source. NVIDIA's notice points to `source_sync.sh` or `oss-requests@nvidia.com`. NVIDIA's `public_sources.tbz2` (295 MB) holds the kernel, the out-of-tree modules and `nvgpu` |
| `libnvidia-container1` | Apache-2.0, LGPL-3.0+, BSD-3-Clause, MIT | The LGPL parts' source (GitHub, tag `v1.19.1`) |
| `nvidia-container-toolkit` | Apache-2.0 | Notices |
| `nvidia-l4t-init` configs, `nvethernetrm`, display parts | MIT | Notices |
| NVDLA (FlatBuffers), `tipc_test`, the BSD parts of `nvbootctrl` | Apache-2.0, BSD | Notices |
| Realtek Wi-Fi and Bluetooth firmware (`nvidia-l4t-firmware`) | Realtek's binary licence: redistribution without modification, notice reproduced, no reverse engineering | Unchanged, with the notice |
| PVA firmware (`nvidia-l4t-firmware`, `NOTICE.nvpva-fw`) | In addition to the Agreement: you may not communicate or publish any performance or statistical data specific to this firmware | IronFlockOS publishes no PVA figures |
| SPE firmware (`spe_t234.bin`: bootloader, capsule) | FreeRTOS V8.1.2 under a modified GPL with an exception | Every copy must come with a written statement of the FreeRTOS version and the distributor's own offer to provide its source. Clause 2 forbids publishing FreeRTOS run-time or compile-time metrics. `public_sources.tbz2` holds `FreeRTOSV8.1.2_src.tbz2` and `spe-freertos-bsp.tbz2` |
| UEFI (L4TLauncher `BOOTAA64.efi`, `uefi_t23x_*.bin`), Standalone MM | BSD-2-Clause-Patent, with NVIDIA's proprietary parts | Notices |
| OP-TEE, TF-A | BSD | Notices; the source is in `public_sources.tbz2` |
| MB1, MB2, BPMP, RCE, ADSP | NVIDIA proprietary (the Agreement), with BSD and MIT parts | As the Agreement |
| NVIDIA trademarks | The trademark addendum: the NVIDIA logos and the word "Jetson" may be used on goods that use NVIDIA products, following NVIDIA's guidelines, but not in a way that suggests NVIDIA provides or supervises the goods | Board names in text, no logos |

**Ubuntu.** Canonical's IP policy (2015-07-15) says that a modified version of Ubuntu may
be redistributed only if Canonical approves, certifies or provides it. Otherwise the
Ubuntu trademarks must be removed and replaced, and the binaries recompiled. The policy
also says that Ubuntu is an aggregate work, and that it does not reduce the rights the
licences of its packages grant. IronFlockOS's `jetson-orin` image carries IronFlockOS's name and
uses Canonical's binaries from `ports.ubuntu.com`, unchanged. Its `os-release` is IronFlockOS's own
(`ID_LIKE="ubuntu debian"`). Ubuntu's `base-files` puts Ubuntu's name into
`/etc/lsb-release`, `/etc/issue`, `/etc/issue.net`, `/etc/legal` and the scripts in
`/etc/update-motd.d`. Systems built from Ubuntu's binaries replace these with their own
and keep the technical references (the codename, the `ubuntu` version strings, the
package names). The image does the same (point 10; WP-6.8;
[research](jetson-licence-research.md), question 7).

## What IronFlockOS does

1. **NVIDIA's packages stay unchanged.** dpkg installs them from NVIDIA's repositories at
   the pinned version. The build changes none of their files. It writes its own
   `extlinux.conf`, masks two of NVIDIA's units, and leaves out `nvidia-l4t-extlinux`,
   `-apt-source` and `-configs` (target notes). The build excludes no
   documentation, so `/usr/share/doc/nvidia-l4t-*` keeps the Agreement and the notices.
   A check in `test/image/jetson-rootfs-check.sh` makes this a rule: every installed
   `nvidia-l4t-*` package has its `copyright` file, also where its doc directory links
   to another package's (built, WP-6.8). At the pins, each of the 20 `nvidia-l4t-*`
   packages the image installs has its own `copyright`.
2. **The Agreement goes with every Jetson file.** NVIDIA's text, byte for byte the BSP's,
   is published as `NVIDIA-LICENSE.txt` next to the Jetson files in `ironflockos/<version>/`.
   The release notes link it. FlockFlasher shows it before it writes a Jetson image.
   Devices that update over the air get it inside the bundle (WP-6.8). As built: the
   Jetson image's build fetches the Agreement from NVIDIA (`BSP_LICENSE_URL`), checked
   against NVIDIA's SHA-1 list and the SHA-256 pinned in `bsp.conf`, and puts it next to
   the image (`build/jetson-release.sh files`); `stage` checks it against the pin again
   and publishes it with the slot image, the bundle and the flash kit, in `SHA256SUMS`.
   The repository holds no copy. A release with Jetson files fails when its notes do not
   link `<DL_BASE>/ironflockos/<version>/NVIDIA-LICENSE.txt` ([release.md](release.md),
   "Jetson"). In the image and the bundle the Agreement is each `nvidia-l4t-*` package's
   `copyright`, and `/usr/share/doc/nvidia-l4t-core/Tegra_Software_License_Agreement-Tegra-Linux.txt.gz`
   is the BSP's text byte for byte (the root tree check holds it to the pin).
   FlockFlasher writes no Jetson image yet (WP-6.6).
3. **IronFlockOS mirrors NVIDIA's sources.** Each Jetson release puts NVIDIA's
   `public_sources.tbz2` of its L4T version, and the `libnvidia-container` source of its
   tag, on the download server (`ironflockos/sources/l4t-<version>/`). For files
   downloaded from that server this is more than an offer: source at the same place
   counts as distributing the source (GPLv2 section 3, last paragraph). The other
   channels (the appliance's OS mirror, updates over the air, FlockFlasher, devices a
   partner installs) need the source at their place too, or IronFlock's written offer,
   valid three years (question 6). Passing on NVIDIA's offer (GPLv2 section 3(c)) is
   allowed only for noncommercial distribution. The same mirror holds FreeRTOS for the
   capsule's offer (WP-6.8). As built: both files are pinned by URL and SHA-256 in
   `bsp.conf` (NVIDIA publishes no hash for the sources tarball: the pin comes from one
   download of 2026-11-17, 309,583,176 bytes); `release/sources` gives each
   `nvidia-l4t-*` source package its decision (the sources tarball for the kernel, its
   modules, the device trees, the display driver and the boot firmware; no source, with
   the reason, for the packages under the Agreement without copyleft parts), and the
   release's `sources` job mirrors them to `ironflockos/sources/l4t-<L4T version>/`. The
   Ubuntu packages of the image get their source packages from Ubuntu's archive, or from
   Launchpad when the archive no longer has the version, into the release's pool
   (`ironflockos/sources/ubuntu/`), as the Debian packages do. `nvidia-l4t-initrd`'s
   initrd carries Ubuntu programs under the GPL and LGPL whose package versions NVIDIA
   does not name and whose source the sources tarball does not hold; its decision is
   open, and a release with Jetson files stops until it is made.
4. **IronFlockOS does not publish the flash package.** CI still makes it on every pull request
   as a test. Users get a flash kit instead: IronFlockOS's own scripts. On the flashing host,
   the kit downloads the pinned BSP from NVIDIA, checks it against the SHA-256 in
   `bsp.conf`, and runs what CI runs (`build/tegra-flash-package.sh`) with the published
   slot image. The user gets the BSP from NVIDIA under the Agreement. IronFlockOS then
   distributes no NVIDIA-made bootloader images, no changed NVIDIA scripts and no
   derived layout. IronFlockOS publishes the package itself only if legal answers
   questions 1 and 2 with yes (WP-6.4). As built (WP-6.4): the kit also downloads the
   Agreement from NVIDIA (`Tegra_Software_License_Agreement-Tegra-Linux.txt` next to the
   BSP, pinned by SHA-256 in `bsp.conf` and checked against NVIDIA's SHA-1 list), shows it
   and asks for acceptance before it unpacks or runs anything of NVIDIA's;
   `--accept-nvidia-license` accepts it without the question and still prints it
   (question 3). The kit holds no file of NVIDIA's.
5. **The Orin Nano SD image waits for question 1.** It holds partition images that
   NVIDIA's tools make. If the answer is no, the developer kit also uses the flash kit
   (WP-6.4). Answered on 2026-11-17: not relied on, so there is no SD image and the
   developer kit uses the flash kit.
6. **The QSPI capsule is NVIDIA's own where NVIDIA ships one.** `nvidia-l4t-bootloader`
   at the pinned version has prebuilt capsules for NVIDIA's carrier boards
   (`/opt/ota_package/t23x/TEGRA_BL_3767*.Cap` for Orin NX and Nano,
   `TEGRA_BL_3701*.Cap` for AGX Orin). The bundle carries the capsule unchanged. WP-6.5
   checks that the capsule matches the QSPI firmware the flash kit writes.
   `l4t_generate_soc_capsule.sh` makes capsules only for carriers NVIDIA ships none for,
   and only after legal answers question 1 with yes. The bundle carries the FreeRTOS
   statement: version 8.1.2, and the offer that points at the source mirror (WP-6.5).
   As built: `nvidia-l4t-bootloader` is installed in the image, so the capsules reach
   the bundle with the package's own `copyright` (the Agreement) and
   `LICENSE.bl_update_payload.gz` (the FreeRTOS licence); the build writes the
   statement to `/usr/share/doc/ironflockos/FreeRTOS-source-offer.txt` and fails when a
   capsule's version is not the BSP pin's (`build/tegra-capsules.sh`). The statement
   names IronFlock GmbH as the one that offers the source, and its postal address and
   legal@ironflock.com for requests (`release/contact`), next to the mirror's URL; the
   build fails when the statement does not carry the mirror or the contact (WP-6.8).
7. **The repository holds no file under NVIDIA's licence.** NVIDIA's layout files stay
   out already. `jetson-ota-public.asc` is the key as NVIDIA serves it at
   `https://repo.download.nvidia.com/jetson/jetson-ota-public.asc`: the same key block
   as `nvidia-l4t-apt-source` 39.2.1 (dearmored bytes identical), the same fingerprint,
   `3C6D1FF3100C8C3ABB0869C0E6543461A9996195`, and no licence header. A unit test
   checks that the file has none (built, WP-6.8).
8. **Names, not logos.** IronFlockOS's documents and FlockFlasher name the boards in text,
   for example "NVIDIA Jetson Orin Nano Developer Kit". They show no NVIDIA logos and say
   nothing that suggests NVIDIA provides or supports IronFlockOS.
9. **No PVA or FreeRTOS figures.** IronFlockOS publishes no performance data of the PVA
   firmware or of FreeRTOS on the SPE. The real-time figures of WP-6.7 measure Linux on
   the CPU cores.
10. **IronFlockOS's name, Ubuntu's technical references.** The image follows what
    systems built from Ubuntu's binaries visibly do. It ships Canonical's binary
    packages unchanged and replaces the visible Ubuntu branding with its own. Where the
    base is named, the text is "IronFlockOS, based on Ubuntu 24.04". As built
    (`build/branding.sh`, `overlay/etc/issue`; WP-6.8):
    - the login prompt shows `os-release`'s `PRETTY_NAME`, for example "IronFlockOS
      0.18.0 (jetson-orin, base)"; `/etc/issue.net` says "IronFlockOS". Every target
      has the same prompt;
    - `/etc/lsb-release` has `DISTRIB_ID=IronFlockOS` and
      `DISTRIB_DESCRIPTION="IronFlockOS <version>, based on Ubuntu 24.04"`;
      `DISTRIB_RELEASE=24.04` and `DISTRIB_CODENAME=noble` stay. Nothing in the image
      needs `DISTRIB_ID=Ubuntu`: `lsb_release` answers from `os-release`, and NVIDIA's
      `nvidia-bug-report-jetson.sh` reads the ID only to print an install hint;
    - `/etc/legal` and Ubuntu's `update-motd.d` scripts (header, help text with
      Canonical's links, motd-news) are gone, `motd-news.timer` is masked, and nothing
      fetches `motd.ubuntu.com`. The login banner is IronFlockOS's `/etc/motd`;
    - `ubuntu-pro-client` is not installed: nothing the image lists depends on it, and
      Recommends are not installed;
    - kept: `ID_LIKE="ubuntu debian"`, the package names, the `ubuntu` version
      strings, `/etc/dpkg/origins/ubuntu`, the apt sources at `ports.ubuntu.com` and
      Ubuntu's archive keyring;
    - no Ubuntu logo: the image has no Plymouth theme or desktop on Jetson, and the
      build removes the logos `base-files` puts into `/usr/share/pixmaps`.

    `test/image/jetson-rootfs-check.sh` checks each of these on the built tree.

## Questions for legal

IronFlock's legal check answered these on 2026-11-17 (WP-6.8), before the first
published Jetson image. The "If no" column is the record of the fallbacks.

| # | Question | If no | IronFlock's answer, 2026-11-17 |
|---|----------|-------|--------------------------------|
| 1 | Are images that NVIDIA's own tools make from unchanged BSP binaries "binary files not modified" under 1.1(d)? This covers signed or packed binaries, BCTs, partition images and capsules | Flash kit only; no SD image; capsules only from `nvidia-l4t-bootloader` | Not relied on. IronFlockOS publishes the flash kit only; no SD image; capsules only as NVIDIA ships them in `nvidia-l4t-bootloader` |
| 2 | May IronFlockOS distribute two of NVIDIA's flash scripts with its `-r` fix, and a layout generated from NVIDIA's XML, if they carry change notices (1.1(b), 2.5)? In r39.2.1 the two scripts are MIT-licensed, so the open part is whether the MIT header governs them (the Agreement's section 6) and the layout, which comes from a proprietary file | The flash kit applies the fix and makes the layout on the user's host, as CI does | Not distributed. The flash kit applies the fix and makes the layout on the user's host |
| 3 | Is the Agreement next to the download, in FlockFlasher and in the image enough for "provided to each SOFTWARE recipient"? Does FlockFlasher need an acceptance step? What about devices that partners sell with IronFlockOS already installed? The flash kit asks for acceptance, and also takes `--accept-nvidia-license` for runs without a terminal: it still prints the Agreement in full, but nobody answers a question. Is that flag an acceptance by the recipient? | FlockFlasher asks for acceptance; partners pass the Agreement on; the kit drops the flag and always asks | The Agreement is published next to the Jetson files, is in the image, and the flash kit shows it and asks for acceptance; `--accept-nvidia-license` stays. FlockFlasher shows it when it comes to write Jetson images. Passing the Agreement on with devices that partners sell is arranged in IronFlock's contracts with them |
| 4 | Does IronFlock accept the indemnity (2.11)? Do its customer terms pass the exclusion of Critical Applications (2.10) on for Jetson devices? What changes with the EU's product liability directive 2024/2853, which counts software as a product from 9 December 2026 and allows no exclusion of liability towards injured persons? | Customer terms change before the first Jetson release | IronFlock accepts the indemnity. The customer terms for Jetson devices are IronFlock's to adjust, outside this repository |
| 5 | How are the Jetson images classified for export control (15)? NVIDIA's proprietary parts are not publicly available open source, which matters under the US rules that follow US-origin software; the EU's definition of "in the public domain" disregards copyright restrictions. NVIDIA publishes no classification for its Jetson software. Does the download server need restrictions for embargoed destinations? | Jetson files go behind the restriction the answer names | The Jetson files are published on the download server like the other files, without a restriction by destination |
| 6 | Is the source mirror (point 3) enough for NVIDIA's GPL and LGPL parts? The same question applies to the Ubuntu and Debian packages of every IronFlockOS image. For FreeRTOS (point 6): the image's statement (`/usr/share/doc/ironflockos/FreeRTOS-source-offer.txt`) offers the source at the mirror and says IronFlock sends it on request. Does the offer need a postal or e-mail address, and whose? | As legal sets; the statement names the contact legal gives | The mirror on the download server; the source offers name IronFlock GmbH, Taunusanlage 8, 60329 Frankfurt am Main, and legal@ironflock.com. As built, the statement names IronFlock GmbH's postal address and legal@ironflock.com |
| 7 | Is an IronFlockOS-branded image built from Canonical's Ubuntu binaries fine under Canonical's IP policy? Canonical's written position keeps a licence or a rebuild for a commercial, own-named image of classic Ubuntu packages (its founder set such device images apart from Ubuntu Core in 2016), and it has never said which marks must go. Many systems, commercial ones included, ship the unchanged binaries under their own names with the visible branding replaced, without a published agreement, and no enforcement against them is known: tolerance, not permission. Does IronFlock rely on that, or ask Canonical? As built, the image replaces the visible branding and keeps the technical references (point 10) | A licence from Canonical (it sells one for devices), or a userspace IronFlockOS builds itself | IronFlockOS ships Canonical's packages unchanged under its own name and branding, as described in "What IronFlockOS does"; no licence from Canonical is sought |
| 8 | The licence is revocable, and every Jetson device in the field depends on it. Does IronFlock accept that, or does it seek a written distribution agreement with NVIDIA, for example through NVIDIA's partner programme? | | IronFlock distributes under the Agreement as it is; no separate agreement with NVIDIA is sought for now |

## Sources

- NVIDIA, Jetson Linux r39.2.1: `release_sha_hashes.txt`,
  `Tegra_Software_License_Agreement-Tegra-Linux.txt`, `Jetson_Linux_R39.2.1_aarch64.tbz2`,
  `sources/public_sources.tbz2`, at
  `https://developer.download.nvidia.com/embedded/L4T/r39_Release_v2.1/`.
- NVIDIA's apt repositories `https://repo.download.nvidia.com/jetson/{som,common}`, suite
  `r39.2`: the packages of `targets/jetson-orin/packages` at their pins, and
  `nvidia-l4t-bootloader` 39.2.1.
- [EULA - JetPack](https://docs.nvidia.com/jetson/jetpack/eula/index.html): the NVIDIA
  Driver License Agreement for JetPack OS, and the CUDA EULA.
- [Canonical's intellectual property policy](https://canonical.com/legal/intellectual-property-policy).
