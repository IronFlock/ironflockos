# Jetson licence research: evidence for the eight questions

Desk research of 2026-11-17 on the eight questions at the end of the
[Jetson licence review](jetson-licence-review.md). This is not legal advice and no legal
opinion. It collects what primary texts say, what NVIDIA and Canonical have said in
public, and what other distributors visibly do, so that IronFlock's legal check starts
from evidence. The questions stay open until that check has answered them (WP-6.8).

How to read it:

- **Text** means a primary source (licence, law, policy), quoted as fetched today.
- **NVIDIA said** means a public statement by NVIDIA staff or in NVIDIA documents.
- **Practice** means what another company visibly does. Practice is not permission:
  most of these companies are NVIDIA partners and may have agreements nobody can see.
- **Reading** is this research's own inference. It is marked as such and is not a legal
  opinion.
- Every quote was fetched on 2026-11-17 and checked against the fetched copy; the
  sources are listed at the end, and the copies are not part of this repository. The
  NVIDIA Agreement fetched that day has the SHA-1 the review gives
  (`e331f3658ad9569817848036b6889d2bedcab18a`), so the review and this memo read the
  same text.

## 1. Where the evidence points

| # | Question (short) | Direction of the evidence | Confidence | The one next step |
| --- | --- | --- | --- | --- |
| 1 | Are tool-made images (BCTs, signed images, capsules) "not modified"? | Text open. Practice points to yes: NVIDIA itself now publishes tool-made flash packages, and its top partners publish full massflash packages | Low (text), medium (practice) | Written question to NVIDIA (`driver-licensing@nvidia.com`, the Agreement's §20) |
| 2 | May IronFlockOS ship the two fixed scripts and the derived layout? | Scripts: yes, they are MIT-licensed in r39.2.1 (new finding). Layout XML: open, it is "LicenseRef-NvidiaProprietary" | Medium-high (scripts), low (layout) | Lawyer confirms the MIT header governs (Agreement §6); the layout goes into the NVIDIA question |
| 3 | Is the Agreement next to the download and in the image "provided"? Acceptance? Flag? | Evidence points to yes for "provided": NVIDIA's own apt repository does no more. NVIDIA's own tools have the same non-interactive accept flag | Medium | Lawyer decides whether the recipient must also accept; partner contracts pass the Agreement on |
| 4 | Indemnity (2.11) and Critical Applications (2.10) | Text is clear; this is a business decision. New: the EU Product Liability Directive applies from 9 Dec 2026 and forbids excluding liability towards injured persons | High (text) | Lawyer drafts the Jetson clauses of the customer terms |
| 5 | Export classification; restrict the download server? | Open. EU: probably not listed. US: NVIDIA's binaries are US-origin and NVIDIA publishes no ECCN for any Jetson software | Low-medium | Ask NVIDIA for the ECCN of Jetson Linux r39.2.1; export adviser decides on a geo-block |
| 6 | Is the source mirror enough? Does the FreeRTOS offer need a contact? | Mirror: yes for the download channel (GPLv2 §3, last paragraph). Other channels need more. FreeRTOS text needs no address, but every German example names one | Medium-high | Add a postal and e-mail contact to the offers; cheap either way |
| 7 | IronFlockOS-branded image from Ubuntu binaries | Canonical's written answer points to a licence or a rebuild for a commercial own-named deb image (policy; Shuttleworth 2016: "a major difference between Ubuntu Core and classic (deb-based) Ubuntu images"). Practice: Pop!_OS, TUXEDO OS, Zorin, Mint and others ship Canonical's unmodified binaries under their own names with no published agreement and no known enforcement | Medium (on what exists), low (on permission) | Do the branding build items now; ask Canonical whether a licence is needed and whether Ubuntu Pro for Devices covers it |
| 8 | Revocable licence; seek a written agreement? | No public distribution agreement found. NVIDIA has a partner network with a "Distro and OS" category; the Agreement changes only "in a writing signed by" both | Low (thin evidence) | Write to `driver-licensing@nvidia.com` and ask what a distribution agreement takes |

## 2. Question 1: images that NVIDIA's tools make from unchanged binaries

**The question.** Are images that NVIDIA's own tools make from unchanged BSP binaries
"binary files not modified" under 1.1(d)? This covers signed or packed binaries, BCTs,
partition images and capsules.

### Text

The Agreement, r39.2.1 copy (v. February 25, 2025), section 1.1(d):

> "Distribute the SOFTWARE provided for use with operating system kernels distributed under the terms of an OSI-approved open source license as listed by the Open Source Initiative at http://opensource.org, provided that (i) the binary files thereof are not modified in any way (except for uncompressing of compressed files) and (ii) this Agreement is provided to each SOFTWARE recipient."

Section 2.3: "You may not modify or create derivative works of the SOFTWARE provided in binary form."

The text has one exception only: "uncompressing of compressed files". It says nothing
about signing, packing, concatenating or wrapping binaries in an image or capsule.

The licence headers in the BSP show which files are under which terms (BSP r39.2.1,
extracted today):

- `bootloader/LICENSE` and `bootloader/tegraflash.py`: "SPDX-License-Identifier: LicenseRef-NvidiaProprietary".
- `bootloader/LICENSE.spe_t234.bin` (SPE firmware): "LicenseRef-NvidiaProprietary", with FreeRTOS under the modified GPL (see question 6).

### NVIDIA said

- Jetson Linux Developer Guide r39.2.1, "Flashing Support": "NVIDIA provides a tool and instructions to efficiently flash Jetson devices in a factory environment." It then explains how to "Generate massflash package". The page does not say who may receive such a package.
- Developer Guide r39.2.1, "Jetson ISO Customization": "For custom bootloader configuration, such as pinmux, BPMP DTB, partition layout, or BCT changes, build a customized Bootloader Update Payload (BUP), ship it as a custom nvidia-l4t-bootloader_*.deb file". NVIDIA tells customers to build and ship a tool-made payload. The context is an ISO installer that the customer builds.
- NVIDIA's blog on JetPack 7.2: "NVIDIA owns the CI/CD pipeline, SQA, and releases validated reference images for Jetson developer kits." The Developer Guide says: "With JetPack 7.2, NVIDIA is moving from a community-only model to an officially supported NVIDIA path".
- NVIDIA's JetPack 7.2.1 download page lists `demo-image-reference-jetson-orin-nano-devkit-nvme.rootfs.tegraflash-tar.zst`. This is a full flash package, made by the Yocto (OE4T) tools, with BCTs and signing tools in it. It is NVIDIA distributing its own files, so it shows what NVIDIA considers normal, not what a third party may do.
- Forum, moderator (staff flag in the forum's JSON) kayccc, 2022-11-09, topic 233265, to a carrier-board maker asking about selling boards with an L4T image: "Users/developers are expected to deploy Jetson with software pre-installed and configured for use in end products, so what you describe should be fine." The same answer appears in topics 250727 (2023) and 320934 (2025).
- Forum, topic 311485, 2024-10-29. A user wrote for a customer that ships Jetson Orin NX devices: "We do not make any changes to the binary files, we only run additional software on the operating system. It would also be important to know which license conditions apply in this case, e.g. passing on the EULA". kayccc (moderator) answered the same day: "Customers are expected to deploy Jetson with software pre-installed and configured for use in end products, so what you describe should be fine." The question which conditions apply (passing on the EULA) got no answer.
- Forum, kayccc, 2017-07-08, topic 51156: "NVIDIA will permit the redistribution of L4T and hence will be revising our license agreement to reflect this." Section 1.1(d) of today's Agreement is probably that revision.
- Forum, topic 268839 ("NVIDIA Orin Distribution and Licensing Questions", 2023): the moderator (suhash) answered only "i will contact you via email on this to discuss your questions." NVIDIA handles such questions privately.

### Practice

- **Seeed Studio** (NVIDIA "Elite" partner) publishes full massflash packages for its
  reComputer boards on public links, for example
  `mfi_recomputer-orin-nano-8g-j401-6.0-36.3.0-2024-06-07.tar.gz`, flashed with
  `sudo ./tools/kernel_flash/l4t_initrd_flash.sh --flash-only --massflash 1 --network usb0 --showlogs`. These hold NVIDIA's bootloader, BCTs and
  signed images. The wiki page shows no NVIDIA licence text.
- **Advantech** (Elite) links a full BSP tree (`MIC-711_OrinNX_6.1.0_V1.0.0_SDK.tbz2`)
  on a public Dropbox. **AVerMedia** (Elite) and **Auvidea** (Elite) offer full
  `Linux_for_Tegra` downloads. **Antmicro** publishes prebuilt meta-tegra tegraflash
  tarballs on its own server.
- **balena** (NVIDIA "Preferred" partner, category "System Software, Distro and OS")
  keeps seven `boot0_*.img.gz` QSPI images in a public repository; the recipe says
  "# SPI flash images dumped after flashing the bootloader from L4T". The repository
  labels them Apache-2.0 and has no NVIDIA licence file. IronFlockOS does not take
  this as a model.
- **Connect Tech** and **Forecr** (both Elite) publish only an overlay. The user
  downloads NVIDIA's BSP, then runs the vendor's installer on top.
- **Canonical** (Ubuntu for Jetson) does not ship the boot firmware: its download page
  links NVIDIA's own BSP tarball ("Please download boot firmware before you start your
  installation."). Canonical does copy NVIDIA's userspace binaries into a Launchpad PPA:
  "this is a copy of binaries released by NVIDIA as part of Jetpack".
- **OE4T meta-tegra.** Its maintainer, asked to mirror NVIDIA's downloads (issue
  #1806): "I'm not sure licensing would permit redistribution of that sort, at least for
  some of the artifacts." OE4T itself publishes no prebuilt images.

### Reading

The text is narrow and does not answer the question. The practice is broad: NVIDIA's own
reference images, its top-tier partners' massflash packages and an NVIDIA moderator's
"should be fine" all treat tool-made images as normal. But the partners may have
agreements, and a moderator's forum post does not change a contract that "may only be
modified in a writing signed by an authorized representative of each party" (§18).
The capsules IronFlockOS takes unchanged from `nvidia-l4t-bootloader` are NVIDIA's own
files and are not part of this question.

### For the lawyer or NVIDIA

Whether NVIDIA's own processing (signing, packing, BCT generation) is "modifying" the
binaries. Only NVIDIA can settle this in writing.

**Draft question to NVIDIA:** "We distribute Jetson Linux r39.2.1 under section 1.1(d)
of the NVIDIA Driver License Agreement, with all binaries unchanged. May we also
distribute the flash images, BCTs, signed partition images and UEFI capsules that
NVIDIA's own unmodified tools (`l4t_initrd_flash.sh --massflash`,
`l4t_generate_soc_capsule.sh`) generate from those binaries, with the Agreement attached?
We read this as distribution of unmodified binaries and ask you to confirm it in writing."

## 3. Question 2: the two fixed scripts and the derived layout

**The question.** May IronFlockOS distribute two of NVIDIA's flash scripts with its `-r`
fix, and a layout generated from NVIDIA's XML, if they carry change notices
(1.1(b), 2.5)?

### Text

The two files IronFlockOS changes (`build/tegra-flash-package.sh`, `fix_reuse_option`)
carry these headers in the r39.2.1 BSP (extracted today from
`Jetson_Linux_R39.2.1_aarch64.tbz2`):

- `tools/kernel_flash/l4t_initrd_flash.func`: "SPDX-FileCopyrightText: Copyright (c) 2021-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved." and "SPDX-License-Identifier: MIT", followed by the full MIT text: "Permission is hereby granted, free of charge, to any person obtaining a copy of this software ... to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, ... subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."
- `tools/kernel_flash/l4t_create_images_for_kernel_flash.sh`: the same, "SPDX-License-Identifier: MIT".

For comparison: `generate_capsule/l4t_generate_soc_capsule.sh` is also MIT, and
`flash.sh` is "SPDX-License-Identifier: BSD-3-Clause". `bootloader/tegraflash.py` is
"LicenseRef-NvidiaProprietary".

The layout source, `tools/kernel_flash/flash_l4t_t234_nvme_rootfs_ab.xml`, is not open:
"SPDX-License-Identifier: LicenseRef-NvidiaProprietary ... Any use, reproduction,
disclosure or distribution of this material and related documentation without an express
license agreement from NVIDIA CORPORATION or its affiliates is strictly prohibited." The
"express license agreement" is the Driver License Agreement. Its 1.1(b) allows you to
"Modify and create derivative works of any portion of the SOFTWARE delivered by NVIDIA in
source code format", and 2.5 asks that "modified files ... carry prominent notices
stating that you changed the files".

The Agreement's section 6 on other licences: "The SOFTWARE may include or be distributed
with components provided with separate legal notices or terms that accompany the
components, such as open source software licenses ... The components are subject to the
applicable Other Licenses ... except that this Agreement will prevail regarding the use of
third-party open source software, unless a third-party open source software license
requires its license terms to prevail."

### NVIDIA said and practice

- OE4T meta-tegra's `tegra-flashtools` recipe applies eight patches to NVIDIA's flash
  tools (`l4t_sign_image.sh`, `l4t_bup_gen.func`, `tegraflash.py` and others), each
  marked `Upstream-Status: Inappropriate [OE specific]`. Patch 0007, to the proprietary
  `tegraflash.py`, carries a `Signed-off-by:` from an `@nvidia.com` address.
- NVIDIA's own Orin Nano tegraflash download contains a changed `l4t_sign_image.sh`
  (10,562 bytes against 10,653 in the BSP). The diff shows the OE4T changes, for example
  `xxd` replaced by a `python3 -c` call. NVIDIA itself distributes OE4T-patched NVIDIA
  scripts.
- balena publishes a patch that turns NVIDIA's `flash_t234_qspi_sdmmc.xml` into its own
  layout. balena and Forecr also edit NVIDIA's scripts with `sed` on the user's machine,
  as IronFlockOS's flash kit does.

### Reading

For the two scripts the review's question is mostly answered by the files themselves:
they are MIT-licensed, and MIT allows modifying and distributing them if the copyright
and permission notice stay. The review treats them under 1.1(b) and 2.5; that is out of
date for r39.2.1. Section 6's "this Agreement will prevail" clause speaks of
"third-party open source software"; NVIDIA's own MIT files are not third-party, so the MIT
terms should govern. A change notice in the file is still good practice (and what 2.5
would ask).

The layout XML is different: it is NVIDIA-proprietary text. A generated layout derived
from it is a "derivative work" of a part "delivered ... in source code format", which
1.1(b) allows. Whether 1.1(d) then allows distributing that derived file is the open
point: 1.1(d)'s "not modified" condition speaks of "binary files", and an XML file is not
one. Practice (balena, NVIDIA's own changed script) points to yes.

### For the lawyer or NVIDIA

- Confirm that the MIT header governs the two scripts despite §6.
- Whether a layout derived from NVIDIA's XML may be distributed. Add it to the NVIDIA
  question of question 1: "We also generate a partition layout from your
  `flash_l4t_t234_nvme_rootfs_ab.xml` (LicenseRef-NvidiaProprietary) and would distribute
  it with a notice that we changed it. Do sections 1.1(b), 1.1(d) and 2.5 allow this?"

## 4. Question 3: providing the Agreement, acceptance, and the `--accept-nvidia-license` flag

**The question.** Is the Agreement next to the download, in FlockFlasher and in the image
enough for "provided to each SOFTWARE recipient"? Does FlockFlasher need an acceptance
step? What about devices that partners sell with IronFlockOS installed? Is the flash
kit's non-interactive flag an acceptance by the recipient?

### Text

- 1.1(d)(ii): "this Agreement is provided to each SOFTWARE recipient". The word is
  "provided", not "accepted".
- The Agreement's own opening: "IMPORTANT NOTICE – PLEASE READ AND AGREE BEFORE USING
  THE SOFTWARE." and "If you don't have the required age or authority to enter into this
  Agreement or if you don't accept all the terms below, do not use the SOFTWARE." The
  recipient's own licence comes from accepting this text.
- §3 Authorized Users: "You may allow employees and contractors of your entity or of your
  subsidiary(ies) to access and use the SOFTWARE ... You are responsible for the
  compliance with the terms of this Agreement by your authorized users."
- §10.5: Delaware law governs. German law (BGB §305(2), the rules on how standard terms
  become part of a contract) does not apply between businesses anyway: BGB §310(1):
  "§ 305 Absatz 2 und 3 ... finden keine Anwendung auf Allgemeine Geschäftsbedingungen,
  die gegenüber einem Unternehmer ... verwendet werden." (§305(2) and (3) do not apply to
  standard terms used towards a business.)

### NVIDIA said and practice: how NVIDIA itself provides the Agreement

- **apt repository.** NVIDIA's own channel for the `nvidia-l4t-*` packages, which
  IronFlockOS uses, has no acceptance step. The `Packages` index has no licence field.
  The Agreement reaches the user only as each package's `copyright` file. IronFlockOS
  provides the same and more.
- **First boot.** NVIDIA's `nvidia-l4t-oobe` package shows
  `Tegra_Software_License_Agreement-Tegra-Linux.txt` under "License For Customer Use of
  NVIDIA Software". The graphical setup needs the checkbox
  `'I accept the terms of these licenses'`. Headless setup shows it as a debconf note.
  NVIDIA's quick start lists "Review and accept NVIDIA Jetson software EULA".
- **NVIDIA's own non-interactive flag.** The BSP script `tools/l4t_create_default_user.sh`
  has "--accept-license - Specified to accept the terms and conditions of EULA" and
  "# This script creates default user and bypass the oobe setup". Seeed's and Mender's
  guides use it (`--accept-license`).
- **SDK Manager.** The command line has `--licenses accept | reject`: "Set this option to
  accept the terms and conditions of the NVIDIA software licenses." and "If the option is
  not set, SDK Manager prompts you with the license pages to review and confirm."
- **Download page.** "By downloading and using the software, you agree to fully comply
  with the terms and conditions of the NVIDIA Software License Agreement." The link goes
  to a MathDx licence file, not the Jetson Agreement.
- **Others.** None of the carrier-board image pages that were checked (Seeed, Advantech,
  AVerMedia, Antmicro) shows NVIDIA's licence or asks for acceptance. Forecr relies on SDK
  Manager's acceptance. Canonical avoids the question by having the user fetch NVIDIA's
  files.
- **FSF on click-through (for the GPL parts):** "Some software packaging systems have a
  place which requires you to click through or otherwise indicate assent to the terms of
  the GPL. This is neither required nor forbidden."

### Reading

"Provided" asks for the text to reach the recipient; IronFlockOS's plan (next to every
Jetson file, linked in the release notes, shown in FlockFlasher, inside the image and the
bundle) does at least what NVIDIA's own apt channel does. An acceptance step is not
asked for by 1.1(d). It helps NVIDIA's contract with the recipient come about, which is
NVIDIA's interest and also lowers IronFlock's risk under 2.11.

