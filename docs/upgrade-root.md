# Root via the unsigned upgrade path (XM535D1, V5.01)

> **Status: confirmed on real hardware (2026-11-19).**
> A spare `IPC-RM1-BLK535-2M6P` camera running stock
> `V5.01.R02.000A07F3.10010.346732.0000000` was rooted by uploading a **modified,
> unsigned** V5.01 update package. After the automatic reboot, the camera exposes a
> **persistent root shell over TCP 2323**. The reference camera (`192.168.0.153`) was
> **not** touched during this work.

This page documents the vulnerability, the two payload variants, the tested
procedure, and the risks. It is a security write-up for the owner of the hardware, not
a generic "one-click" tool: **a verified 8 MiB SPI dump is mandatory before flashing**.

## TL;DR

| Variant | What it changes | Result | Risk |
|---|---|---|---|
| **A — upgraded `InstallDesc`** | adds a `{"Command":"Shell","Script":"..."}` entry to the official package's `InstallDesc` | the script runs **as root during the update** (one shot). Marker survives in `/mnt/mtd` | low–medium |
| **B — custom `user` partition** | official V5.01 package, only `user-x.cramfs.img` replaced by a vendor `/usr` squashfs + a small root-shell daemon | after the automatic reboot, **persistent root shell on 2323**, sequential sessions auto-respawn | medium |

Both were validated end-to-end in QEMU and variant **B** was then validated on a physical
camera.

## Why the camera accepts it

The XM535D1 update package is a container with:

- `InstallDesc` — JSON metadata: `Hardware`, `DevID`, `CompatibleVersion`, `CRC`,
  `Mx8Q` signature, and an `UpgradeCommand` list (`Burn <component>` entries);
- component images: `u-boot.bin.img`, `u-boot.env.img`, `uImage.img`,
  `romfs-x.cramfs.img`, `user-x.cramfs.img`, `custom-x.cramfs.img`.

`CUpgrader` in `Sofia` checks the package structure, `CRC` and `InstallDesc`, but the
`Mx8Q` signature check is **only performed when the "FirmwareMx8Q check" feature is
enabled** (strings: `VerifyMx8QSign, no pub, skip check Mx8Q`,
`CUpgrader::doMetadataCheck no need check Mx8Q`). On the tested V5.01 builds this check
is not enforced, and the component payloads are not verified against the official
package. Consequences:

1. a package with an extra `Shell` upgrade command is accepted (`Ret 515`) and the
   command is executed as root;
2. a package whose `user-x.cramfs.img` is replaced by an arbitrary squashfs is accepted
   and flashed; the vendor `user` partition is what `/usr` is mounted from at boot.

The rest of the package can stay byte-identical to the official V5.01 package
(U-Boot, env, kernel, romfs, `custom`, `InstallDesc`), which keeps the camera
functional and minimises the risk.

## Variant A — root command in `InstallDesc` (one shot)

`InstallDesc` normally contains only `Burn` commands. Adding an `UpgradeCommand` of
type `Shell` makes `CUpgrader` run the `Script` string through the system shell as
root, during the update, before the reboot:

```json
{"Command": "Shell", "Script": "echo PWNED > /mnt/mtd/PWNED; sync"}
```

The official package is otherwise unchanged. The marker in `/mnt/mtd` (JFFS2) survives
the reboot and proves the command ran as root. The script is short — the vendor
implementation limits the command to roughly 99 bytes, so this variant is best for a
proof/marker or a one-shot network command, not for installing a persistent service.

**QEMU evidence:** V5.00 and V5.01 both returned `Ret 515`; `/mnt/mtd/PWNED` was read
before and after the automatic reboot.

## Variant B — custom `user` partition (persistent root)

The `user` partition is mounted at `/usr` (squashfs). Replace the payload with the
vendor `/usr` tree plus:

- `/usr/bin/shd` — a ~1.6 KB static ARM binary. It opens TCP **2323**, accepts one
  client, dup2's the socket to stdin/stdout/stderr and execs `/bin/sh -i` with
  `PATH=/bin:/sbin:/usr/bin:/usr/sbin`.
- `/usr/bin/quick_venc.sh` — executed by `rcS` if present. It starts a **respawn loop**:

```sh
#!/bin/sh
(while true; do /usr/bin/shd 2323; done) >/dev/null 2>&1 &
exit 0
```

This gives persistent **sequential** root sessions: after each disconnect, the loop
starts a fresh listener. No power-cycle, no second upgrade, and it survives reboots.

The squashfs is rebuilt from the vendor V5.01 `/usr` tree
(`mksquashfs ... -comp xz -Xbcj arm -b 131072 -noappend -all-root`), padded to the
original `user-x.cramfs.img` payload size, then wrapped into the official package with
`agent_camfw2_mkzip.py`. In the tested package, every component except `user-x` was
byte-identical to the official V5.01 package.

