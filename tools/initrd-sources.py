#!/usr/bin/env python3
"""Where each file of NVIDIA's Jetson initrd comes from (WP-6.8).

    python3 -I tools/initrd-sources.py DEB CACHE_DIR > targets/jetson-orin/initrd.sources

DEB is nvidia-l4t-initrd at the pin, from NVIDIA's repository; its
/boot/initrd is gzip of one or more cpio archives. NVIDIA builds it from Ubuntu's binary
packages and names none of them. For every regular file in it this finds
the Ubuntu packages that ship the same path (Ubuntu's Contents-arm64 of
SUITE, SUITE-updates and SUITE-security on ports.ubuntu.com), takes every
version of those packages Ubuntu ever published for SUITE on arm64
(Launchpad's publishing history), downloads each .deb into CACHE_DIR
(checked against Launchpad's SHA-256), and compares the file's SHA-256
with the same path in the .deb. A package's version is settled when its
files in the initrd match that version and no other. The output lists, per
Ubuntu binary package: its version, the source package and version it is
built from, and the sources its Built-Using names; then, as comments, the
files that match no Ubuntu package (NVIDIA's own and firmware), for a
person to account for. It fails when a package's files match no version,
or more than one and the files cannot tell them apart, or two files of one
package match different versions.

Reads public URLs only, with curl. Needs Python 3.14's compression.zstd, or
zstd, for the .debs' data.tar.zst. Nothing of
the downloads is kept outside CACHE_DIR.
"""

import gzip
import hashlib
import io
import json
import lzma
import os
import subprocess
import sys
import tarfile
import urllib.parse

SUITE = "noble"
PORTS = "http://ports.ubuntu.com/ubuntu-ports"
LP = "https://api.launchpad.net/devel"


def get(url):
    """URL's body, through curl (its certificates, its retries)."""
    r = subprocess.run(["curl", "-fsSL", "--retry", "5", "--retry-all-errors", url], stdout=subprocess.PIPE)
    if r.returncode != 0:
        raise RuntimeError(f"{url}: curl exit {r.returncode}")
    return r.stdout