The `--accept-nvidia-license` flag copies NVIDIA's own `--accept-license` and SDK Manager
`--licenses accept`. Whoever passes the flag accepts on behalf of the organisation that
runs the kit; it is an acceptance by that person, not by nobody. Keeping it is in line
with NVIDIA's practice.

Partner-installed devices are the gap: the partner, not IronFlock, hands the device to
the end customer. The Agreement is in the image, but the partner should be bound by
contract to pass it on.

### For the lawyer

- Whether IronFlock wants recipients to accept, or only to receive the Agreement.
- Whether a person who passes `--accept-nvidia-license` binds the organisation (US
  law, since Delaware law governs NVIDIA's contract with the recipient).
- The clause in partner contracts that passes the Agreement on with each device.

## 5. Question 4: indemnity (2.11) and Critical Applications (2.10)

**The question.** Does IronFlock accept the indemnity? Do its customer terms pass the
exclusion of Critical Applications on for Jetson devices?

### Text

- 2.10: "You acknowledge that the SOFTWARE as delivered is not tested or certified by NVIDIA for use in any system or application where the use of or failure of such system or application developed with the SOFTWARE could result in injury, death or catastrophic damage (each, a "Critical Application"). Examples of Critical Applications include use in avionics, navigation, autonomous vehicle applications, automotive products, military, medical, life support or other life critical applications. ... You are solely responsible for ensuring that systems and applications developed with the SOFTWARE include sufficient safety and redundancy features".
- 2.11: "You agree to defend, indemnify and hold harmless NVIDIA and its affiliates ... from and against any and all claims, damages, obligations, losses, liabilities, costs or debt, fines, restitutions and expenses (including but not limited to attorney's fees ...) arising out of or related to products or services that have been developed with or use the SOFTWARE (including for use in or for Critical Applications), and for use of the SOFTWARE outside of the scope of this Agreement or not in compliance with its terms."
- §12: NVIDIA's total liability "WILL NOT EXCEED FIVE U.S. DOLLARS (US$5)".
- NVIDIA's hardware carries the same exclusion. Jetson Linux r39.2.1 Developer Guide,
  Legal Information: "NVIDIA products are not designed, authorized, or warranted to be
  suitable for use in medical, military, aircraft, space, or life support equipment, ...
  such inclusion and/or use is at customer's own risk."
- **New EU law.** Directive (EU) 2024/2853 on liability for defective products, Art. 2(1):
  "This Directive shall apply to products placed on the market or put into service after
  9 December 2026." Art. 4(1): "'product' means all movables ... it includes electricity,
  digital manufacturing files, raw materials and software". Art. 2(2): "This Directive
  does not apply to free and open-source software that is developed or supplied outside
  the course of a commercial activity." Art. 15: "Member States shall ensure that the
  liability of an economic operator pursuant to this Directive is not, in relation to the
  injured person, limited or excluded by a contractual provision or by national law."

### NVIDIA said and practice

No public statement by NVIDIA on the indemnity was found. How other vendors word the
pass-on in their customer terms was not researched; there is no evidence on that here.

### Reading

The text leaves no room: every licensee, IronFlock included, gives the indemnity. The
indemnity has no cap and covers "products or services that have been developed with or
use the SOFTWARE", which is every Jetson device running IronFlockOS. From 9 December 2026
IronFlockOS images released for commercial use are "products" under the new directive;
IronFlock cannot exclude its liability to injured persons by contract. Customer terms
can still allocate risk between businesses (recourse, Critical Applications exclusion,
safety responsibility), the same way NVIDIA's hardware notice does.

### For the lawyer

- Whether IronFlock accepts 2.11 as is (it cannot negotiate it without a separate
  agreement; see question 8).
- Jetson clauses for the customer terms: the Critical Applications exclusion, the
  customer's responsibility for safety, and a recourse clause that mirrors 2.11.
- How the Product Liability Directive (from 9 Dec 2026) and the German law that
  implements it change the risk of shipping software for Jetson devices.

## 6. Question 5: export control

**The question.** How are the Jetson images classified? NVIDIA's proprietary parts are
not publicly available open source. Does the download server need restrictions for
embargoed destinations?

### Text: EU and Germany

- Regulation (EU) 2021/821, consolidated text of 21.09.2026, Art. 2(2)(d): export
  includes "transmission of software or technology by electronic media ... it includes
  making available in an electronic form such software and technology to natural or legal
  persons or to partnerships outside the customs territory of the Union".
- General Software Note: "Categories 1 to 9 of this list do not control "software" which
  is any of the following". Entry a. is retail sale, followed by "Note : Entry a. of the
  General Software Note does not release "software" specified in Category 5, Part 2
  ("Information Security"). b. "In the public domain"; or". Entry b. has no such
  carve-out for Category 5 Part 2.
- Definition: ""In the public domain" ... means "technology" or "software" which has
  been made available without restrictions upon its further dissemination (copyright
  restrictions do not remove "technology" or "software" from being "in the public
  domain")."
- Cryptography Note (Note 3 to Cat. 5 Part 2): "5A002, 5D002.a.1., 5D002.b. and
  5D002.c.1. do not control items as follows: a. Items that meet all of the following:
  1. Generally available to the public by being sold, without restriction, from stock at
  retail selling points ..." Also: "Note: 'Executable software' does not include complete
  binary images of the "software" running on an end-item."
- BAFA, Merkblatt "Exportkontrolle und das BAFA", 10th ed., Nov 2024, on internet
  provision: "Ebenfalls genehmigungspflichtig ist das Bereitstellen von Software und
  Technologie im firmeninternen Intranet oder im Internet, wenn hierdurch der Zugriff auf
  die Software oder Technologie aus Drittstaaten möglich ist." (Making software available
  on the internet also needs a licence where third countries can access it.) And:
  "Vielmehr besteht die Genehmigungspflicht bereits dann, wenn die Möglichkeit eines
  Zugriffs geschaffen wird." (Creating the possibility of access is enough.) Both
  sentences apply where a licence requirement exists at all, that is, for listed items or
  under an embargo.
- Same Merkblatt: "Die Befreiung für allgemein zugängliche Technologie oder
  Grundlagenforschung bezieht sich nur auf die Genehmigungspflichten für gelistete Güter.
  Die Anwendung des Art. 4 der EU-Dual-Use-VO bleibt möglich" (The public-domain
  exemption covers only listed items; the Art. 4 catch-all for sensitive end uses still
  applies.)
