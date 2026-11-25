# Recovery

How to back up the SPI flash, restore a camera, return it to stock and regain root SSH access.
Applies to the `IPC-RM1-BLK535-2M6P` board (8 MiB SPI NOR). Flash layout: [hardware.md](hardware.md).

## SPI dump

There is no recovery button, no SD recovery mode and no usable UART on this board revision
([hardware.md](hardware.md)). No physical reset button is documented for this board either;
the factory resets recorded in these notes used ONVIF, the web UI or a root shell. A full SPI read is the only safety net.

| field | value |
|---|---|
| chip | Fudan FM25Q64A13, SOIC-8, 3.3 V |
| expected size | 8,388,608 B (8 MiB) |
| contents | U-Boot, kernel uImage, cramfs romfs, squashfs user, cramfs custom, JFFS2 mtd |

Procedure (CH341A, 3.3 V only). The cam1 dump was read with a CH341A and ASProgrammer, which
reported JEDEC ID `A1 40 17` (Fudan FM25Q64). The `flashrom` commands below are **UNTESTED**
on this chip: first run `flashrom -p ch341a_spi` alone and check that the chip is detected; if
it is not, or several definitions match, select one with `-c "<name>"` as listed by
`flashrom -L`.

1. Power the camera off and disconnect it.
2. Clip the SOIC-8 flash.
3. Read it twice and compare:

   ```sh
   flashrom -p ch341a_spi -r dump1.bin
   flashrom -p ch341a_spi -r dump2.bin
   cmp dump1.bin dump2.bin && sha256sum dump1.bin dump2.bin
   ```

4. Accept the dump only if both reads are byte-identical and 8,388,608 B.
5. Keep at least two copies off-device and record the SHA-256 privately.

Restore with the same setup, then read back and compare before powering on.

