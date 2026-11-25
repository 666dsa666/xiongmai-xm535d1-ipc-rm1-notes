# Root access

Root paths on the `IPC-RM1-BLK535-2M6P` (XM535D1), what each one gives, and the one
procedure that works on real hardware: the unsigned firmware upgrade on V5.01 and V5.07.

## Path matrix

| Path | Result | Status | Details |
|---|---|---|---|
| Unsigned upgrade, custom `user` partition (variant B) | Persistent root, accepted with `Ret 515` | **HW** on V5.01 and V5.07 | this page |
| Unsigned upgrade, `Shell` command in `InstallDesc` (variant A) | One-shot root command during the update | **QEMU** only | this page |
| Boot media: `ConfigImport` traversal to `mtd5` + forged U-Boot env | Persistent root console, network-only, destructive | **QEMU** only | [boot-media-root.md](boot-media-root.md) |
| Downgrade V5.07 to V5.01, then V5.01 root package | Root on V5.01 | **HW** (downgrade), **QEMU** (re-root) | this page |
| Vendor debug TCP 12901 (`/usr/bin/debug`) | Closed by default; auth bypassable (VSC), but post-auth runs fixed `timetest` only. No root shell | **HW** (closed), **QEMU** (protocol) | [debug-services.md](debug-services.md) |
| BusyBox `timetest` telnetd on TCP 50119 | Present, inactive by default, gated by `telnetctrl` | **HW** (closed), **STATIC** | [debug-services.md](debug-services.md) |
| DVRIP OP 2040 `OPTelnetControl` / `EnableKey` | Decoy, opens nothing | **QEMU**, **STATIC** | [debug-services.md](debug-services.md) |
| Port 9530 knock / XMTelnet | Subsystem absent; ports 23/4321/9530 closed | **HW**, **STATIC** | [negative-results.md](negative-results.md) |
| UART console | No usable pad on this board revision | **HW** | [negative-results.md](negative-results.md) |
| Older firmware downgrade | No pre-V5 build exists for this board | n/a | [negative-results.md](negative-results.md) |
| SPI flash write (clip + programmer) | Physical fallback and recovery | **HW** (read) | [recovery.md](recovery.md) |

An official firmware update removes the custom root, but the unsigned-upgrade path stays open:
re-root is possible after any official update tested so far.

## Why modified packages are accepted

The update package is a container with:

- `InstallDesc`: JSON metadata (`Hardware`, `DevID`, `CompatibleVersion`, `CRC`, `Mx8Q`
  signature) and an `UpgradeCommand` list (`Burn <component>` entries);
- component images: `u-boot.bin.img`, `u-boot.env.img`, `uImage.img`, `romfs-x.cramfs.img`,
  `user-x.cramfs.img`, `custom-x.cramfs.img`.

`CUpgrader` in `Sofia` contains the `Mx8Q` signature and CRC checks, but neither is enforced on
V5.01 nor on V5.07 (**HW**: modified packages return `Ret 515`).

`Sofia` strings that show the skipped checks:

```
VerifyMx8QSign, no pub, skip check Mx8Q
VerifyMx8QSign, no pub, Mx8Q check failed
CUpgrader::doMetadataCheck no need check Mx8Q
CUpgrader::doMetadataCheck uparate file was craked NO Mx8Q!
CUpgrader::onUpgrade no need check CRC
```

V5.07 static detail (**STATIC**):

- CRC flag `this+0x4b8` and Mx8Q flag `this+0x4b9` are set to 0 in the `CUpgrader`
  constructor (`0x57acc` / `0x57ad0`);
- their setters (`0x51e80` / `0x51f34`) have no direct callers and are reachable only through
  vtable slots that nothing invokes; `VerifyMx8QSign` (`0x55350`) is never reached;
- the only real check is `tryDoDataCheck`, which re-validates the uImage header CRCs of the
  members. Re-wrapped payloads pass it.

Consequences:

1. an extra `Shell` upgrade command is executed as root (variant A);
2. a replaced `user-x.cramfs.img` (the squashfs mounted at `/usr`) is flashed (variant B).

