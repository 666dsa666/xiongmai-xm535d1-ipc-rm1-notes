# Status matrix — verified / to verify / abandoned

Last updated: 2026-11-19. XM535D1 / X6E-WEQ, `IPC-RM1-BLK535-2M6P V1.03`, 8 MiB FM25Q64.

Legend: **HW** = validated on physical hardware; **QEMU** = validated on the exact
firmware image under `qemu-bench`; **NO** = failed / not applicable.

## Current camera state

| Camera | State | Role |
|---|---|---|
| `.153` | stock V5.01, cloud/PMS as vendor | reference; never flashed |
| `.161` | stock V5.01 **with hardened config**, no SSH/root (2222/2323 closed) | hardware test unit |
| camera 3 | new in box, not connected | SPI dump/recovery reference |

- SPI clip: **not available yet**; no verified SPI dump of any camera.
- `.161` was taken through V5.01 stock → V5.07 production SSH → V5.01 official downgrade;
  it is currently stock V5.01 with hardened config.

---

## ✅ Verified — real hardware

| Item | Evidence / detail |
|---|---|
| **V5.01 unsigned-upgrade root** | custom `user`/`Shell` package accepted (`Ret 515`); root shell; production SSH 2222; hardware-validated on `.161` |
| **V5.07 unsigned-upgrade root** | V5.07 package accepted (`Ret 515`); V5.07.X02; production SSH 2222; hardware-validated |
| **V5.01 → V5.07 → V5.01 round-trip** | `Ret 515` both directions; version changes confirmed; config preserved |
| **Production SSH (V5.01 and V5.07)** | key-only root on 2222, no 2323/12901/9530; persists after reboot |
| **Hardening** | admin only/strong password; PMS/NAT/OnlineUpgrade/NTP off; `DisableXmServerConn`; `OnvifPwdCheckout`; `9530Disable` |
| **Auth behaviour after hardening** | RTSP blank 401 / new 200; ONVIF media+device 401; snapshot 401; HTTP bridge wrong password 203 |
| **Official firmware restore / downgrade** | official V5.01/V5.07 package `Ret 515`; SSH/root removed; config kept |
| **Config preservation across upgrade/downgrade/reboot** | hardened fields re-read after each reboot |
| **HTTP bridge + ConfigExport on stock** | admin+empty full admin; config ZIP with accounts/PSK (observed before hardening) |
| **No telnetd / no 9530 subsystem** | `find / -iname '*telnet*'` empty, no listener; checked on real rooted V5.01 |
| **OTA version/URL** | camera stored `V5.07.X02` URL in `/mnt/mtd/Log/ota_info.txt`; app offered same build |
| **Windows SSH client key ACL** | `icacls /inheritance:r` + owner grant required; client-side only |

## ✅ Verified — QEMU only

| Item | Result |
|---|---|
| V5.00/V5.02/V5.04 boots and baseline | booted; no hardware test; intermediate versions abandoned as root targets |
| **Boot-media root on stock V5.07** | ConfigImport → `mtd5` cramfs `/init` + `mtd0` U-Boot/env; persistent root console 2323; arbitrary ARM exec; **no hardware test** |
| **ConfigImport msg 1540 traversal** | root file/block-device write; `mtd0`/`mtd1`/`mtd5` writable; brick risk |
| **V5.07 no CRC/Mx8Q enforcement** | flags 0, setters uncalled, `VerifyMx8QSign` unreachable; `Ret 515` with modified `user` |
| **Upgrade without burning `user`** | root preserved, but V5.01 userspace with V5.07 kernel → modules/ISP mismatch; **abandoned** |
| **12901 auth downgrade (VSC vs RSA)** | short-field VSC path, safety code offline-computable; full 0→4 walk; no vendor key |
| **12901 heap overflow** | clean pre-auth DoS (zero-N MPI SIGSEGV); long-E heap corruption with PC/LR influence; no reliable RCE |
| **12901 PATH hijack** | failed: RO PATH, `timetest` is a busybox applet already running root on **50119**, ZIP drops exec bit |
| **`core_pattern`/`hotplug` helper** | writable but no core dumps / no exec bit → fails |
| **XMTelnet model** | paid exploit + offline licence; 9530 subsystem absent → not applicable |
| **Signed-upgrade assumptions** | V5.01/V5.07 accept modified packages despite `Mx8Q`; documented |

---

## 🟡 To verify / pending

| Item | Why / next step |
|---|---|
| **SPI dump ×2 of camera 3** | clip pending; verify hashes, store two copies |
| **SPI dump of `.161` / `.153`** | target-specific backup; preferable before any future flash |
| **SPI restore test on a sacrificial camera** | validate the recovery procedure, not just the theory |
| **Boot-media root on real hardware** | QEMU-proven only; destructive to `mtd0`/`mtd5`; needs dump/recovery |
| **Boot-media root portability to V5.00–V5.04/V5.01** | same ConfigImport/layout; untested |
| **`timetest` busybox service on TCP 50119** | new root-service lead; no protocol audit yet |
| **Factory recovery image from official packages** | can be generated (not a target dump); test in QEMU/SPI |
| **Voice prompts after official flash** | expected restored (whole `user` partition); not explicitly re-checked on HW |
| **Camera 3 version/behaviour** | new in box; unknown V5.01/V5.07 status |
| **Final state of `.161`** | choose V5.07 production SSH (recommended), V5.01 production SSH, or stock |
| **`.153` decision** | keep stock or later production/hardening |
| **Rotate exposed Wi-Fi PSK** | `ConfigExport` exposed it before hardening; user action |
| **CVE-2026-79393 / other family CVEs** | not assessed; could be tested on QEMU/spare |
| **12901 heap RCE** | optional research; DoS confirmed, no weaponised exploit |

---

## ❌ Abandoned / excluded

| Item | Reason |
|---|---|
| **V5.00/V5.02/V5.04 as root targets** | intermediate; same runtime/upgrade weaknesses; someone on them can move to V5.01/V5.07 |
| **Upgrade without burning `user`** | incompatible modules/userspace; not needed |
| **XMTelnet / 9530 secret knock** | no telnetd/9530 in this firmware; paid exploit + offline licence |
| **Vendor RSA private-key search** | not present in firmware; not needed for the VSC path anyway |
| **12901 as a root path** | auth bypass + heap DoS only; no arbitrary command (`timetest` fixed) |
| **12901 PATH hijack / core_pattern / hotplug** | all measured blocked (RO PATH, exec bit, RLIMIT_CORE=0) |
| **UART pad investigation** | stopped earlier; SPI is the chosen physical path (could revisit) |
| **OpenIPC replacement** | no video backend for XM535D1 |
| **CVE-2026-34005 HostName injection** | negative on this IPC (dead code/no caller) |
| **Intermediate downgrade as a root route** | no access advantage; V5.01/V5.07 already rooted |

---

## Artifacts

- Packages: `stack/xm_fw/upg/v501_prod_ssh.bin`, `v507_prod_ssh.bin`,
  `v501_official.bin`, `v501_persist2_user.bin`.
- Keys/passwords: `stack/analysis/access/cam2-production/`,
  `stack/analysis/access/v507-production/` (sensitive; not in git).
- Backup: `stack/backups/2026-11-19/` (packages, credentials, reports, flash dump,
  docs snapshot, SHA256SUMS).
- Public docs: <https://github.com/666dsa666/xiongmai-xm535d1-ipc-rm1-notes>
  (status, upgrade-root, upgrade-root-v507, production-firmware, production-firmware-v507,
  boot-media-root-v507, debug-12901, xmtelnet, ota, return-to-stock).
