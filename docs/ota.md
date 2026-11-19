# OTA / cloud update: what the app offers, and why it is V5.07

## What was observed

On the stock `V5.01.R02` camera, the Android app (`com.xm.csee`, iCSee) shows a generic
dialog:

> Important ! N'exécutez pas d'autres actions pendant la mise à niveau
> Mettre à niveau ? [Annuler] [Mettre à niveau]

The dialog does **not** contain a version string. The app does not know or expose it; the
camera performs the OTA itself after confirmation.

The camera writes the detected OTA URL into **`/mnt/mtd/Log/ota_info.txt`** (readable with
root). On 2026-11-19 it contained:

```
https://upgrade.secu100.net:9083/download?devId=000A07F3XXXXX00003200000&ver=2025-09-06&file=General_IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.dss.OnvifS_V5.07.X02.20250906_all.bin
```

⇒ the offered version is **V5.07.X02, build 2025-09-06** — the same package already
available from the vendor portal and `OpenIPC/xmupdates` (SHA-256
`f9ed99f370953ef59e41a7e7656a2594854adf806b57029de3d883c7dd67a5e2`).

So there is **no newer build to capture** as of this writing; downloading it again is not
useful.

## How the OTA check works

- the camera has `NetWork.OnlineUpgrade` enabled (`upgrade.secu100.net:8083`) and a cloud
  connection (PMS/NAT/RPS);
- the app sends the update request through the cloud/P2P channel;
- the camera queries the OTA service, stores the URL in `/mnt/mtd/Log/ota_info.txt`, and
  the app only shows a confirmation dialog;
- on confirmation the camera downloads the `_all.bin` from
  `upgrade.secu100.net:9083/download?...` and runs the normal `CUpgrader` flow.

The phone-side traffic (`tcpdump`, app data) does not contain the firmware URL; the
download is done by the camera, not by the phone.

## Why you should NOT update if you want to keep root

The V5.04/V5.07 upgrade verifier is stricter (CRC/metadata checks;
`CUpgrader::doMetadataCheck`). The confirmed unsigned-upgrade root path
([upgrade-root.md](upgrade-root.md)) targets V5.01 and is **not expected to survive**
V5.07. In addition, a V5.07 update may make downgrade/recovery harder without an SPI dump.

Recommendation:

- **want to keep root / local-only production** → stay on V5.01, disable
  `OnlineUpgrade` (as in [production-firmware.md](production-firmware.md));
- **want vendor latest** → take a verified SPI dump first, then update; dump again and
  compare if you want to archive the new firmware.

## Capturing an OTA package safely (for a future/newer build)

1. Take a full 8 MiB SPI dump ×2 of the current state.
2. Optionally re-root the camera and read `/mnt/mtd/Log/ota_info.txt` to get the URL.
3. Trigger the update from the app, then dump the flash again.
4. Compare the partitions with the pre-update dump; keep both.
5. Restore the pre-update dump if needed (SPI), or re-flash the official package.

`ota_info.txt` is only written by the camera, so a temporary root (persistent package) is
the easiest way to read it without updating.

## Related

- [firmware.md](firmware.md) — archive of official builds and hashes
- [production-firmware.md](production-firmware.md) — V5.01 production image with cloud off
- [return-to-stock.md](return-to-stock.md) — how to undo the modifications