The contents of all other members can stay byte-identical to the official package, which keeps
the camera functional (the ZIP container itself is rewritten).

## Variants

### Variant A: `Shell` command in `InstallDesc` (QEMU only)

```json
{"Command": "Shell", "Script": "echo ok > /mnt/mtd/marker; sync"}
```

- the script runs as root (`Uid 0`) during the update, **before** the `Burn` commands;
- the vendor limit is about 99 bytes per script;
- writes to `/mnt/mtd` (JFFS2) persist across the reboot, but `rcS` does not execute anything
  from `/mnt/mtd`. It does execute `/mnt/custom/extapp.sh` and `/usr/bin/quick_venc.sh`;
- useful as a proof marker or one-shot command, not for a persistent install.

**QEMU:** accepted on all five builds. V5.00, V5.01 and V5.07 return `Ret 515`; V5.02 and V5.04
report progress 100 and reboot without a `Ret 515` frame. The marker is present before and
after the automatic reboot.

### Variant B: custom `user` partition (hardware-validated)

The `user` partition (4544 KiB) is mounted at `/usr` (squashfs). The payload is the vendor
`/usr` tree of the **same firmware version** plus a root service started from
`/usr/bin/quick_venc.sh`, which `rcS` executes if present.

Lab payload (unauthenticated shell):

- `/usr/bin/shd`: about 1.6 KB static ARM binary. Listens on TCP 2323, accepts one client,
  `dup2`s the socket to stdin/stdout/stderr, execs `/bin/sh -i` with
  `PATH=/bin:/sbin:/usr/bin:/usr/sbin`;
- `/usr/bin/quick_venc.sh`:

```sh
#!/bin/sh
(while true; do /usr/bin/shd 2323; done) >/dev/null 2>&1 &
exit 0
```

  The loop gives sequential root sessions: a new listener after each disconnect, and after
  every reboot.

Production payload: dropbear SSH key-only root on TCP 2222, no 2323, hardening applied.
See [production.md](production.md).

## Per-version details

| | V5.01 (`V5.01.R02`) | V5.07 (`V5.07.X02`) |
|---|---|---|
| Base package | official V5.01 `_all.bin` | official V5.07 package ([firmware.md](firmware.md)) |
| `user` payload | vendor V5.01 `/usr` + root service | vendor V5.07 `/usr` + root service |
| Lab package (2323 shell) | `v501_persist2_user.bin` (not published) | `pkg_v507_usermod.bin` (not published) |
| Production package (SSH 2222) | `v501_prod_ssh.bin` (not published), see [production.md](production.md) | `v507_prod_ssh.bin` (not published), see [production.md](production.md) |
| Mx8Q / CRC enforcement | none | none (flags forced to 0, see above) |
| Variant A (`Shell`) | **QEMU**: `Ret 515`, marker persists | **QEMU**: runs as `Uid 0` before burns |
| Variant B (`user`) | **HW** (cam2): `Ret 515`, 3 sequential root sessions on 2323 (`Uid: 0 0 0 0`), no power cycle. **QEMU**: 4 sessions, 3 more after full restart | **QEMU**: `Ret 515`, `0.0.0.0:2323 LISTEN`, root. **HW**: production SSH variant on cam1, cam2, cam3 |
| Recovery package | official V5.01 package (`Ret 515`) | official V5.07 package (`Ret 515`), or downgrade to V5.01 |

V5.07 combinations tested in **QEMU**:

| Package | Result |
|---|---|
| Official V5.07 over a rooted V5.01 | V5.07, root lost |
| V5.07 without burning `user` | `Ret 515`; V5.07 kernel with V5.01 userspace, root preserved, but V5.01 modules/ISP/Wi-Fi do not match the V5.07 kernel. Not usable |
| V5.07 + rooted V5.07 `user` | `Ret 515`, V5.07, root. Recommended |
| Official V5.01 over V5.07 (downgrade) | `Ret 515`, V5.01; V5.01 root packages work afterwards. Downgrade itself also **HW** on cam2 |
| `v507_prod_ssh.bin` | `Ret 515` from V5.01-rooted and V5.07-stock images; SSH root, no 2323, persistent after reboot |