- BAFA, Merkblatt "Immaterieller Technologietransfer", May 2024: "Es ist ständige
  Verwaltungspraxis des BAFA, erstmalige Veröffentlichungen von Forschungsergebnissen,
  die dem Anhang I der EU-Dual-Use-VO unterfallen, als Ausfuhr zu bewerten" ... "Dies
  gilt auch für Open Source." (BAFA treats the first publication of listed material as an
  export; this also applies to open source.)
- No BAFA guidance on the Cryptography Note or on mass-market software was found.
- Russia, Regulation 833/2014 (consolidated 24.07.2026), Art. 2(1): "It shall be
  prohibited to sell, supply, transfer or export, directly or indirectly, dual-use goods
  and technology, whether or not originating in the Union, to any natural or legal
  person, entity or body in Russia or for use in Russia." Annex VII also lists
  "X.D.I.001 "Software" specially designed for the "development", "production", or "use"
  of electronic devices or components controlled by X.A.I.001" (X.A.I.001 covers
  microprocessors above 25 MHz). The Belarus, Iran, Syria and North Korea regulations were
  not fetched.

### Text: United States (EAR, current eCFR)

- 15 CFR 734.3(a)(2): subject to the EAR are "All U.S. origin items wherever located;".
- 734.7(a): software is "published", and thus not subject to the EAR, "when it has been
  made available to the public without restrictions upon its further dissemination",
  including "posting on the Internet on sites available to the public".
- 734.7(b): "Published encryption software classified under ECCN 5D002 remains subject to
  the EAR unless it is publicly available encryption object code software classified
  under ECCN 5D002 and the corresponding source code meets the criteria specified in
  § 742.15(b) of the EAR."
- 734.4, note: "U.S.-origin software is not eligible for the de minimis exclusion and is
  subject to the EAR when exported or reexported separately from (i.e., not bundled or
  incorporated with) the foreign-made item."
- 740.17(b)(1): mass-market items are "classified as ECCN 5A992 or 5D992 following
  self-classification or classification by BIS"; and "This License Exception ENC does not
  authorize export or reexport to ... any country listed in Country Groups E:1 or E:2"
  (E:1: Iran, North Korea, Syria; E:2: Cuba).
- 746.1, on Cuba: "most other items subject to the EAR, but not included on the CCL,
  designated by the Number "EAR99", require a license to Cuba."
- 746.8(a)(1): "A license is required to export, reexport, or transfer (in-country) to or
  within Russia or Belarus any item subject to the EAR and specified in any Export Control
  Classification Number (ECCN) on the CCL." This covers 5D992; EAR99 software is caught
  only for the types listed in (a)(8)(ii) (for example ERP, CAD, CAM).
- BIS mass-market page: "Although a 5A992.c and 5D992.c item does not require a license
  exception to go to most places (because it is only Anti-Terrorism controlled)".

### NVIDIA said

- NVIDIA's export page: "The Export Control Classification Number (ECCN) and Harmonized
  Schedule (HS) codes are the classifications that NVIDIA applies to the listed
  products." The table (searched in a browser, not saved) gives Jetson Orin modules and
  developer kits 5A992.c, and some Orin NX/Nano SKUs 4A994.l. Searches for software
  (JetPack, CUDA, L4T, driver, 5D*) returned "No data".
- Forum moderators: "the ECCN for Jetson AGX Xavier Industrial Module is 5A992.c" (2022);
  a 2014 forum question asking for the ECCN of L4T and CUDA software got no NVIDIA answer.
- NVIDIA serves the BSP and the apt repository without login and without an export notice.

### Practice

Canonical's Ubuntu for Jetson page, OE4T, balena and Seeed show no export notice and no
geo-restriction that can be seen from Germany. No official Canonical ECCN statement for
Ubuntu was found.

### Reading

- **Open-source userspace (Ubuntu).** EU: likely "in the public domain" (GSN entry b),
  so not listed. US: the US-origin parts are likely outside the EAR under 734.3(b)(3) and
  742.15(b). Both point the same way.
- **NVIDIA's binaries.** US: US-origin, so subject to the EAR wherever they are, unless
  "published". They are posted publicly, but with conditions on redistribution
  (unmodified, Agreement attached). Whether that is "without restrictions upon its further
  dissemination" is the key open point. If not published, they are probably EAR99 or
  5D992. Either way, a US licence would be needed for Cuba, Iran, North Korea and Syria,
  and for Russia and Belarus if 5D992. EU: the EU definition says copyright restrictions
  do not defeat "in the public domain", so the same binaries may well be public domain in
  the EU sense. **EU and US answers can differ here.**
- **IronFlock's own software in the image** (update client, device agent). If it is
  already public, it is "in the public domain". If it is first published with the image,
  BAFA treats first publication of listed software as an export. Whether it is listed at
  all (5D002) depends on the exclusions of 5A002.a for operations and maintenance or
  "connected civil industry" use; that needs a technical review.
- A geo-block costs little: typical precautions, modelled on 15 CFR 734.17(c), are
  blocking the E:1/E:2 countries plus Russia, Belarus and the occupied regions of Ukraine,
  an export notice, and a click-through acknowledgement. NVIDIA itself shows none of these.

### For the lawyer or an export adviser

1. Whether the Agreement's conditions defeat "published" (EAR) or "in the public domain" (EU).
2. The ECCN of NVIDIA's Jetson Linux binaries; ask NVIDIA.
3. The 5D002 status of IronFlock's own update client and device agent.
4. The Russia, Belarus, Iran, Syria and North Korea regulations for free downloads.
5. Whether to geo-block the Jetson files, or all IronFlockOS files.

