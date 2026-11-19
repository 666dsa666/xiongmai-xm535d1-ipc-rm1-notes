# Root on the latest V5.07 — unsigned upgrade still works

> **Status: validated in QEMU only (2026-11-19).** No physical V5.07 camera was
> available yet. The first camera (`.153`, V5.01) was not touched; the V5.01
> production camera was not touched either. Take a verified SPI dump before any real test.

## The finding

The V5.07 `CUpgrader` **does not enforce CRCs or the `Mx8Q` signature**:

- console/log evidence on V5.07:
  `CUpgrader::onUpgrade no need check CRC` and
  `CUpgrader::doMetadataCheck no need check Mx8Q`;
- statically, the CRC flag (`this+0x4b8`) and Mx8Q flag (`this+0x4b9`) are set to 0 in
  the CUpgrader constructor (`0x57acc/0x57ad0`), and their setters
  (`0x51e80/0x51f34`) have **no callers**; `VerifyMx8QSign` (`0x55350`) is never reached;
- the only real check is `tryDoDataCheck`, which re-validates the uImage header CRCs of
  the members — payloads are re-wrapped so this passes.

A modified V5.07 package (official V5.07 metadata, replaced `user-x.cramfs.img`) is
therefore accepted: **`Ret 515`**, reboot, `flash_changed=True`.

## Root variants tested in QEMU

| Variant | What it does | Result |
|---|---|---|
| Official V5.07 over V5.01-rooted | normal upgrade | V5.07, **root lost** |
| V5.07 **without burning `user`** | keeps V5.01 `/usr` | `Ret 515`, kernel V5.07, V5.01 userspace + dropbear/root preserved — but V5.01 modules/ISP/wifi do not match the V5.07 kernel |
| **V5.07 + rooted V5.07 `user`** | full V5.07 `/usr` with root daemon | `Ret 515`, **V5.07 + root shell (2323, `SHD_ROOT_OK`)** ✅ |
| `Shell` command in V5.07 `InstallDesc` | runs a command as root during upgrade (`≤99` bytes) | executed `Uid 0` **before** the burns; `/mnt/mtd` writes persist. `rcS` does not execute from `/mnt/mtd`, but it does execute `/mnt/custom/extapp.sh` and `/usr/bin/quick_venc.sh` |
| Downgrade V5.07 → V5.01 | official V5.01 package | `Ret 515`, V5.01; then V5.01 root/dropbear packages work |

**Best method:** one upgrade, `pkg_v507_usermod.bin` — official V5.07 metadata plus a
rooted V5.07 `/usr` (`shd` on 2323 + `quick_venc.sh` started by `rcS`). QEMU: `Ret 515`,
reboot, version V5.07, `0.0.0.0:2323 LISTEN`, root shell.

A production SSH variant was also built (`pkg_v507_prod_ssh.bin`, see
[production-firmware-v507.md](production-firmware-v507.md)): V5.07 official metadata,
V5.07 `/usr` with dropbear key-only on 2222; QEMU: `Ret 515` from both V5.01-rooted and
V5.07-stock images, SSH root, no 2323, persistent after reboot, hardening verified.

## Procedure for a real V5.07 camera

> Until an SPI dump exists, do not do this on a camera you cannot afford to lose.
> Prefer a spare/throwaway unit, isolated LAN.

1. **Verified SPI dump ×2** (8 MiB, CH341A), compare hashes, keep two copies.
2. Identify the firmware version (DVRIP `SystemInfo` / web). This package targets
   **V5.07.X02**; other builds may need their own package.
3. Export the config; note the admin password.
4. Upload the package over DVRIP `OPSystemUpgrade` (32 KiB blocks). Expected:
   `Ret 100` frames → progress `0..100` → **`Ret 515`** → reboot.
5. After reboot, connect to the root path:
   - lab package: `nc <ip> 2323` (one-shot/respawn shell);
   - production package: `ssh -i <key> -p 2222 root@<ip>`.
6. Verify version, ports, persistence after a second reboot.
7. Recovery: re-upload the official V5.07 package (`Ret 515`), or downgrade to V5.01 and
   use the V5.01 root path, or restore the SPI dump.

## Risks / limits

- **QEMU-only validation** for V5.07: real `rcS` timing, dropbear bind-mounts, flash
  layout/length and `/mnt/mtd` config flush still need hardware confirmation.
- A package with the wrong `user` payload size can brick; keep the SPI dump.
- The `user` partition is 4,544 KiB; the production `/usr` is 4,456,448 B (voice prompts
  removed). Do not add more without checking the payload limit.
- Homemade packages are unsigned; any future vendor firmware that restores
  CRC/Mx8Q/`doPartitionCheck` enforcement will reject them.
- The `Shell` variant is limited to ~99 bytes and runs before the burns; it is useful for
  a marker/persistence test, not for a full root install.
- XMTelnet is **not** applicable (no telnetd/9530 on this model) — see
  [xmtelnet.md](xmtelnet.md).

## Related

- [production-firmware-v507.md](production-firmware-v507.md) — SSH production variant
- [upgrade-root.md](upgrade-root.md) — V5.01 unsigned-upgrade root
- [ota.md](ota.md) — V5.07.X02 is the version offered by the cloud app
- [return-to-stock.md](return-to-stock.md) — official flash/downgrade recovery
