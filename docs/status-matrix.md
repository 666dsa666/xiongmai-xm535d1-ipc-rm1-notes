# Status matrix — what is validated, what is not, what remains

Last updated: 2026-11-19. Scope: XM535D1 / X6E-WEQ, `IPC-RM1-BLK535-2M6P V1.03`,
8 MiB FM25Q64.

Legend: **HW** = validated on a physical camera; **QEMU** = validated on the exact
firmware image under `qemu-bench`; **NO** = tested and failed/not applicable;
**PENDING** = not finished / not tested.

## Cameras

| Camera | Current state | Notes |
|---|---|---|
| `.153` (camera 1) | **stock V5.01**, cloud/PMS as vendor | reference; never flashed; 12901 open on stock config |
| `.161` (camera 2) | **stock V5.01 with hardened config**, no SSH/root (2222/2323 closed) | used for every hardware test; was V5.07 production during the round-trip, then downgraded to V5.01 official |
| camera 3 | **new in box**, not connected | intended as SPI-dump/recovery reference and optional boot-media test |

- SPI clip: **not available yet** (expected in a few days).
- No verified SPI dump of any camera yet. Camera 2 has an **old 8 MiB dump of a custom
  state** (pre-factory-reset), useful as a fallback but not a stock reference.
- `.161` current config: admin password set, only `admin`, PMS/NAT/OnlineUpgrade/NTP off,
  ONVIF/RTSP/snapshot auth on, no SSH/root.

## Firmware

| Version | Package / status | QEMU | HW | Notes |
|---|---|---|---|---|
| V5.00.R02 (2024-04-18) | archived | booted | NO | no access advantage |
| V5.01.R02 (2024-09-14) | **exact unit build** | booted | **YES** | root via unsigned upgrade; production SSH validated on HW |
| V5.02.R02 | archived | booted | NO | intermediate — not pursued |
| V5.04.R02 | archived | booted | NO | intermediate — not pursued |
| V5.07.X02 (2025-09-06) | latest official | booted | **YES** | unsigned upgrade accepted; production SSH validated on HW; downgrade to V5.01 validated on HW |

- `debug` binary (12901) is byte-identical V5.00–V5.07.
- Voice prompts are in the `user` (`/usr/share/music`) partition; removed in production
  images; restored by official firmware flash, **not** by a config reset.

## Root / access methods

| Method | QEMU | HW | Verdict |
|---|---|---|---|
| **Unsigned upgrade, V5.01** — `Shell` command / custom `user` | YES | **YES** | root command as root; persistent 2323; production SSH 2222 |
| **Unsigned upgrade, V5.07** — no CRC/Mx8Q enforcement | YES | **YES** | V5.07 production SSH 2222 validated on HW; `Ret 515` |
| Upgrade **without burning `user`** (V5.07 kernel + V5.01 rooted `/usr`) | YES | NO | **abandoned** — root preserved but V5.01 modules/ISP mismatch the V5.07 kernel; not needed since V5.01 and V5.07 both have direct root entry points |
| **Downgrade V5.07 → V5.01** official | YES | **YES** | `Ret 515`, V5.01 restored; config preserved |
| **Boot-media root V5.07** — ConfigImport writes mtd5 cramfs `/init` + mtd0 U-Boot/env | YES | **NO** | network-only persistent root on 2323; destructive to mtd0/mtd5; QEMU V5.07 only — the same `ConfigImport`/layout exists on V5.00–V5.04/V5.01, so it is *likely* portable, but untested |
| `ConfigImport` msg 1540 traversal — root file/block-device write | YES | NO | root write, config/boot tampering, brick risk |
| HTTP legacy bridge admin bypass / ConfigExport | YES | **YES** (on stock) | full admin + credential/PSK leak when password empty |
| 12901 auth downgrade (VSC vs RSA) | YES | NO (binary identical) | no vendor key needed to drive the service; no root shell by itself |
| 12901 pre-auth heap overflow (225 B) | YES | NO | **DoS confirmed**; control-flow influence but no reliable RCE |
| 12901 `popen("timetest")` fixed command | YES | NO | PATH hijack **fails**: RO PATH + busybox applet already running root on TCP 50119; ZIP strips exec bit |
| 12901 follow-up: busybox `timetest` on 50119 | NO | NO | new root-service lead, not yet audited |
| XMTelnet / 9530 secret knock | NO | NO | absent telnetd/9530; paid exploit + offline licence; not applicable |
| UART console / SPI flash | NO | NO | physical fallback; UART pads not identified; clip pending |
| Vendor RSA private key | NO | NO | not present in firmware; not needed for VSC path anyway |