**Draft question to NVIDIA:** "Please state the export classification (ECCN, or EAR99)
of the Jetson Linux r39.2.1 software as distributed in your apt repository
(`nvidia-l4t-*` packages) and in `Jetson_Linux_R39.2.1_aarch64.tbz2`, including the
bootloader and OP-TEE components. Does NVIDIA consider these files 'published' under
15 CFR 734.7?"

## 7. Question 6: the source mirror and the written offers

**The question.** Is the source mirror enough for NVIDIA's GPL and LGPL parts, and for
the Ubuntu and Debian packages? For FreeRTOS: does the offer need a postal or e-mail
address, and whose?

### Text

GPLv2 section 3 (fetched from gnu.org):

> "a) Accompany it with the complete corresponding machine-readable source code ...; or,
> b) Accompany it with a written offer, valid for at least three years, to give any third party, for a charge no more than your cost of physically performing source distribution, a complete machine-readable copy of the corresponding source code ...; or,
> c) Accompany it with the information you received as to the offer to distribute corresponding source code. (This alternative is allowed only for noncommercial distribution and only if you received the program in object code or executable form with such an offer, in accord with Subsection b above.)"

And its last paragraph:

> "If distribution of executable or object code is made by offering access to copy from a designated place, then offering equivalent access to copy the source code from the same place counts as distribution of the source code, even though third parties are not compelled to copy the source along with the object code."

The FreeRTOS exception, as NVIDIA ships it in `bootloader/LICENSE.spe_t234.bin` of the
BSP r39.2.1 (the review reports the FreeRTOS licence in the package's
`LICENSE.bl_update_payload.gz`; this research read the BSP copy):

> "As a special exception, the copyright holder of FreeRTOS gives you permission to link FreeRTOS with independent modules that communicate with FreeRTOS solely through the FreeRTOS API interface, regardless of the license terms of these independent modules, and to copy and distribute the resulting combined work under terms of your choice, provided that
> + Every copy of the combined work is accompanied by a written statement that details to the recipient the version of FreeRTOS used and an offer by yourself to provide the FreeRTOS source code (including any modifications you may have made) should the recipient request it."

> "Clause 2: FreeRTOS may not be used for any competitive or comparative purpose, including the publication of any form of run time or compile time metric, without the express permission of Real Time Engineers Ltd."

The FreeRTOS text asks for "an offer by yourself" and names no time limit and no form of
contact.

FSF GPL FAQ (gnu.org/licenses/gpl-faq.html):

- On binaries shipped on physical media with source offered by FTP: "Under version 2, you're certainly free to offer source via FTP, and most users will get it from there. However, if any of them would rather get the source on physical media by mail, you are required to provide that. If you distribute binaries via FTP, you should distribute source via FTP."
- "How can I make sure each user who downloads the binaries also gets the source? ... You don't have to make sure of this. As long as you make the source and binaries available so that the users can see what's available and take what they want, you have done what is required of you."
- On the written offer: "If you choose to provide source through a written offer, then anybody who requests the source from you is entitled to receive it."