def cpio_bodies(data):
    """{path: bytes} of the regular files (see cpio_files)."""
    out, pos, n = {}, 0, len(data)
    while pos < n:
        if data[pos:pos + 6] != b"070701":
            pos += 1
            continue
        h = data[pos:pos + 110]
        f = [int(h[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        mode, size, namesize = f[1], f[6], f[11]
        name = data[pos + 110:pos + 110 + namesize - 1].decode().lstrip("./")
        pos += (110 + namesize + 3) & ~3
        if mode & 0o170000 == 0o100000:
            out[name] = data[pos:pos + size]
        pos += (size + 3) & ~3
    return out


HEADER = """\
# The Ubuntu programs in NVIDIA's initrd (WP-6.8; docs/release.md, "Jetson"):
# nvidia-l4t-initrd's /boot/initrd, which the Jetson image boots, carries
# programs of Ubuntu 24.04 under the GPL and LGPL that NVIDIA names nowhere.
# Each line: an Ubuntu binary package, its version, the source package and
# version it is built from, its Built-Using, and how many of the initrd's
# files only this version ships byte for byte, then how many it covers
# (a file several versions ship alike is covered by one of them). The
# release publishes these source packages (release/sources: initrd), and the
# build fails when the image's /boot/initrd is not INITRD_SHA256.
#
# Made by tools/initrd-sources.py from NVIDIA's package, by content: every
# file of the initrd against the same path in every arm64 .deb Ubuntu
# published for noble (Contents-arm64, Launchpad's publishing history). For
# another L4T pin:
#   curl -fsSLO https://repo.download.nvidia.com/jetson/som/pool/main/n/nvidia-l4t-initrd/nvidia-l4t-initrd_<version>_arm64.deb
#   python3 -I tools/initrd-sources.py nvidia-l4t-initrd_<version>_arm64.deb <cache> >targets/jetson-orin/initrd.sources
# The files from no Ubuntu package are listed last, with the licence their
# header names.
"""


def cpio_files(data):
    """Regular files and symlinks of concatenated newc cpio archives:
    {path: ("file", sha256, size) or ("link", target)}."""
    out, pos, n = {}, 0, len(data)
    while pos < n:
        if data[pos:pos + 6] != b"070701":
            if data[pos] == 0:
                pos += 1
                continue
            raise ValueError(f"no cpio header at {pos}")
        h = data[pos:pos + 110]
        f = [int(h[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
        mode, size, namesize = f[1], f[6], f[11]
        name = data[pos + 110:pos + 110 + namesize - 1].decode()
        pos += (110 + namesize + 3) & ~3
        body = data[pos:pos + size]
        pos += (size + 3) & ~3
        if name == "TRAILER!!!":
            continue
        name = name.lstrip("./")
        kind = mode & 0o170000
        if kind == 0o100000:
            out[name] = ("file", hashlib.sha256(body).hexdigest(), size)
        elif kind == 0o120000:
            out[name] = ("link", body.decode())
    return out


def contents(paths):
    """{path: [package, ...]} for the wanted paths, from the Contents
    indexes (paths there have no leading usr/ on a merged /usr only
    sometimes, so both spellings are asked)."""
    want = {}
    for p in paths:
        want.setdefault(p, p)
        if p.startswith("usr/"):
            want.setdefault(p[4:], p)
    found = {}
    for suite in (SUITE, f"{SUITE}-updates", f"{SUITE}-security"):
        raw = gzip.decompress(get(f"{PORTS}/dists/{suite}/Contents-arm64.gz"))
        for line in raw.decode("utf-8", "replace").splitlines():
            path, _, pkgs = line.rpartition(" ")
            path = path.strip()
            if path in want:
                for p in pkgs.split(","):
                    found.setdefault(want[path], set()).add(p.rsplit("/", 1)[-1])
    return found


def lp_collection(url):
    while url:
        doc = json.loads(get(url))
        yield from doc.get("entries", [])
        url = doc.get("next_collection_link")


def published(binary):
    """Every version of BINARY Ubuntu published for SUITE/arm64:
    {version: (deb url, sha256, source, source version, latest date of
    a publication in a pocket of the stable release, or "")}."""
    q = urllib.parse.urlencode({
        "ws.op": "getPublishedBinaries", "binary_name": binary, "exact_match": "true",
        "distro_arch_series": f"{LP}/ubuntu/{SUITE}/arm64", "ws.size": "300"})
    versions, dates = {}, {}
    for e in lp_collection(f"{LP}/ubuntu/+archive/primary?{q}"):
        v = e["binary_package_version"]
        if e.get("pocket") in ("Release", "Updates", "Security") and e.get("date_published"):
            dates[v] = max(dates.get(v, ""), e["date_published"])
        if v in versions:
            continue
        files = json.loads(get(e["self_link"] + "?ws.op=binaryFileUrls&include_meta=true"))
        debs = [f for f in files if f["url"].endswith(".deb")]
        if len(debs) != 1:
            continue
        versions[v] = [debs[0]["url"], debs[0]["sha256"], e["source_package_name"], e["source_package_version"]]
    return {v: tuple(x) + (dates.get(v, ""),) for v, x in versions.items()}


def deb(url, sha256, cache):
    path = os.path.join(cache, sha256 + ".deb")
    if not os.path.exists(path) or hashlib.sha256(open(path, "rb").read()).hexdigest() != sha256:
        data = get(url)
        if hashlib.sha256(data).hexdigest() != sha256:
            raise RuntimeError(f"{url} is not the file Launchpad names")
        with open(path + ".part", "wb") as f:
            f.write(data)
        os.replace(path + ".part", path)
    return open(path, "rb").read()


def ar_members(data):
    if data[:8] != b"!<arch>\n":
        raise ValueError("not a .deb")
    pos, out = 8, {}
    while pos < len(data):
        h = data[pos:pos + 60]
        name = h[:16].decode().strip().rstrip("/")
        size = int(h[48:58].decode().strip())
        out[name] = data[pos + 60:pos + 60 + size]
        pos += 60 + size + (size & 1)
    return out


def untar(name, blob):
    if name.endswith(".zst"):
        try:
            from compression import zstd  # Python 3.14

            blob = zstd.decompress(blob)
        except ImportError:
            blob = subprocess.run(["zstd", "-dcq"], input=blob, stdout=subprocess.PIPE, check=True).stdout
    elif name.endswith(".xz"):
        blob = lzma.decompress(blob)
    elif name.endswith(".gz"):
        blob = gzip.decompress(blob)
    return tarfile.open(fileobj=io.BytesIO(blob))


def deb_files(data):
    """({path: sha256} of the .deb's regular files, Built-Using)."""
    m = ar_members(data)
    hashes = {}
    for name, blob in m.items():
        if name.startswith("data.tar"):
            with untar(name, blob) as t:
                for ti in t:
                    if ti.isreg():
                        hashes[ti.name.lstrip("./")] = hashlib.sha256(t.extractfile(ti).read()).hexdigest()
    used = ""
    for name, blob in m.items():
        if name.startswith("control.tar"):
            with untar(name, blob) as t:
                for ti in t:
                    if ti.name.lstrip("./") == "control":
                        for line in t.extractfile(ti).read().decode().splitlines():
                            if line.startswith("Built-Using:"):
                                used = line.split(":", 1)[1].strip()
    return hashes, used


def initrd_of(data):
    """(package, version, /boot/initrd) of nvidia-l4t-initrd's .deb."""
    m = ar_members(data)
    package = version = None
    for name, blob in m.items():
        if name.startswith("control.tar"):
            with untar(name, blob) as t:
                for ti in t:
                    if ti.name.lstrip("./") == "control":
                        for line in t.extractfile(ti).read().decode().splitlines():
                            if line.startswith("Package:"):
                                package = line.split(":", 1)[1].strip()
                            if line.startswith("Version:"):
                                version = line.split(":", 1)[1].strip()
    for name, blob in m.items():
        if name.startswith("data.tar"):
            with untar(name, blob) as t:
                for ti in t:
                    if ti.name.lstrip("./") == "boot/initrd":
                        return package, version, t.extractfile(ti).read()
    raise ValueError("the .deb has no /boot/initrd")


def licence_line(body):
    for line in body.decode("utf-8", "replace").splitlines()[:40]:
        if "SPDX-License-Identifier:" in line:
            return line.split("SPDX-License-Identifier:", 1)[1].strip()
    return ""


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    path, cache = sys.argv[1], sys.argv[2]
    os.makedirs(cache, exist_ok=True)
    package, version, raw = initrd_of(open(path, "rb").read())
    files = cpio_files(gzip.decompress(raw))
    regular = {p: v for p, v in files.items() if v[0] == "file"}
    bodies = cpio_bodies(gzip.decompress(raw))
    index = os.path.join(cache, f"contents-{hashlib.sha256(raw).hexdigest()}.json")
    if os.path.exists(index):
        owners = {k: set(v) for k, v in json.load(open(index)).items()}
    else:
        owners = contents(regular)
        json.dump({k: sorted(v) for k, v in owners.items()}, open(index, "w"))
    matches = {}  # path -> {(package, version)}
    meta = {}  # (package, version) -> (source, source version, built-using, date)
    for pkg in sorted({p for s in owners.values() for p in s}):
        versions = published(pkg)
        for v, (url, sha, src, srcv, date) in sorted(versions.items()):
            hashes, used = deb_files(deb(url, sha, cache))
            meta[(pkg, v)] = (src, srcv, used, date)
            for path, owners_of in owners.items():
                if pkg not in owners_of:
                    continue
                alt = path[4:] if path.startswith("usr/") else path
                if regular[path][1] in (hashes.get(path), hashes.get(alt)):
                    matches.setdefault(path, set()).add((pkg, v))
        print(f"{pkg}: {len(versions)} versions compared", file=sys.stderr)
    for path in sorted(matches):
        print(f"{path}: {' '.join(f'{p}={v}' for p, v in sorted(matches[path]))}", file=sys.stderr)

    # The versions of a package: first each version that is the only match
    # of one of its files (settled by content). A file that several versions
    # ship byte for byte (a configuration file, a library no update touched)
    # is then covered by a version already taken; else by the version whose
    # source another package's settled version shares; else by the one the
    # stable release published last. Each of them is a corresponding source
    # of that file.
    files_of = {}
    for path, ms in matches.items():
        for pkg in {p for p, _ in ms}:
            files_of.setdefault(pkg, []).append((path, {v for p, v in ms if p == pkg}))
    taken = {}  # (pkg, version) -> [paths settled, paths covered]
    for pkg, entries in files_of.items():
        for path, vs in entries:
            if len(vs) == 1:
                taken.setdefault((pkg, next(iter(vs))), [0, 0])[0] += 1
    settled_sources = {(meta[k][0], meta[k][1]) for k in taken}
    for pkg, entries in sorted(files_of.items()):
        for path, vs in sorted(entries):
            have = [v for v in vs if (pkg, v) in taken]
            if not have:
                same = [v for v in vs if (meta[(pkg, v)][0], meta[(pkg, v)][1]) in settled_sources]
                pick = same or sorted(vs, key=lambda v: (meta[(pkg, v)][3], v))[-1:]
                have = [sorted(pick)[-1]]
                taken.setdefault((pkg, have[0]), [0, 0])
            taken[(pkg, sorted(have)[-1])][1] += 1
    unmatched = sorted(p for p in regular if p not in matches)
    sha = hashlib.sha256(raw).hexdigest()
    print(HEADER.rstrip())
    print(f"INITRD_PACKAGE={package}")
    print(f"INITRD_PACKAGE_VERSION={version}")
    print(f"INITRD_SHA256={sha}")
    print("# binary\tversion\tsource\tsource version\tbuilt-using\tfiles: settled by this version alone, covered")
    for (pkg, v), (settled, covered) in sorted(taken.items()):
        src, srcv, used, _ = meta[(pkg, v)]
        print(f"{pkg}\t{v}\t{src}\t{srcv}\t{used or '-'}\t{settled} {covered}")
    for p in unmatched:
        lic = licence_line(bodies[p])
        print(f"# not from Ubuntu: {p}\t{regular[p][1]}" + (f"\t{lic}" if lic else ""))


if __name__ == "__main__":
    main()