**Write only this unit's own dump.** A dump holds the unit identity, accounts and
calibration ([Identity block](#identity-block)); writing another camera's dump clones its
identity. For an unbrick without an own dump, use a factory recovery image instead.

```sh
flashrom -p ch341a_spi -w dump1.bin
flashrom -p ch341a_spi -r verify.bin && cmp dump1.bin verify.bin
```

Status: the `dump → official recovery overwrite → restore exact dump → boot` cycle passed in
**QEMU** (the dump boots as stock V5.01). A physical SPI write/restore is **UNTESTED** on hardware.

## Identity block

- The unit serial, software tag and account customization live in a **1 KiB block at boot
  partition offset `0x2FC00`** (**STATIC**, **QEMU**).
- The official packages and the factory recovery images leave this block erased.
- Restoring only mtd5 (config) or the U-Boot environment does not restore identity. Only a
  full-dump restore does.
- A dump is a unit backup (identity, accounts, config, calibration), not a generic image.
  **Never write one camera's dump to another camera.**

## Factory recovery images

Two 8 MiB images reconstructed only from the official V5.01 and V5.07 packages, for SPI unbrick of
an `XM535_X6E-WEQ_8M` board. They are not unit backups. The build tool is not published.

| image | size | SHA-256 |
|---|---|---|
| `v501_factory_recovery.bin` | 8,388,608 B | `051981be8cd67419fb6eb3c50bfd1f4bb72be3aa59960d663fe22dd3e9c8cee5` |
| `v507_factory_recovery.bin` | 8,388,608 B | `2c3b2e3acff5972be1158764801bd53af01934e9d5d620993b1e94b4402e62b4` |

What they contain (**STATIC**, **QEMU**):

- U-Boot, environment and kernel byte-identical to the official package; env CRC and kernel data
  CRC valid.
- Layout `mtdparts=xm_sfc:256K,1536K,1280K,4544K,256K,320K` (`boot/kernel/romfs/user/custom/mtd`).
- mtd5 (320 KiB JFFS2 config) filled with `0xFF`; the official package does not ship it.
- First boot formats mtd5 and creates the default `Config/Json`, `Account1/2`, `DeviceInfo`,
  `network`, `Log/ns`; this survives a power cycle.
- QEMU stock boot: V5.01 (U-Boot 2014.04, kernel `#27`, `V5.01.R02`) and V5.07 (U-Boot 2014.04,
  kernel `#84`, `V5.07.X02`); ports 80/554/8899/34567 up, HTTP 200, RTSP 401, ONVIF 200.

What they do NOT preserve:

- mtd5 config: accounts, passwords, Wi-Fi settings;
- FactoryCfg / `Camera.fac` calibration (e.g. DayNightColor);
- PTZ tables (`trackset`, `motor`, `PtzLocateSet`);
- serial number (empty in the package) and MAC (U-Boot env holds the package default
  `00:01:02:03:04:00`).

Procedure:

1. Read the original chip first (two identical reads, see [SPI dump](#spi-dump)).
2. Write the chosen recovery image.
3. Read back and compare the SHA-256 with the table above.
4. Power on; first boot formats mtd5 and recreates defaults.
5. Re-apply the production package ([production.md](production.md)) and the configuration
   ([hardening.md](hardening.md)).

Status: build, static verification and QEMU boot pass. Real SPI write: **UNTESTED**. Use only on
an otherwise unrecoverable board, after keeping its own dump.

## Return to stock

Three different operations:

| operation | firmware (`/usr`, U-Boot, kernel, romfs) | config (`/mnt/mtd`) | voice prompts | identity |
|---|---|---|---|---|
| A. Official package upload | restored to vendor | kept | restored | kept |
| B. Factory/config reset | untouched | reset to defaults | untouched | kept |
| C. SPI restore of the unit's own dump | exact dump contents | exact dump contents | as in dump | restored |

Voice prompts are `.pcm` files in `/usr/share/music`, in the read-only mtd3 `/usr` squashfs
(58 files in V5.01, 45 in V5.07). The production image removes them. A config reset
(mtd5 `Config`/`Flags` wipe, `OPDefaultConfig`, `RestoreFactoryConfig`, ONVIF factory default) does
not restore them; only rewriting mtd3 does (**QEMU**).

### A. Official package upload (removes root, keeps config)

1. Reach the camera with the admin password (DVRIP or vendor web UI).
2. Upload the official package with DVRIP `OPSystemUpgrade`. Package hashes and download source:
   [firmware.md](firmware.md). The extracted V5.01 `.bin` used here had SHA-256
   `34e75c27b49e3006af422a3396373510af9a4cbedb299d476d27d26087ff489c`.
3. Expect progress frames with `Ret 100`, then `Ret 515`, then an automatic reboot.
4. After reboot (**HW**):
   - SSH on TCP 2222 and any custom daemon are gone;
   - `/usr` is the vendor squashfs (voice prompts back);
   - `/mnt/mtd` is unchanged (admin password, users, cloud settings).

The official V5.07 package and a V5.07 → V5.01 downgrade both return `Ret 515` (downgrade: **HW**, on cam2). The unsigned-upgrade
path stays open after an official flash, so the camera can be re-rooted ([root.md](root.md)).

### B. Factory/config reset

Order for a full return to stock: run B first, while root SSH is still available, then A.
Without root, do A, then B through the web UI or ONVIF.

**Warning:** the commands below erase the admin password, all users and the whole hardening
(cloud cut, `OnvifPwdCheckout`, time settings). The camera comes back with an empty admin
password and the cloud enabled; keep it off untrusted networks until it is hardened again.

With root:

```sh
rm -rf /mnt/mtd/Config/* /mnt/mtd/Flags/*
rm -f /mnt/mtd/Log/9530Disable
sync
reboot
```

Without root: web UI "restore defaults", or ONVIF `SetSystemFactoryDefault` authenticated with the
current admin password.

The camera recreates the default config: empty admin password, cloud/PMS/NAT enabled,
unauthenticated ONVIF and snapshot. It also recreates the cloud service account.

Verification after B + A (full stock):

```text
admin + empty password                 -> login OK
ONVIF GetProfiles without auth         -> 200
/webcapture.jpg without auth           -> 200
RTSP user=admin_password=_             -> 200
PMS / NAT / OnlineUpgrade              -> enabled
TCP 2222 / 2323 / 12901 / 9530 / 23    -> closed
/usr/share/music                       -> present
```

The stock state is insecure by design ([security.md](security.md)). Keep it on an isolated network.

### C. SPI restore

Restores firmware, config, calibration and identity exactly. It is the only recovery when the
network or the boot is broken. Requires the unit's own dump ([SPI dump](#spi-dump)).

## SSH key loss

Production cameras expose root SSH key-only on TCP 2222. Authorized keys are built into the
production `user` image at `/usr/share/ssh/authorized_keys` and copied to
`/mnt/mtd/.ssh/authorized_keys` at boot. Losing the private key does not brick the camera:
the admin password and DVRIP remain usable.

### Admin password known

1. Generate a new key: `ssh-keygen -t ed25519 -f id_ed25519_camX`.
2. Put the new public key, plus a second backup public key, in the file that becomes
   `/usr/share/ssh/authorized_keys` (the build scripts copy a single `.pub` file, so it must
   contain both keys: [production.md](production.md#build), prerequisite 3), and rebuild the
   production package.
3. Upload it with DVRIP `OPSystemUpgrade` and the admin password. Expect `Ret 515` and a reboot.
4. Connect with `ssh -i id_ed25519_camX -p 2222 root@<camera-ip>` and check `id` shows uid 0.

The upgrade keeps `/mnt/mtd` (cloud cut, admin, service account, time settings).

### Admin password also lost

1. Factory/config reset through a remaining admin path: root SSH with another authorized key
   (section B commands), or ONVIF `SetSystemFactoryDefault` / web UI if any admin credential
   still works. No physical reset button is documented for this board. If no path remains, see
   [No network or admin access](#no-network-or-admin-access). The reset clears the mtd config,
   including the admin password and the cloud service account. The production `user` image
   with the old key stays.
2. DVRIP login with `admin` and an empty password works again.
3. Upload a production package with the new key(s), then re-apply [hardening.md](hardening.md).

### No network or admin access

SPI restore of the unit's own dump, then upload a package with a new key. Without a dump, only a
factory recovery image remains (identity lost).

### Prevention

- Keep the private key in at least two offline, encrypted locations.
- Build two public keys (primary + backup) into the image (see
  [production.md](production.md#build), prerequisite 3); test both before deploying.
- Keep the admin password in a password manager; it is the recovery credential.
- Keep the production package build pipeline and the hash of the deployed package.

## Recovery options per unit

| option | cam1 | cam2 | cam3 |
|---|---|---|---|
| own SPI dump | yes: one dump, 8 MiB, V5.01 stock, two identical reads | none | none |
| official package upload (A) | yes | yes (validated) | yes |
| factory/config reset (B) | yes | yes | yes |
| SPI restore with identity (C) | yes | no | no |
| factory recovery image | possible, identity lost | last resort, identity lost | last resort, identity lost |
| destructive tests (boot-media root, recovery write, destructive ConfigImport) | allowed | not allowed | not allowed |

No dump exists for cam2 and cam3; this risk is accepted. Do not clone the cam1 dump onto them.