**Package used for the hardware test:**

```
v501_persist2_user.bin
sha256 ca387aca5857ba105434204e343314da242756765edec4b1192a88d8a472cb82
```

The package is built locally in `stack/xm_fw/upg/`; it is not published as a binary
here (build it from your own official V5.01 `_all.bin` and verify the hashes).

## Evidence

### QEMU (exact V5.01 image)

- upgrade through DVRIP `OPSystemUpgrade` → `Ret 515`, automatic reboot;
- after reboot: **4 sequential sessions** on 2323, each `Uid: 0 0 0 0`;
- full restart of the QEMU image → **3 more root sessions**: boot persistence confirmed;
- `/usr` mounted from the custom squashfs; `/usr/bin/shd` present.

### Real camera (spare unit, V5.01.R02)

- package uploaded through DVRIP (`admin` / empty) → **`Ret 515`**, automatic reboot;
- **3 sequential root sessions** on 2323, each `Uid: 0 0 0 0`, no power-cycle;
- 8 MiB flash dump of the spare was taken **before** the persistent variant was flashed
  (partitions + full-flash SHA-256 recorded in the analysis workspace).

## Procedure (spare camera only)

> **Do not do this on your reference camera.** Use a spare unit, an isolated LAN, and
> have a recovery path ready.

0. **Full SPI dump first** — CH341A clip on the FM25Q64, read the whole 8 MiB **twice**,
   compare SHA-256, keep two copies. Without this, a failed write means a brick.
   Also export the camera configuration (`ConfigExport`) and keep it.
1. **Check the version** (`DVRIP SystemInfo` / ONVIF `GetDeviceInformation`). The package
   above is for `V5.01.R02`; if the spare is V5.04/V5.07, rebuild the package from
   *its* official `_all.bin` and test in QEMU first (the verifier and metadata checks
   differ on newer builds).
2. **Upload** the package with the vendor DVRIP `OPSystemUpgrade` flow (web UI upgrade
   uses the same path). The camera returns progress frames up to `Ret 100`, then
   **`Ret 515` = success**, then reboots automatically.
3. **Connect** after the reboot:

```sh
nc <ip> 2323
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
id          # Uid: 0 0 0 0
mount       # /dev/mtdblock3 on /usr type squashfs
```

   One shell at a time; the respawn loop opens a new one after each disconnect.
4. **Recovery:** re-upload the official V5.01 package (restores the vendor `user`
   partition), or restore the verified SPI dump. A package that returns something other
   than `Ret 515` may still have written part of the flash — restore the dump.

## Risks and limitations

- **Brick risk**: the `user` partition is replaced. A wrong/bad squashfs, a partial
  flash write, or a mismatched package can leave the camera without `/usr` and without
  network. The SPI dump is the only reliable recovery.
- **V5.04/V5.07 differ**: newer builds add CRC/metadata checks; the V5.01 package is not
  guaranteed to work. Rebuild and QEMU-test for the target build.
- **The root shell is unauthenticated.** Port 2323 gives root to anyone who can reach
  it. Keep the camera on an isolated VLAN/SSID, never port-forward 2323, and firewall it.
- `shd` is a minimal static binary; it does not provide encryption or authentication.
- This is a **firmware-integrity vulnerability** (unsigned update accepted and executed
  as root). It is not a memory-corruption exploit; the camera treats the modified
  package as a normal upgrade.
- The vendor debug service on 12901 remains RSA-protected and separate.

## Hardening after rooting

A production-oriented variant of this work replaces the unauthenticated 2323 shell with
**SSH key-only root on 2222**, applies the hardening below, and was validated on real
hardware. Build, deployment and test matrix:
[production-firmware.md](production-firmware.md).

Once you have root:

- change the admin password and remove/audit the hidden `twhn`/extra accounts;
- disable PMS/NAT/online upgrade (and block WAN at the router) — see
  [cloud-cut.md](cloud-cut.md);
- create `/mnt/mtd/Log/9530Disable` to keep the vendor debug service disabled at boot;
- decide whether to keep port 2323 (firewall it to a management host) or restore the
  official `user` partition once you no longer need the shell;
- keep the verified SPI dump and the official V5.01 package for recovery.

## Related pages

- [root.md](root.md) — path matrix and what failed before this was found
- [telnet.md](telnet.md) — 12901 / `EnableKey` / `GetSaftyCode` reverse
- [firmware.md](firmware.md) — V5.01/V5.00/V5.02/V5.04/V5.07 packages and hashes
- [backup.md](backup.md) — SPI dump procedure
- [security.md](security.md) — default credentials and exposure
