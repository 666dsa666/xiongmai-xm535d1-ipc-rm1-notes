# Return to stock / factory state

This page covers undoing the modifications on a `XM535D1` camera.

## Two different things

| Action | Firmware (`/usr`, U-Boot, kernel, romfs) | Config (`/mnt/mtd`) | Voice prompts |
|---|---|---|---|
| Flash official `v501_official.bin` | **restored to vendor** | **kept** | **restored** |
| Reset factory settings (web/ONVIF/root wipe) | untouched | **reset to defaults** | untouched |

The voice prompts are files in `/usr/share/music`, i.e. in the **firmware** partition.
They are removed in the production image; flashing the official package restores them.
A config reset alone does **not** restore them.

## A. Restore official firmware (removes root/SSH, keeps config)

1. Make sure you can reach the camera (web/DVRIP admin password).
2. Upload the official V5.01 package (`v501_official.bin`, SHA-256
   `34e75c27b49e3006af422a3396373510af9a4cbedb299d476d27d26087ff489c`) through the
   vendor web UI or DVRIP `OPSystemUpgrade`.
3. Expect progress frames up to `Ret 100`, then **`Ret 515`**, then an automatic reboot.
4. After reboot:
   - SSH/2222 and any custom `shd` are gone;
   - `/usr` is the vendor squashfs (voice prompts back);
   - `/mnt/mtd` config is unchanged (admin password, cloud settings, users persist).
5. If the camera cannot be reached, see the flash-dump recovery in
   [backup.md](backup.md) (once an SPI dump exists).

## B. Full factory reset (config defaults)

Do this **before** flashing the official package if you still have root, or **after** if
you know the admin password.

### With root (before losing SSH)

```sh
rm -rf /mnt/mtd/Config/* /mnt/mtd/Flags/*
rm -f /mnt/mtd/Log/9530Disable
sync
reboot
```

The camera recreates the default config on boot (admin password empty, cloud/PMS/NAT
enabled, ONVIF/snapshot unauthenticated). The custom firmware is still active at this
stage — it is only the config that is reset.

### Without root (after official firmware)

- use the web UI **factory reset / restore defaults**; or
- ONVIF `SetSystemFactoryDefault` (authenticated with the current admin password).

Then reboot and verify.

## Verification after a full stock return

```
admin login: admin + empty password            -> OK
ONVIF GetProfiles without auth                 -> 200
/webcapture.jpg without auth                   -> 200
RTSP user=admin_password=_                     -> 200
PMS / NAT / OnlineUpgrade                      -> enabled
SSH 2222 / 2323 / 12901 / 9530 / 23            -> closed
voice prompts (/usr/share/music)               -> present
```

> The factory state is **insecure by design**. Only leave it on an isolated network, and
> re-apply [hardening.md](hardening.md) / [production-firmware.md](production-firmware.md)
> when appropriate.

## C. SPI restore (best recovery)

If you have a verified 8 MiB dump, restoring it with the CH341A clip returns the exact
flash contents (firmware + config + calibration). This is the only recovery if the
network/boot is broken or SSH/root access is lost. See [backup.md](backup.md).

## Related

- [ota.md](ota.md) — why updating to V5.07 closes the unsigned-upgrade root path
- [production-firmware.md](production-firmware.md) — what the production image changes
- [upgrade-root.md](upgrade-root.md) — the unsigned-upgrade root method