Commentary (Copyleft guide by FSF, SFC and others, archived edition, marked "made public
for archival and historical purposes only"): "The binary distributor must be prepared to
honor that offer for source for three years and ship it out ... at a moment's notice
when they receive such a request. ... support engineers must be trained how to route
source requests".

### Practice: three German written offers, quoted

1. **IGEL Technology GmbH** (a German Linux OS vendor, closest to IronFlockOS):
   "IGEL provides a copy of the complete corresponding source code for a period of three
   years after the last shipment of this product. You may request a copy by either:
   Completing the below form. ... Mail IGEL a written request to the address below and be
   sure to provide a return address. IGEL Technology GmbH Attn: GPL Source Code Offer
   Melli-Beese-Str. 3, 86159 Augsburg, Germany".
2. **SEW-EURODRIVE** (industrial drives): "You can obtain the source code for these
   software components from us on a data medium (CD-ROM, DVD or USB memory stick) by
   sending a request by e-mail to opensource@sew-eurodrive.de or in writing to the address
   specified below. SEW-EURODRIVE GmbH & Co KG Software Development IIoT Ernst-Blickle-Str.
   42 76646 Bruchsal Germany" ... "This offer is valid for three years from the date we
   last distributed the product with the object code of the requested component, or in
   the case of GPL 3.0 source code, for as long as we provide spare parts or customer
   support for that product."
3. **Schüco International KG** (building technology): "Schüco International KG hereby
   offers, valid for at least three years from the date we distributed the product and/or
   the date, you downloaded the software, to give you or any third party a complete
   machine-readable copy of the corresponding source code ... To receive such source code,
   please contact Schüco International KG using the following contact details: Schüco
   International KG Support Smart Building Karolinenstr. 1-15 33609 Bielefeld Germany".

A fourth, ALLNET GmbH, also names a postal address and adds: "For your convenience, some
or all of the source code may also be found at: http://www.allnet.de/gpl.html". All four
name the company that distributes, not the upstream author.

### Reading

- **Download channel.** The mirror on the same download server as the images is GPLv2
  §3's "equivalent access ... from the same place". For that channel no written offer is
  needed. This also covers the Ubuntu and Debian packages if their sources sit on the same
  server; Canonical's own archive does not count as "the same place" for IronFlock's
  server.
- **Other channels.** The appliance OS mirror, the device-agent's over-the-air updates
  and FlockFlasher are other "places". Each either serves the sources too, or the images
  must carry a written offer (3(b)), valid for three years and open to any third party.
- **Partner-installed devices.** The partner distributes; it cannot use 3(c) because its
  distribution is commercial. It needs its own offer or IronFlock's written offer passed
  on under a contract in which IronFlock agrees to serve such requests.
- **FreeRTOS.** The exception asks for an offer "by yourself". It names no address. Every
  German example names a postal address, and several add e-mail. Adding IronFlock's
  postal address and an e-mail address (for example a role address) costs nothing and
  makes the offer actionable.

### For the lawyer

- Which channels count as "the same place", and whether a written offer is needed in the
  image for the OTA and appliance channels and for partners.
- The contact to name (postal address and e-mail), and how long to keep sources (three
  years after the last distribution of each version).
- Whether FreeRTOS's clause 2 ("no ... metric") limits anything IronFlock publishes; the
  review already says IronFlockOS publishes no SPE or PVA figures.

## 8. Question 7: an IronFlockOS-branded image built from Ubuntu binaries

**The question.** Is an IronFlockOS-branded image built from Canonical's Ubuntu binaries
fine under Canonical's IP policy? The case is narrow: a company publishes a commercial
embedded image under its own name. The image holds unmodified Ubuntu 24.04 binary
packages from Canonical's archive, plus the company's own packages and NVIDIA's.

Many systems are built from Ubuntu's binaries, so the question has been asked in public
for almost twenty years. This section collects the answers given, ranks them, and shows
what the derivatives visibly do.

### Text: Canonical's current terms

- **IP rights policy** (dated 15 July 2015, still current; the 14 May 2013 version has the same wording on modified versions):
  - "You can redistribute Ubuntu, but only where there has been no modification to it. You can redistribute Ubuntu in its unmodified form, complete with the installer images and packages provided by Canonical (this includes the publication or launch of virtual machine images)."
  - "Any redistribution of modified versions of Ubuntu must be approved, certified or provided by Canonical if you are going to associate it with the Trademarks. Otherwise you must remove and replace the Trademarks and will need to recompile the source code to create your own binaries. This does not affect your rights under any open source licence applicable to any of the components of Ubuntu."
  - "If you need us to approve, certify or provide modified versions for redistribution you will require a licence agreement from Canonical, for which you may be required to pay."
  - "Ubuntu is an aggregate work of many works, each covered by their own licence(s). ... For the avoidance of doubt, where any other licence grants rights, this policy does not modify or reduce those rights under those licences."
  - "The disk, CD, installer and system images, together with Ubuntu packages and binary files, are in many cases copyright of Canonical (which copyright may be distinct from the copyright in the individual components therein) and can only be used in accordance with the copyright licences therein and this IPRights Policy."
  - "You cannot use the Trademarks in software titles."
- **Ubuntu Pro service terms** (dated 1 June 2026), a definition: "**Ubuntu Content**: means the set of installable Ubuntu packages and Ubuntu images which are published by Canonical and are redistributable in their original form subject to the IP policy documented at www.ubuntu.com/IP and their contents which may be included in Images as unpacked, integrated or derived materials." Clause 5: "Where a Service or Order is stated to include a trademark licence, Canonical grants to Customer a non-exclusive licence to use the trademarks of the Canonical group".
- **Device offer.** Canonical's device pricing page lists, among the parts of "Ubuntu Pro for devices", "[Trademark use](https://canonical.com/legal/trademarks)". The Ubuntu Pro for Devices page says it "can be purchased for a one-time fee per device". Neither page says whether that subscription covers redistributing an own-branded image built from Ubuntu packages.
- **Older terms, for history only.** The Ubuntu trademark policy as archived in December 2012 said: "Canonical grants permission for anyone to mirror or redistribute unmodified Ubuntu installation images, Ubuntu software packages, and Ubuntu package archives." It also said: "Note that if there's a commercial intent to your use, then you will always need a formal license from us for trademarks and copyright materials." The 2013 policy dropped the explicit permission for packages.

### Existing answers, ranked by how directly they fit the case

1. **Mark Shuttleworth, founder of Ubuntu, 14 May 2016, snappy-devel mailing list.** A
   device maker asked whether shipping hardware with an Ubuntu Core image needs an
   agreement. He answered: "You don't need an agreement with Canonical to ship an Ubuntu
   Core image, just make sure it uses the standard unmodified OS snap. ... we are happy
   for devices to ship without a private agreement with the manufacturer. ... This is a
   major difference between Ubuntu Core and classic (deb-based) Ubuntu images." This is
   the most direct statement by Canonical's leadership on device images. By contrast, it
   implies that a classic deb-based device image, which is what IronFlockOS builds, is
   the case where Canonical expects an agreement.
2. **Michael Hall, Ubuntu Community Council, 4 and 5 May 2015, ubuntu-community-team
   list.** He was answering the Kubuntu lead and relaying what he called "Canonical's
   position on the matter". On 4 May: "Derivatives can either work fully within the
   archives, in which case they don't need to do anything, or they can request a license
   grant from Canonical to base their derived product off of Ubuntu's archives. If they
   don't wish to do either, then they should take the source code and build their own
   archives from that, as Ubuntu does with Debian and CentOS does from Red Hat." On 5 May:
   "Moreover, for non-commercial derivatives Canonical offers free (or nearly free) use of
   Ubuntu's archives for the distribution for those distros. ... All we ask is that they
   don't call it Ubuntu. This works our well for Mint and Elementary and a number of other
   derivatives". The free or nearly free terms are stated for non-commercial derivatives
   only.
3. **The Linux Mint case, 2013-2014.**
   - InfoWorld, 11 December 2013, citing DistroWatch: "Clem claims he has been asked by Canonical’s legal department to license the binary packages used by Ubuntu."
   - Ubuntu Community Council, 13 February 2014: "Linux Mint had been asked to sign a license agreement in order to continue distributing software packages out of the Ubuntu repositories" ... "Canonical already provides a license for the use of these to the Ubuntu project and all of its distributions". The Council called it a licence "to help ensure" that Mint can continue.
   - CIO (press), 2015: "Later, the Linux Mint team ended up signing a deal with Canonical to use binaries for an undisclosed fee (if any)."
   - No statement by Mint itself on the terms was found. The DistroWatch issue could not be fetched (it returned an empty page).
4. **Ubuntu community voices in 2025 and 2026, all unofficial.**
   - Discourse, January 2026: a robotics start-up asked almost this exact question, a modified Ubuntu pre-installed on its own board with all Ubuntu marks removed. popey, a community moderator who wrote in 2025 that he is "Not a Canonical employee (but used to be one)", answered: "I am confident you will not get a straight answer to the questions you asked. Many people have tried, all have (as far as I know) failed." and "you should very seriously consider entering into a paid license agreement with Canonical to ship Ubuntu image." Another long-time contributor wrote: "Please contact legal@canonical.com for such questions, there are pretty fine grained requirements they will be able to explain to you".
   - Discourse, January 2025, on a shop selling PCs with a customised Ubuntu, the same moderator wrote: "The general advice is if you modify the image, it’s not Ubuntu, so you can’t call it Ubuntu." He named TUXEDO OS as the example of a modified Ubuntu shipped under another name.
5. **Ubuntu Community Council member, 13 October and 2 December 2025, ubuntu-devel
   list.** He asked Canonical to clarify the policy for "remixes". He wrote that the IP
   policy "suggests that the entire way in which remixes work is, at best, a gray area,
   and at worst, completely disallowed". He added that Qubes OS does not distribute
   Ubuntu VMs "for fear of legal action being taken against them by Canonical". No reply
   appears in the list archive from October 2025 to November 2026.
6. **Matt Zimmerman, then Ubuntu's CTO, 8 January 2007, ubuntu-devel list.** This
   predates the 2013 policy; it shows what Canonical once called fair use. On
   `/etc/lsb-release`: "Perhaps changing DISTRIB_DESCRIPTION but not DISTRIB_ID is the
   right thing to do." On version strings like "1.4.4-0ubuntu1": "No, this refers to the
   Ubuntu version of the package (which is the same package being used in the
   derivative)." On naming: "'based on Ubuntu ...' requires no prior permission; this is
   fair use of the trademark to refer to Ubuntu itself." On the logo: "Use of the logo to
   refer to a derivative distribution requires prior permission." On the archives: "The
   Ubuntu archives are a public service for anyone to use".
7. **The 2016 cloud dispute** (Canonical blog, 1 December 2016, by Mark Shuttleworth).
   The provider "has breached its contract and is publishing insecure, broken images of
   Ubuntu". The concern was images that claim to be Ubuntu: "users expect that ‘all
   things that claim to be Ubuntu are genuine’". It concerned the Ubuntu name and a
   contract, not images under another name.
8. **Container images.** Canonical maintains the official `ubuntu` image on Docker Hub.
   Its page says: "As for any pre-built image usage, it is the image user's
   responsibility to ensure that any use of this image complies with any relevant
   licenses for all software contained within." Canonical's Ubuntu Pro description
   restricts only images made from Pro content: "Container images may be generated from
   Ubuntu Pro bits only if the resulting container images are deployed to Ubuntu
   Pro-covered machines." No Canonical statement restricting republished images built
   from the public archive was found.

### Critics and commentary (not Canonical; marked as commentary)

- **Jonathan Riddell**, Kubuntu founder and Ubuntu archive admin, KDE blog, 14 February 2014: "no licence is needed to make a derivative distribution of Kubuntu. All you need to do is remove obvious uses of the Kubuntu trademark. Any suggestion that somehow compiling the packages causes Canonical to own extra copyrights is nonsense." On 1 May 2015 (ubuntu-community-team): "Canonical does not hold the copyright on binary packages any more than it does on the source packages." He left the Kubuntu lead role later that month (LWN, 28 May 2015: "Jonathan Riddell forced out of Kubuntu").
- **Matthew Garrett**, LWN comments:
  - 28 May 2015: "Nobody knows what they're claiming, because the policy is unclear and they refuse to answer anybody attempting to seek clarity. Canonical employees have indicated that the policy requires you to rebuild packages even if they embody no trademarks".
  - 20 November 2015: "Every question I've asked on this front has either been ignored or I've been explicitly told it won't be answered."
  - 21 April 2025: Canonical "has demanded license payments from Ubuntu derivatives that simply imported Canonical binary packages rather than rebuilding them" and "has also never made a public statement about what would need to be stripped from source packages before a full rebuild would no longer be a trademark violation."
  - His own blog could not be fetched (timeouts); only these LWN comments were read.
- **Jono Bacon**, who worked at Canonical ("When I was at Canonical"), blog, 28 August 2015: "If someone else takes those binaries and builds a commercial product from them, I can understand Canonical being a bit miffed about that and asking the company to pay it forward and cover some of the costs." He also wrote that the compiled-binary copyright question is open: "Some believe it does, some believe it doesn’t. My opinion: I just *don’t know*."
- **FSF and SFC, 15 July 2015.** After the policy change, the GPL's binary redistribution right prevails for GPL packages. The FSF: "it does not help works covered by lax permissive licenses (such as the X11 license) that do allow such additional restrictions." The SFC: "full permission to redistribute Ubuntu as a whole remains in question."
- **Community readings of "modified version".**
  - A list member, 3 May 2015: "A grey area may be spinning an updated version of a ISO, in which case is it a modified version of Ubuntu because you've messed with the ISO, or not since it is all official, unmodified, Ubuntu packages?"
  - A Discourse user who describes themself as an in-house lawyer, 15 November 2026: "even Canonical’s own published IP policy doesn’t spell out that level of technical detail (package names, system files, etc.), which is exactly why it needs a direct answer from them".
- No law-firm note or court decision on the compiled-binary copyright argument was found.

### Practice: what systems built from Ubuntu's binaries do

Each system below was checked from its own files: package indexes, `.deb` contents, build
scripts and ISO manifests, all fetched on 2026-11-17.

| System | Ubuntu packages | Package source | `os-release` NAME / ID / ID_LIKE | Ubuntu names left | Agreement with Canonical |
| --- | --- | --- | --- | --- | --- |
| Linux Mint 22.3 | Canonical's binaries; own build of `base-files` (`13ubuntu10mint22.3.0`) | `archive.ubuntu.com`, `security.ubuntu.com` | "Linux Mint" / `linuxmint` / "ubuntu debian"; `DISTRIB_ID=LinuxMint` | ID_LIKE, `UBUNTU_CODENAME`, `/etc/dpkg/origins/ubuntu`; motd scripts emptied | Asked to sign (2014); a deal reported by the press, terms unknown |
| Pop!_OS 24.04 (System76, commercial) | Canonical's binaries; 50 Ubuntu packages rebuilt and pinned first | Own copy of the archive at `apt.pop-os.org/ubuntu`, Release file byte-identical to Ubuntu's ("Origin: Ubuntu") | "Pop!_OS" / `pop` / "ubuntu debian" via `dpkg-divert`; `DISTRIB_ID=Pop` | ID_LIKE, `UBUNTU_CODENAME`, own packages named `ubuntu-minimal` | None public |
| elementary OS 8 | Canonical's binaries; 80 overrides in a PPA | `archive.ubuntu.com` | "elementary OS" / `elementary` / "ubuntu debian" | ID_LIKE, `UBUNTU_NAME="Ubuntu"`, `UBUNTU_PRETTY_NAME`; motd-news still fetches `motd.ubuntu.com` | None public (named by Michael Hall in 2015 as a derivative it "works our well" for) |
| Zorin OS 18 (commercial editions) | Canonical's binaries; 261 overrides in a PPA | `archive.ubuntu.com` | "Zorin OS" / `zorin` / "ubuntu debian" | ID_LIKE, motd-news, `/etc/dpkg/origins/zorin` "Parent: Ubuntu" | None public |
| KDE neon | Canonical's builds, except about 500 of 2,058 packages that neon builds itself | `archive.ubuntu.com` | "KDE neon" / `neon` / "ubuntu debian" | `plymouth-theme-ubuntu-text`, `ubuntu-minimal`; help text disabled ("disable ubuntu references") | FAQ: "It is otherwise unrelated to the Ubuntu project or Canonical." |
| TUXEDO OS 24.04 (laptop vendor, commercial) | Canonical's binaries (`base-files 13ubuntu10.5`) plus `tuxedo-base-files` | Own mirror, Release file byte-identical to Ubuntu's | "TUXEDO OS" / `tuxedo` / "ubuntu debian" via `dpkg-divert` | `DISTRIB_ID=Ubuntu` kept, `ubuntu-pro-client` | None public |
| Linux Lite 8.0 | Canonical's binaries, no `base-files` fork | `archive.ubuntu.com` | Only `PRETTY_NAME` replaced by its build script; NAME and ID not confirmed | Probably most of Ubuntu's `os-release` | None public |
| NVIDIA Jetson Linux R36.4.4 sample rootfs | Canonical's binaries, built from `ubuntu-base-22.04.2` with `apt-get install` | `ports.ubuntu.com` | `DISTRIB_ID=Ubuntu`, `/etc/issue` "Ubuntu 22.04.5 LTS" | Everything; it ships as Ubuntu, with `ubuntu-desktop` | Canonical describes a "collaboration with NVIDIA"; no published licence covering the sample rootfs |
| ctrlX OS (Bosch Rexroth, industrial) | Ubuntu Core | Canonical | not checked | not checked | Yes, public: Canonical "provides open source security, support and software customization services for ctrlX OS" |

**The pattern.**

- Almost all of them ship Canonical's binary packages unchanged. They take them straight
  from Canonical's archive, or from a byte-identical copy signed with Ubuntu's key.
- They rebuild or divert only a few packages: `base-files`, branding, installer and some
  drivers. They put their own name in `os-release` (NAME, ID, PRETTY_NAME, the URLs), in
  `lsb-release` (DISTRIB_ID or at least DISTRIB_DESCRIPTION) and in `/etc/issue`.
- All of them keep `ID_LIKE="ubuntu debian"`, `UBUNTU_CODENAME`, the `-0ubuntu` version
  strings and packages named `ubuntu-*`.
- None of them rebuilds the whole archive. None of them uses the Ubuntu name or logo as
  its product name.
- No commercial derivative has published an agreement with Canonical. The only published
  arrangements are Mint's, known from the Council and the press, and Canonical's own
  customers (ctrlX OS, Ubuntu Core).
- No public enforcement action by Canonical against an own-named derivative was found.
  The one public dispute (2016) concerned images sold as "Ubuntu" under a contract.

### Reading

The existing answer has two layers, and they disagree.

- **What Canonical has written.** For an own-named product built from Canonical's
  binaries, Canonical's written position is consistent from 2013 to today.
  - The image may be called "based on Ubuntu" but not "Ubuntu".
  - Otherwise, "remove and replace the Trademarks" and "recompile".
  - Or take "a licence agreement ..., for which you may be required to pay".
  - The free or nearly free archive use mentioned in 2015 was for "non-commercial
    derivatives".
  - Shuttleworth's 2016 answer draws the line for devices explicitly: Ubuntu Core with
    the unmodified OS snap needs no agreement; classic deb-based images are different.
  - Canonical has never published which marks must go, or which binaries must be rebuilt.
    Its staff and moderators say it will not.
- **What the derivatives do.** Dozens of systems, commercial ones included (System76,
  TUXEDO, Zorin), ship Canonical's unmodified binaries under their own names. They
  replace the visible branding and keep the technical references (ID_LIKE, codename,
  version strings). They publish no agreement, and no enforcement against them is known.
  This is tolerance, not permission.

For IronFlockOS this means: a commercial, own-named embedded image of unmodified Ubuntu
binaries is exactly the case that Canonical's texts keep for a licence or a rebuild. It
is also exactly what many companies do without a visible licence. Only Canonical can turn
that tolerance into a permission. Whether Canonical's claimed copyright in compiled
binaries holds, for example under German law, where software is protected only as its
author's own intellectual creation (§ 69a UrhG), is a question for the lawyer. No source
fetched for this research decides it.

### Build items that can be checked now

These items follow the derivatives' pattern and Canonical's own 2007 guidance. They do
not need Canonical's answer. They reduce the "associate it with the Trademarks" risk; they
do not settle the "recompile" clause.

1. `/usr/lib/os-release`: the build already writes IronFlockOS's own file
   (`build/osrelease.sh`). Keep `ID_LIKE="ubuntu debian"` (every derivative does).
   Check that no `UBUNTU_*` field and no Ubuntu URL slips in.
2. `/etc/lsb-release` (from Ubuntu's `base-files`): set `DISTRIB_DESCRIPTION` to
   IronFlockOS. For `DISTRIB_ID`, Zimmerman's 2007 advice was to keep it; Mint, Pop!_OS
   and the others replace it, TUXEDO keeps "Ubuntu". The safer choice by current practice
   is IronFlockOS's own ID.
3. `/etc/issue`, `/etc/issue.net`, `/etc/legal`: replace them with IronFlockOS text. The
   repository's overlay has `/etc/motd` but none of these files.
4. `/etc/update-motd.d/` (`00-header`, `10-help-text`, `50-motd-news`, and the ESM
   scripts of `ubuntu-pro-client`): remove or neutralise them, as Mint and neon do. Also
   stop `motd-news` from fetching `motd.ubuntu.com`.
5. Plymouth, GRUB and any logos: the image must show no Ubuntu logo. Use of the logo for
   a derivative "requires prior permission" (Zimmerman, 2007).
6. Whether to install `ubuntu-pro-client` at all: it advertises Canonical's service under
   the Ubuntu name.
7. Keep without change: package names, `-0ubuntu` version strings,
   `/etc/dpkg/origins/ubuntu` and apt sources pointing at `ports.ubuntu.com` (or a
   byte-identical copy). Zimmerman 2007 says version strings need no change, and every
   derivative keeps them.
8. Product text: "IronFlockOS, based on Ubuntu 24.04" is fair use by Canonical's own 2007
   words and by the 2012 policy. "Ubuntu" alone, or the logo, is not.

### For the lawyer or Canonical

A written question to Canonical is still needed if IronFlock wants permission rather than
tolerance. Canonical's published terms do not answer it; they point to a licence. Expect
a slow or no answer: one in January 2026 got none in public, and the Community Council's
October 2025 request got none on the list. The alternatives are Ubuntu Pro for Devices,
if it covers this, or the Debian userspace IronFlockOS already builds for other targets,
if NVIDIA's packages allow it.

**Shortest form of the question:** "We publish a commercial embedded Linux image under
our own name. It contains unmodified Ubuntu 24.04 binary packages from your archive, with
Ubuntu logos and product naming removed and 'based on Ubuntu' stated. Do we need a
licence agreement with Canonical for this, and if so, does Ubuntu Pro for Devices cover
it?"

## 9. Question 8: a revocable licence, or a written agreement with NVIDIA

**The question.** The licence is revocable, and every Jetson device in the field depends
on it. Does IronFlock accept that, or seek a written distribution agreement, for example
through NVIDIA's partner programme?

### Text

- 1.1: "a non-exclusive, revocable, non-transferable and non-sublicensable (except as expressly provided in this Agreement) license".
- §7: "This Agreement will automatically terminate without notice from NVIDIA if you fail to comply with any of the terms in this Agreement or if you commence or participate in any legal proceeding against NVIDIA with respect to the SOFTWARE. ... Your prior distributions according to this Agreement are not affected by termination."
- §14: "You may not, without NVIDIA's prior written consent, assign, delegate or transfer any of its rights or obligations under this Agreement".
- §18: "This Agreement may only be modified in a writing signed by an authorized representative of each party."
- §20: "For any questions regarding this Agreement, please contact NVIDIA at driver-licensing@nvidia.com".
- §5: "NVIDIA is not obligated to support any SOFTWARE, unless there is a separate agreement for this purpose."

### NVIDIA said and practice

- NVIDIA's embedded ecosystem table has the tiers Elite, Preferred, Partner, Registered
  and Distributor. Only three entries carry the category "Distro and OS": balena
  (Preferred, "System Software, Distro and OS"), Peridio (Partner, "Distro and OS",
  "Avocado OS ... a production-grade, AI-optimized Yocto-based Linux") and Concurrent
  Real-Time (Partner).
- NVIDIA's forum announcement of Yocto support (topic 375042): "Distribution and ISV
  partners include Konsulko Group and Peridio, offering complete OS solutions and Balena,
  providing container-based fleet management and deployment at scale."
- NVIDIA Partner Network page: "The Registered partner is an entry into some of the NPN
  Partner types." and "Elite partners represent the deepest level of partnership with
  NVIDIA". It lists partner types such as Independent Software Vendor and OEM and an
  "Embedded Compute" competency. It says nothing about software redistribution rights.
- A redistribution question in the forum (topic 268839) was moved to private e-mail.
- No public text of any NVIDIA software distribution agreement was found.

### Reading

Any distribution terms NVIDIA gives partners are private. The visible route has two
parts: write to the address the Agreement names (`driver-licensing@nvidia.com`), and
join the partner network in the category NVIDIA already uses for OS vendors ("Distro and
OS"). §7 protects devices already shipped ("prior distributions ... are not affected"),
but not future updates. A signed confirmation under §18 would also settle questions 1, 2
and 5 in one step.

### For the lawyer or NVIDIA

**Draft question to NVIDIA:** "We are a German company that publishes an open-source
Linux OS for Jetson Orin devices and plan to distribute your Jetson Linux binaries under
section 1.1(d). Does NVIDIA offer a written distribution agreement or partner programme
for OS vendors, for example in the 'Distro and OS' category of your Jetson ecosystem, and
what does it take to join? We would also like written answers to the questions attached
(questions 1, 2 and 5)."

## 10. What the review should change

These points of `docs/jetson-licence-review.md` are out of date or incomplete:

1. **The two scripts are MIT-licensed** in r39.2.1 (`l4t_initrd_flash.func`,
   `l4t_create_images_for_kernel_flash.sh`; also `l4t_generate_soc_capsule.sh`;
   `flash.sh` is BSD-3-Clause). The review treats them under 1.1(b) and 2.5 (table row
   1.1(b), question 2, point 4). The layout XML is NVIDIA-proprietary, so 1.1(b) still
   applies to it.
2. **The Agreement's version.** The r39.2.1 copy is "(v. February 25, 2025)"; the JetPack
   EULA page still shows "(v. November 23, 2023)" with "operating systems". The review
   notes the wording difference but not the dates. The r39.2.1 copy also names a contact
   (§20, `driver-licensing@nvidia.com`) and the rule that only a signed writing changes
   it (§18); both matter for questions 1, 5 and 8.
3. **GPLv2 §3's "same place" rule.** Point 3 of the review presents the mirror as
   IronFlock's source offer. For downloads it is more than an offer: it is distribution of
   the source under the last paragraph of §3. For other channels (appliance mirror, OTA,
   partners) a written offer is still needed.
4. **NVIDIA's own Yocto images (JetPack 7.2).** Since the review, NVIDIA itself publishes
   tool-made flash packages and names OS "distribution partners". This is new evidence for
   questions 1, 2 and 8.
5. **Export.** The question's premise ("NVIDIA's proprietary parts are not publicly
   available open source") matters for the US rules. The EU definition of "in the public
   domain" ignores copyright restrictions, so in the EU those parts may count as public.
6. **Product liability.** Question 4 should also name the EU Product Liability Directive
   2024/2853, in force for products placed on the market after 9 December 2026.

7. **Ubuntu (question 7).** The Canonical policy the review cites (15 July 2015) is still
   the current one. The review's question should name the device case: Canonical's
   founder said in 2016 that an Ubuntu Core image with the unmodified OS snap needs no
   agreement, and set classic deb-based images apart. The review should also list the
   branding files the image still takes from Ubuntu's packages (`/etc/lsb-release`,
   `/etc/issue`, `/etc/issue.net`, `/etc/legal`, `/etc/update-motd.d/`), next to the
   `os-release` the build already writes.

## 11. Gaps: where no evidence was found

- Q4: how other vendors pass the Critical Applications exclusion and the indemnity on.
  Not researched.
- Q5: any NVIDIA export classification for Jetson software; BAFA guidance on the
  Cryptography Note; the EU embargo regulations other than Russia.
- Q7:
  - Linux Mint's own statement on the 2014 deal and its terms. The DistroWatch interview
    could not be fetched, and only press reports and the Ubuntu Community Council speak
    of it.
  - Any agreement, or the absence of one, for Pop!_OS, elementary OS, Zorin OS, TUXEDO OS
    or Linux Lite. NVIDIA's arrangement for its Ubuntu-branded sample rootfs.
  - Whether Ubuntu Pro for Devices includes a licence to redistribute an own-branded image.
    The pages show only "Trademark use".
  - Matthew Garrett's blog posts, which timed out; only his LWN comments were read.
  - The `os-release` NAME and ID of Linux Lite 8.0.
  - Any court decision or law-firm note on copyright in compiled binaries.
- Q8: the terms of any NVIDIA partner or distribution agreement.
- Q1: whether the partner packages (Seeed, Advantech, AVerMedia, Antmicro) contain
  NVIDIA's licence file; they were not opened. balenaCloud's and Peridio's download flows
  need a login and were not seen.

## Sources

All fetched on 2026-11-17, with curl unless marked "WebFetch" (read through a fetch
tool, not saved).

### NVIDIA: licence, BSP, documentation, downloads

- https://developer.download.nvidia.com/embedded/L4T/r39_Release_v2.1/release/Tegra_Software_License_Agreement-Tegra-Linux.txt — the NVIDIA Driver License Agreement, r39.2.1 copy (v. February 25, 2025), SHA-1 as in the review.
- https://developer.download.nvidia.com/embedded/L4T/r39_Release_v2.1/release/Jetson_Linux_R39.2.1_aarch64.tbz2 — the BSP, streamed; only these files kept: `tools/kernel_flash/l4t_initrd_flash.func`, `l4t_create_images_for_kernel_flash.sh`, `flash_l4t_t234_nvme_rootfs_ab.xml`, `flash.sh`, `generate_capsule/l4t_generate_soc_capsule.sh`, `bootloader/tegraflash.py`, `bootloader/generic/cfg/flash_t234_qspi.xml`, `bootloader/LICENSE*`, `nv_tegra/LICENSE*`; also `l4t_sign_image.sh` and `tools/l4t_create_default_user.sh`.
- https://docs.nvidia.com/jetson/jetpack/eula/index.html — JetPack EULA page: Driver License Agreement v. November 23, 2023 for "JetPack OS" (WebFetch).
- https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/RM/LegalInformation.html — Developer Guide legal notice, incl. the hardware's life-support exclusion.
- https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/FlashingSupport.html — Flashing Support, massflash for factories.
- https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/JetsonISOCustomization.html — ISO customisation, "ship it as a custom nvidia-l4t-bootloader" package.
- https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/AR/YoctoOnJetson.html — Yocto on Jetson, "officially supported NVIDIA path".
- https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/SoftwarePackagesAndTheUpdateMechanism.html — update mechanism (background).
- https://developer.nvidia.com/blog/deploy-agentic-ready-ai-at-the-edge-with-memory-efficiency-in-nvidia-jetpack-7-2/ — JetPack 7.2 blog: NVIDIA releases Yocto reference images.
- https://developer.nvidia.com/embedded/jetpack/downloads/archive-7.2.1.md — JetPack 7.2.1 downloads: Yocto tegraflash packages and the "By downloading ..." notice.
- https://developer.download.nvidia.com/embedded/L4T/r39_Release_v2.1/yocto/demo-image-reference-jetson-orin-nano-devkit-nvme.rootfs.tegraflash-tar.zst — NVIDIA's Yocto flash package, streamed: partial listing and its `l4t_sign_image.sh`.
- https://developer.download.nvidia.com/embedded/L4T/r39_Release_v2.1/yocto/demo-image-reference-jetson-orin-nano-devkit-nvme-SBOM.tar.gz — its SBOM, lists the OE4T patches.
- https://repo.download.nvidia.com/jetson/som/dists/r39.2/main/binary-arm64/Packages and https://repo.download.nvidia.com/jetson/common/dists/r39.2/main/binary-arm64/Packages — NVIDIA apt indexes (no licence field).
- https://repo.download.nvidia.com/jetson/som/pool/main/n/nvidia-l4t-oobe/nvidia-l4t-oobe_39.2.1-20260806224157_arm64.deb — first-boot licence screen.
- https://repo.download.nvidia.com/jetson/ — apt repository index, no login, no export notice.
- https://docs.nvidia.com/sdk-manager/sdkm-command-line-install/index.html — SDK Manager `--licenses accept`.
- https://docs.nvidia.com/jetson/agx-orin-devkit/user-guide/latest/quick_start.html — "Review and accept NVIDIA Jetson software EULA".
- https://developer.nvidia.com/embedded/ecosystem.md — Jetson partner table with tiers and categories ("Distro and OS").
- https://www.nvidia.com/en-us/about-nvidia/partners/become-a-partner/ — NVIDIA Partner Network tiers and types.
- https://www.nvidia.com/en-us/about-nvidia/company-policies/export-regulations/ — NVIDIA export classification page (table read in a browser, not saved).
- https://www.nvidia.com/content/dam/en-zz/Solutions/about-us/documents/NVIDIA-Trademark-and-Logo-Usage-Guidelines.pdf — 2019 trademark guidelines (the current web page returned "Page Not Found").

### NVIDIA developer forum (raw text from `/raw/<id>`, roles from `/t/<id>.json`)

- https://forums.developer.nvidia.com/t/51156 — 2017-2019, "NVIDIA will permit the redistribution of L4T" (kayccc, moderator).
- https://forums.developer.nvidia.com/t/78274 — 2019, kernel under GPLv2, no NVIDIA answer on the binaries.
- https://forums.developer.nvidia.com/t/233265 — 2022, carrier-board maker shipping L4T: "should be fine".
- https://forums.developer.nvidia.com/t/250727 — 2023, same answer, refers to Canonical.
- https://forums.developer.nvidia.com/t/268839 — 2023, distribution question moved to e-mail.
- https://forums.developer.nvidia.com/t/306285 — 2024, moderator sends Ubuntu question to Canonical.
- https://forums.developer.nvidia.com/t/311485 — 2024, unchanged JetPack supplied to customers: "should be fine".
- https://forums.developer.nvidia.com/t/320934 — 2025, same answer, refers to Canonical.
- https://forums.developer.nvidia.com/t/365711 — 2026, notice file question; answer points to the Agreement.
- https://forums.developer.nvidia.com/t/375042 — 2026, JetPack 7.2 Yocto announcement, "Distribution and ISV partners".
- https://forums.developer.nvidia.com/t/64879 — 2018, firmware licensing under the old licence.
- https://forums.developer.nvidia.com/t/jetson-eccn-codes/216341 and https://forums.developer.nvidia.com/t/jetson-nano-export-controls/75599 — ECCN 5A992.c for modules.
- https://forums.developer.nvidia.com/t/jetson-tk1-eccn-number/35307 — 2014 request for a software ECCN, no NVIDIA answer.

### Other Jetson distributors

- https://raw.githubusercontent.com/OE4T/meta-tegra/master/ (files `recipes-bsp/tegra-binaries/tegra-binaries-39.2.1.inc`, `tegra-flashtools_39.2.1.bb`, `files/0003`-`0007` patches, `classes-recipe/image_types_tegra.bbclass`, `README.md`, `docs/`) — OE4T meta-tegra.
- https://github.com/OE4T/meta-tegra/issues/1806 (via `gh api`) — maintainer doubts that mirroring NVIDIA artifacts is allowed.
- `gh api repos/OE4T/tegra-demo-distro/releases` — no published releases.
- https://raw.githubusercontent.com/balena-os/balena-jetson-orin/master/ (`tegra-flash-dry_39.2.0.bb`, repository tree via `gh api`) — QSPI dumps under an Apache-2.0 label.
- https://raw.githubusercontent.com/balena-os/jetson-flash/master/ (`README.md`, `Orin_Flash/Dockerfile`, `Orin_Flash/flash_orin.sh`, `assets/jetson-agx-orin-devkit-assets/resinOS.patch`) — balena's flasher.
- https://ubuntu.com/download/nvidia-jetson (and `?format=md`) — Canonical's Jetson download page, boot firmware from NVIDIA.
- https://canonical-ubuntu-for-jetson.readthedocs-hosted.com/ (`how-to/flash/`, `classic/jp-installation/`) — Canonical's Jetson documentation.
- https://api.launchpad.net/devel/~ubuntu-tegra/+archive/ubuntu/updates — Canonical's PPA, "a copy of binaries released by NVIDIA".
- https://canonical.com/blog/ubuntu-now-officially-supports-nvidia-jetson-powering-the-future-of-ai-at-the-edge — Canonical's Jetson announcement.
- https://hub.mender.io/raw/1360, https://hub.mender.io/raw/3968, https://hub.mender.io/raw/6985 — Mender's Jetson guides.
- https://wiki.seeedstudio.com/reComputer_J4012_Flash_Jetpack/ — Seeed massflash packages.
- https://learn.advantech.com/BSP/MIC-711-OX4A1/Ubuntu%2022.04/6.1.0_V1.0.0 — Advantech full BSP download.
- https://professional.avermedia.com/support/faq/how-to-flash-bsp-for-orin-nano-nx — AVerMedia full `Linux_for_Tegra` download.
- https://auvidea.gitbook.io/software-setup-guide/guide/simple-flashing-guide — Auvidea download package.
- https://antmicro.github.io/jetson-orin-baseboard/getting_started.html — Antmicro prebuilt tegraflash tarballs.
- https://web.archive.org/web/2026id_/https://connecttech.com/ftp/Drivers/L4T-Release-Notes/Jetson-Orin-NX-Orin-Nano/ORIN-NX-NANO-36.3.0.pdf — Connect Tech release notes (archive copy; the live site blocks scripts).
- https://www.forecr.io/blogs/installation/jetpack-7-2-installation-for-dsbox-ornx and https://github.com/forecr/dsboard_ornx_orin_bsp — Forecr overlay.

### Canonical and Ubuntu

- https://canonical.com/legal/intellectual-property-policy (same text at https://ubuntu.com/legal/intellectual-property-policy) — IP rights policy, dated 15 July 2015.
- https://canonical.com/blog/clarification-on-ip-rights-policy — Canonical, 15 July 2015, the aggregate-work clause.
- https://www.fsf.org/news/canonical-updated-licensing-terms — FSF statement, 15 July 2015 (commentary).
- https://sfconservancy.org/news/2015/jul/15/ubuntu-ip-policy/ — Software Freedom Conservancy statement, 15 July 2015 (commentary).
- https://lists.ubuntu.com/archives/ubuntu-news-team/2014-February/001941.html — Ubuntu Community Council on Linux Mint's licence, 13 February 2014.
- https://www.networkworld.com/article/748068/opensource-subnet-making-sense-of-the-ubuntu-licensing-fiasco.html — press report on the Mint case (background only).
- https://blog.linuxmint.com/?s=Canonical — Mint blog search; nothing on the agreement.
- http://apt.pop-os.org/ubuntu/dists/noble/Release — Pop!_OS's copy of the Ubuntu archive.

### Question 7: Canonical's statements, critics and derivatives

- https://canonical.com/legal/intellectual-property-policy?format=md and https://canonical.com/legal/intellectual-property-policy/2013-05-14?format=md — the current IP policy and its 2013 version.
- https://canonical.com/legal/ubuntu-pro-service-terms?format=md — Ubuntu Pro service terms of 1 June 2026, definition of "Ubuntu Content", trademark licence clause.
- https://canonical.com/legal/ubuntu-pro-description?format=md — Ubuntu Pro description, container images from Pro content.
- https://ubuntu.com/pricing/devices?format=md and https://ubuntu.com/pro/devices?format=md — device services, "Trademark use", one-time fee per device.
- https://ubuntu.com/legal/trademarks — current trademark list, no Remix rules.
- https://web.archive.org/web/20121228045716id_/http://www.ubuntu.com/aboutus/trademarkpolicy — the Ubuntu trademark policy as archived in December 2012 (Remix rules, commercial intent).
- https://lists.ubuntu.com/archives/snappy-devel/2016-May/001843.html — Mark Shuttleworth, 14 May 2016, Ubuntu Core images need no agreement, unlike deb-based images.
- https://lists.ubuntu.com/archives/ubuntu-community-team/2015-May/ (messages 000422, 000426, 000429, 000432, 000434, 000435, 000438, 000441, 000442, 000443, 000457, 000458, 000462, 000464, 000472, 000474, 000478, 000480) — the May 2015 thread on the IP policy: Jonathan Riddell, Michael Hall and others.
- https://lists.ubuntu.com/archives/ubuntu-devel/2025-October/043516.html and https://lists.ubuntu.com/archives/ubuntu-devel/2025-December/043533.html — Community Council member's request for clarification on remixes; subject indexes of ubuntu-devel, October 2025 to November 2026, checked for replies.
- https://lists.ubuntu.com/archives/ubuntu-devel/2007-January/023143.html (also 023138, 023188) and https://lists.ubuntu.com/archives/ubuntu-devel/2006-March/016900.html — Matt Zimmerman on derivatives, trademarks and the archives.
- https://raw.githubusercontent.com/ubuntu/wiki-archives/main/UbuntuWiki/D/DerivativeDistroHowto.wiki — archived Ubuntu wiki guide for derivatives (unofficial, quotes Zimmerman).
- https://discourse.ubuntu.com/t/74625 — January 2026 thread on pre-installing a modified Ubuntu on commercial hardware.
- https://discourse.ubuntu.com/t/54191 — January 2025 thread on selling PCs with a customised Ubuntu.
- https://canonical.com/blog/taking-a-stand-against-unstable-risky-unofficial-ubuntu-images?format=md — Mark Shuttleworth, 1 December 2016, the cloud dispute.
- https://hub.docker.com/v2/repositories/library/ubuntu/ — Docker Hub's official `ubuntu` image description.
- https://blogs.kde.org/2014/02/14/no-licence-needed-kubuntu-derivative-distributions — Jonathan Riddell, 14 February 2014 (commentary).
- https://www.jonobacon.com/2015/08/28/ubuntu-canonical-and-ip/ — Jono Bacon, 28 August 2015 (commentary).
- https://lwn.net/Articles/646235/, https://lwn.net/Articles/646275/, https://lwn.net/Articles/665263/, https://lwn.net/Articles/1018189/ — LWN comment threads of 2015 and 2025, Matthew Garrett's comments (commentary).
- https://www.infoworld.com/article/2243953/will-canonical-force-linux-mint-to-license-ubuntu-binary-packages.html — InfoWorld, 11 December 2013, the Mint request.
- https://www.cio.com/article/2949217/canonical-changes-licensing-terms-to-comply-with-gpl.html — CIO, 2015, Mint "signing a deal".
- Derivatives, from their own files:
  - Linux Mint: http://packages.linuxmint.com/dists/zena/ and `pool/` (`base-files_13ubuntu10mint22.3.0_amd64.deb`, `mintsources_2.4.3_all.deb`, `ubuntu-system-adjustments_2025.12.16-zena_all.deb`).
  - Pop!_OS: http://apt.pop-os.org/ubuntu/dists/noble/, http://apt.pop-os.org/release/dists/noble/ (`pop-default-settings`), https://github.com/pop-os/iso; compared with http://archive.ubuntu.com/ubuntu/dists/noble/Release.
  - elementary OS: https://ppa.launchpadcontent.net/elementary-os/os-patches/ubuntu/ and https://github.com/elementary/os (branch `livebuild`).
  - Zorin OS: https://ppa.launchpadcontent.net/zorinos/stable/ubuntu/ and https://ppa.launchpadcontent.net/zorinos/patches/ubuntu/.
  - KDE neon: https://files.kde.org/neon/images/desk/user/20261025-1825/ (manifest), https://archive.neon.kde.org/user/, https://invent.kde.org/neon/neon/livecd-rootfs/-/raw/Neon/release_noble/live-build/auto/config, https://neon.kde.org/faq.
  - Linux Lite: https://repo.linuxliteos.com/linuxlite/ and https://www.linuxliteos.com/forums/archive/index.php/thread-8189.html.
  - TUXEDO OS: https://os.tuxedocomputers.com/ (manifest), https://txos.tuxedocomputers.com/ubuntu/ (`tuxedo-base-files`), https://mirrors.tuxedocomputers.com/ubuntu/mirror/archive.ubuntu.com/ubuntu/dists/noble/Release.
  - NVIDIA sample rootfs: the first 30 MB of https://developer.download.nvidia.com/embedded/L4T/r36_Release_v4.4/release/Tegra_Linux_Sample-Root-Filesystem_R36.4.4_aarch64.tbz2 and of `Jetson_Linux_R36.4.4_aarch64.tbz2` (`tools/samplefs/`), https://docs.nvidia.com/jetson/archives/r36.4.4/DeveloperGuide/ (Root File System, Legal); https://canonical.com/blog/ubuntu-now-officially-supports-nvidia-jetson-powering-the-future-of-ai-at-the-edge.
  - ctrlX OS: https://canonical.com/blog/bosch-rexroth-adopts-ubuntu-core-and-snaps-for-app-based-ctrlx-automation-platform and https://apps.boschrexroth.com/microsites/ctrlx-automation/en/portfolio/ctrlx-os/.

### GPL, FreeRTOS and written offers

- https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt — GPLv2 text.
- https://www.gnu.org/licenses/gpl-faq.html — FSF GPL FAQ.
- https://next.copyleft.org/archive/comprehensive-gpl-guide.pdf (reached from https://copyleft.org/guide/) — "Copyleft and the GNU GPL", archived edition (commentary).
- FreeRTOS V8.1.2 exception: `bootloader/LICENSE.spe_t234.bin` in the BSP above.
- https://www.igel.com/general-public-license/ — IGEL's written offer.
- https://download.sew-eurodrive.com/download/html/31982190/en-EN/54836230667.html — SEW-EURODRIVE's written offer.
- https://www.schueco.com/com/osci — Schüco's written offer.
- https://firmware.allnet.de/media/files/written-offer.txt — ALLNET's written offer.

### German and EU law

- https://www.gesetze-im-internet.de/bgb/__307.html and https://www.gesetze-im-internet.de/bgb/__310.html — BGB §§ 307, 310 (standard terms).
- http://publications.europa.eu/resource/celex/32024L2853 — Directive (EU) 2024/2853 on liability for defective products.
- http://publications.europa.eu/resource/celex/02021R0821-20260921 — Regulation (EU) 2021/821, consolidated 21.09.2026, English and German (EUR-Lex itself blocks scripts; this is the same text from the EU Publications Office).
- http://publications.europa.eu/resource/celex/02014R0833-20260724 — Regulation 833/2014 (Russia), consolidated 24.07.2026.
- https://www.bafa.de/SharedDocs/Downloads/DE/Aussenwirtschaft/afk_merkblatt_exportkontrolle_bafa.pdf?__blob=publicationFile&v=3 — BAFA, Merkblatt "Exportkontrolle und das BAFA", 10th ed., Nov 2024.
- https://www.bafa.de/SharedDocs/Downloads/DE/Aussenwirtschaft/afk_merkblatt_itt.pdf?__blob=publicationFile&v=2 — BAFA, Merkblatt "Immaterieller Technologietransfer", May 2024.

### US export law

- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=734&section=734.3 — 15 CFR 734.3, items subject to the EAR.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=734&section=734.4 — 734.4, de minimis.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=734&section=734.7 — 734.7, published.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=734&section=734.13 and `section=734.14` — export and reexport.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=734&section=734.17 — 734.17, encryption software on the internet, precautions.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=740&section=740.17 — License Exception ENC, mass market.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=740&appendix=Supplement%20No.%201%20to%20Part%20740 — Country Groups E:1, E:2.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=742&section=742.15 — 742.15, encryption items.
- https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-15?part=746&section=746.1 and `section=746.8` — embargoes; Russia and Belarus.
- https://www.bis.gov/learn-support/encryption-controls/mass-market — BIS mass-market page.