## Production / hardening

| Item | QEMU | HW | Notes |
|---|---|---|---|
| **V5.01 production SSH** (`v501_prod_ssh.bin`) | YES | **YES** | SSH key-only 2222, no 2323; cloud off; HW-validated, then camera later reset/downgraded |
| **V5.07 production SSH** (`v507_prod_ssh.bin`) | YES | **YES** | V5.07 + SSH 2222; HW round-trip validated; package ready |
| Admin password change / user cleanup | YES | **YES** | admin only; strong password |
| ONVIF/RTSP/snapshot auth | YES | **YES** | ONVIF 401, RTSP blank 401 / new 200, snapshot 401 |
| PMS/NAT/OnlineUpgrade/NTP off, `DisableXmServerConn`, `OnvifPwdCheckout` | YES | **YES** | survives reboot and upgrade/downgrade |
| `9530Disable` marker | YES | **YES** | 12901/9530 closed |
| Windows SSH key ACL | — | **YES** | needed `icacls /inheritance:r`; client-side only |
| Factory return / downgrade | YES | **YES** | official V5.01/V5.07 packages `Ret 515`; config preserved |

## OTA / cloud

| Item | Result |
|---|---|
| Android app update prompt | generic dialog, **no version shown**; camera stores URL in `/mnt/mtd/Log/ota_info.txt` |
| Offered version | **V5.07.X02** (2025-09-06) — already owned (`f9ed99f3…`) |
| OTA endpoint | `https://upgrade.secu100.net:9083/download?...` |
| V5.01 → V5.07 root | possible with the unsigned package; **HW-validated** |
| Latest V5.07 root | possible; production SSH validated; downgrade validated |

## Remaining decisions / tasks

1. **Final state of `.161`**: choose V5.07 production SSH (recommended), V5.01 production
   SSH, or keep stock V5.01 hardened.
2. **When the clip arrives**: dump camera 3 (new) ×2, verify; ideally dump `.161` and
   `.153` too; store two copies. Optionally build/verify a factory recovery image from the
   official packages (not a substitute for a target dump).
3. **Optional**: hardware-validate boot-media root on camera 3 **after** a dump; it is
   destructive and QEMU-only today.
4. **Optional**: finish the new lead on the **busybox `timetest` root service on TCP 50119**
   (QEMU only; no documentation yet); 12901 itself is settled — no root primitive.
5. **`.153`**: keep stock or choose a later production/hardening step.
6. Rotate the Wi-Fi PSK that was exposed by `ConfigExport` before hardening.
7. Re-apply the chosen production image to `.161` and update docs/backup with the final
   state.

## Artifacts

- Packages: `stack/xm_fw/upg/v501_prod_ssh.bin`, `v507_prod_ssh.bin`,
  `v501_official.bin`, `v501_persist2_user.bin`, V5.07 rooted variants.
- Keys/passwords: `stack/analysis/access/cam2-production/`,
  `stack/analysis/access/v507-production/` (sensitive; not in git).
- Backup: `stack/backups/2026-11-19/` (packages, credentials, reports, flash dump,
  docs snapshot, SHA256SUMS).
- Docs: <https://github.com/666dsa666/xiongmai-xm535d1-ipc-rm1-notes>
  (upgrade-root, upgrade-root-v507, production-firmware, production-firmware-v507,
  boot-media-root-v507, debug-12901, xmtelnet, ota, return-to-stock).