**HW** on V5.07: cam2 went V5.01 to V5.07 with a rooted V5.07 `user` package, verified over SSH,
rebooted, then downgraded to official V5.01. Real `rcS` timing, dropbear bind-mounts, flash
layout/length and `/mnt/mtd` config flush were then confirmed on all three cameras with the
production image.

## Building the package

Production build scripts: [production.md](production.md#build). The lab-package (2323) build
script is not published. The steps:

1. Start from the official `_all.bin` of the **exact** version running on the target.
2. Extract `user-x.cramfs.img`; strip the 64-byte uImage header to get the vendor squashfs;
   unpack it.
3. Add the root service (`shd` + `quick_venc.sh`, or the production SSH files). The `shd` binary
   is not published.
4. Rebuild the squashfs:

   ```sh
   mksquashfs <usr-tree> user.sqfs -comp xz -Xbcj arm -b 131072 -noappend -all-root
   ```

   V5.01 builds used `-b 131072`; the V5.07 builds use `-b 524288` (vendor value).

5. Pad to the original `user-x.cramfs.img` payload size (4,652,992 B = `0x46FFC0`; partition
   4544 KiB = `0x470000`). The V5.01 builder pads with zeros, the V5.07 builders with `0xFF`;
   both were accepted. The V5.07 production `/usr` squashfs is 4,456,448 B with voice
   prompts removed. Check the size before adding anything.
6. Re-wrap in a uImage header with a valid header CRC (checked by `tryDoDataCheck`).
7. Re-zip with the official `InstallDesc` and all other members' contents byte-identical
   ([`tools/xm_mkzip.py`](../tools/xm_mkzip.py) `--wrap` does steps 6 and 7).

Flash layout: [hardware.md](hardware.md).

## Procedure

Prerequisites: isolated LAN, DVRIP credentials (stock: `admin`, empty password), the official
package for recovery. A verified SPI dump is the only recovery from a bad write; only cam1 has
one ([recovery.md](recovery.md)).

1. Export the configuration (`ConfigExport`) and note the admin password.
2. Check the exact version: DVRIP `SystemInfo` or ONVIF `GetDeviceInformation`. Use a package
   built from that version.
3. Upload with DVRIP `OPSystemUpgrade` (32 KiB blocks; the web UI upgrade uses the same path),
   for example with [`tools/dvrip_upgrade.py`](../tools/dvrip_upgrade.py).
   Expected: `Ret 100` frames, progress `0..100`, then **`Ret 515`** (success), then automatic
   reboot.
4. Connect:

   ```sh
   # lab package
   nc <camera-ip> 2323
   export PATH=/bin:/sbin:/usr/bin:/usr/sbin
   id       # Uid 0
   mount    # /dev/mtdblock3 on /usr type squashfs

   # production package
   ssh -i <key> -p 2222 root@<camera-ip>
   ```

   The lab shell accepts one client at a time; the loop opens a new one after each disconnect.
5. Verify version, listening ports and persistence after a second reboot.
6. Recovery: re-upload the official package for the running version (restores the vendor
   `user`), or downgrade V5.07 to V5.01. Any return code other than `Ret 515` may mean a
   partial write: restore from SPI ([recovery.md](recovery.md)).

## Risks

- **Brick:** a wrong squashfs, wrong payload size, partial write or a package for another
  `Hardware`/`DevID` can leave the camera without `/usr` and without network.
- **Unauthenticated 2323:** the lab shell gives root to anyone who reaches it. Never
  port-forward it; use the production SSH image for anything long-lived.
- Packages are unsigned. A future vendor build that enforces CRC/`Mx8Q`/`doPartitionCheck`
  would reject them.
- The flaw is a firmware-integrity issue (unsigned update executed as root), not memory
  corruption. Exposure and mitigation: [security.md](security.md). Post-root hardening:
  [hardening.md](hardening.md).
