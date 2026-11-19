# Factory / brick-recovery images (8 MiB SPI)

These are **reconstructed factory images**, built only from the official V5.01 and V5.07
packages. They are meant for **SPI unbrick** of an `XM535_X6E-WEQ_8M` board (8 MiB Fudan
FM25Q64), **not** as a backup of a specific camera.

| image | size | SHA-256 |
|---|---|---|
| `v501_factory_recovery.bin` | 8,388,608 B | `051981be8cd67419fb6eb3c50bfd1f4bb72be3aa59960d663fe22dd3e9c8cee5` |
| `v507_factory_recovery.bin` | 8,388,608 B | `2c3b2e3acff5972be1158764801bd53af01934e9d5d620993b1e94b4402e62b4` |

Local artifacts: `stack/analysis/access/recovery-images/` (images, `README.md`,
`REPORT.md`, build/verify scripts, `SHA256SUMS.txt`, QEMU logs).

## What is in the image

- U-Boot, environment and kernel are **byte-identical to the official package**; env CRC and
  kernel data CRC are valid.
- layout exactly `mtdparts=xm_sfc:256K,1536K,1280K,4544K,256K,320K`
  (`boot/kernel/romfs/user/custom/mtd`).
- `mtd5` (the 320 KiB config/JFFS2 partition) is filled with **0xFF** (erased), as the official
  flash does not ship it; the camera formats it on first boot.
- QEMU stock boot verified: V5.01 U-Boot 2014.04 / kernel #27 / `V5.01.R02…`; V5.07 U-Boot
  2014.04 / kernel #84 / `V5.07.X02…`; ports 80/554/8899/34567, HTTP 200, RTSP 401/H264DVR,
  ONVIF 200.
- first boot creates a valid JFFS2 on mtd5 and the default `Config/Json`, `Account1/2`,
  `DeviceInfo`, `network`, `Log/ns`; it survives a power cycle.

## What is NOT preserved — read this before using it as a "backup"

- **mtd5 config**, accounts/passwords, Wi-Fi settings;
- **FactoryCfg / Camera.fac calibration** (e.g. DayNightColor);
- **PTZ tables** (`trackset`, `motor`, `PtzLocateSet`);
- **serial number** (empty in the package) and **MAC** (U-Boot env has the package default
  `00:01:02:03:04:00`; the real unit had `3ee55700339720f38ww9` / `E8:9C:25:48:1A:A2`).

A real chip dump is the only way to preserve a unit's identity and calibration. Keep the
original dump in two copies before writing anything.

## SPI procedure (CH341A, 3.3 V)

1. Power off, clip the FM25Q64 SOIC-8 (3.3 V only).
2. **Read the original chip first**, twice, and compare hashes; keep two copies off-device.
3. Write the chosen recovery image.
4. Read back and verify SHA-256 against the table above.
5. Power on; first boot formats mtd5 and recreates defaults.
6. Re-apply the desired production/hardening package and configuration.

## Voice prompts (`/usr/share/music`)

The prompts live in the **read-only mtd3 `/usr` squashfs** (58 `.pcm` in V5.01, 45 in V5.07).
An official flash rewrites mtd3 and restores them; a **config reset** (mtd5 `Config`/`Flags`
wipe, `OPDefaultConfig`, `RestoreFactoryConfig`, ONVIF factory-default) recreates defaults but
**does not restore the music**. Verified in QEMU: a musicless user image stays musicless after
a config reset; writing the official user payload back to mtd3 restores the files.

## Status

- Build + static verification + QEMU boot: **PASS**.
- Real SPI write/restore: **not yet tested** (clip/dump pending); use only on a sacrificial
  board or after keeping the original dump.
- Not copied into `stack/xm_fw/upg/` because that directory is for DVRIP ZIP packages, not raw
  SPI images.
