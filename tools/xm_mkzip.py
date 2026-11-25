#!/usr/bin/env python3
"""xm_mkzip: craft upgrade packages for the XM535D1 CUpgrader tests.

The official *_all.bin is a plain ZIP holding u-boot.bin.img, u-boot.env.img,
custom-x.cramfs.img, uImage.img, romfs-x.cramfs.img, user-x.cramfs.img and
InstallDesc (JSON).  This tool copies such a zip and lets a test change one
piece at a time, so the QEMU upgrade probe can say exactly which check fires:

  --add-shell CMD      append {"Command":"Shell","Script":CMD} to UpgradeCommand
  --drop-mx8q          delete the Mx8Q field (see the "no pub, skip" path)
  --drop-crc           delete the CRC field
  --set FIELD=VALUE    overwrite a top-level InstallDesc string/number field
  --replace NAME=FILE  replace a zip member with FILE
  --corrupt NAME       flip one byte at the end of a member (payload CRC test)
  --wrap NAME=PAYLOAD  keep the member's 64-byte uImage header, replace its
                       payload, recompute ih_size, data CRC and header CRC

Everything is written to a new zip; the original package is never modified.
Members are re-compressed, so untouched members keep identical contents but the
ZIP container itself is not byte-identical to the source.
"""
import argparse
import json
import shutil
import sys
import zipfile
import zlib


def load_members(path):
    out = []
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            out.append((info.filename, z.read(info.filename), info.compress_type))
    return out


def write_members(path, members):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data, _ in members:
            z.writestr(name, data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--add-shell")
    ap.add_argument("--drop-mx8q", action="store_true")
    ap.add_argument("--drop-crc", action="store_true")
    ap.add_argument("--set", action="append", default=[])
    ap.add_argument("--replace", action="append", default=[])
    ap.add_argument("--corrupt", action="append", default=[])
    ap.add_argument("--wrap", action="append", default=[],
                    help="NAME=PAYLOAD: keep the member's 64-byte uImage header "
                         "but replace its payload with PAYLOAD (recomputes "
                         "ih_size and both CRCs)")
    a = ap.parse_args()

    members = load_members(a.src)
    names = [m[0] for m in members]
    print("src members:", names)
    idx = {n: i for i, n in enumerate(names)}
    if "InstallDesc" not in idx:
        raise SystemExit("no InstallDesc in zip")

    desc = json.loads(members[idx["InstallDesc"]][1].decode())
    print("InstallDesc fields:", list(desc.keys()))
    changed = []

    for s in a.set:
        k, v = s.split("=", 1)
        old = desc.get(k)
        try:
            vv = json.loads(v)
        except ValueError:
            vv = v
        desc[k] = vv
        changed.append("set %s: %r -> %r" % (k, old, vv))
    if a.add_shell:
        desc.setdefault("UpgradeCommand", []).append(
            {"Command": "Shell", "Script": a.add_shell})
        changed.append("add Shell cmd: %s" % a.add_shell)
    if a.drop_mx8q:
        desc.pop("Mx8Q", None)
        changed.append("drop Mx8Q")
    if a.drop_crc:
        desc.pop("CRC", None)
        changed.append("drop CRC")

    for rep in a.replace:
        name, path = rep.split("=", 1)
        if name not in idx:
            raise SystemExit("no member %r" % name)
        members[idx[name]] = (name, open(path, "rb").read(), None)
        changed.append("replace %s = %s" % (name, path))
    for w in a.wrap:
        name, path = w.split("=", 1)
        if name not in idx:
            raise SystemExit("no member %r" % name)
        _name, base, ct = members[idx[name]]
        if len(base) <= 64 or base[:4] != b"\x27\x05\x19\x56":
            raise SystemExit("%r is not a uImage-wrapped member" % name)
        payload = open(path, "rb").read()
        hdr = bytearray(base[:64])
        hdr[4:8] = b"\x00\x00\x00\x00"                # ih_hcrc
        hdr[12:16] = len(payload).to_bytes(4, "big")  # ih_size
        hdr[24:28] = (zlib.crc32(payload) & 0xffffffff).to_bytes(4, "big")
        hdr[4:8] = (zlib.crc32(bytes(hdr)) & 0xffffffff).to_bytes(4, "big")
        members[idx[name]] = (name, bytes(hdr) + payload, ct)
        changed.append("wrap %s payload=%s (%d bytes)" % (name, path, len(payload)))
    for cor in a.corrupt:
        if cor not in idx:
            raise SystemExit("no member %r" % cor)
        name, data, ct = members[idx[cor]]
        b = bytearray(data)
        b[-5] ^= 0xFF
        members[idx[name]] = (name, bytes(b), ct)
        changed.append("corrupt %s @-5" % cor)

    # keep the original InstallDesc bytes unless a test changed a field
    if any(c.startswith(("add Shell", "drop ", "set ")) for c in changed):
        members[idx["InstallDesc"]] = ("InstallDesc",
                                       json.dumps(desc).encode(), None)
    write_members(a.out, members)
    print("changes:")
    for c in changed:
        print("  -", c)
    print("wrote", a.out, "InstallDesc:", json.dumps(desc)[:400])


if __name__ == "__main__":
    main()
