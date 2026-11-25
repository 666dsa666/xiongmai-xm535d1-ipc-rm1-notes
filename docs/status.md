# Status

Single source of truth for the state of the three cameras and for what was tested on which
firmware. Details live in the linked pages; this page only records verdicts and their evidence level.

Legend: **HW** = real hardware; **QEMU** = exact official image under QEMU
([emulation.md](emulation.md)); **STATIC** = binary/string analysis only; **UNTESTED** = not
run. `NO` in a cell means tested and absent/negative.

## Fleet

All three units are `IPC-RM1-BLK535-2M6P V1.03` boards ([hardware.md](hardware.md)) and run the
same production image ([production.md](production.md)).

| Unit | Firmware | Root method | SSH | SPI dump |
|---|---|---|---|---|
| cam1 | `V5.07.X02` production | unsigned upgrade, custom `user` partition (variant B) — **HW** | root, key-only, TCP 2222 | **yes**: one 8 MiB dump of the `V5.01.R02` stock state, two identical reads |
| cam2 | `V5.07.X02` production | unsigned upgrade, custom `user` partition (variant B) — **HW** | root, key-only, TCP 2222 | no (risk accepted) |
| cam3 | `V5.07.X02` production | unsigned upgrade, custom `user` partition (variant B) — **HW** | root, key-only, TCP 2222 | no (risk accepted) |

Common state on all three units (**HW**):

- TCP 80 closed by the `block80` bind shim; TCP 23, 2323, 4321, 9530, 12901 and 50119 closed.
- Cloud cut: PMS, NAT and online upgrade off, `DisableXmServerConn` set
  ([hardening.md](hardening.md)). NTP stays on with public servers (deliberate exception).
- Time: `/mnt/mtd/Config/localtime=GMT-1` together with `System.TimeZone.timeMin=-60`; live
  clock and recording timestamps correct ([hardening.md](hardening.md#time-and-ntp)).
- Cloud-created `<service-account>` kept (DVRIP `DelUser` returns `Ret 101` on V5.07), moved to
  group `user` with a strong random password. VMS connects as `admin`.
- SD recording: 64 GB card, `SDCheckStatus=0`, files written continuously. A 128 GB card failed
  WFS init (status 17) on cam1 and was replaced ([quirks.md](quirks.md)).
- An official update removes the custom root; the unsigned-upgrade path stays open, so the unit
  can be re-rooted ([firmware.md](firmware.md#ota-and-official-updates)).
- cam1's dump is a rollback for cam1 only. It must not be cloned onto cam2/cam3
  (identity/calibration). No destructive boot-media or recovery test runs on cam2/cam3
  ([recovery.md](recovery.md)).

## Firmware × vulnerability matrix

Builds: `V5.00.R02` (2024-04-18), `V5.01.R02` (2024-09-14, shipping build), `V5.02.R02`,
`V5.04.R02`, `V5.07.X02` (2025-09-06, latest official). See [firmware.md](firmware.md).

### Root and upgrade

| Item | V5.00 | V5.01 | V5.02 | V5.04 | V5.07 | Details |
|---|---|---|---|---|---|---|
| QEMU boot of official image | QEMU | QEMU | QEMU | QEMU | QEMU | [emulation.md](emulation.md) |
| `Mx8Q`/CRC enforced | NO (STATIC, QEMU) | NO (HW) | NO (STATIC, QEMU) | NO (adds flag-gated CRC read; QEMU) | NO (new verifier, flags off; HW) | [firmware.md](firmware.md#integrity-check-mx8q-crc) |
| Unsigned package accepted (`Ret 515`) | QEMU | HW | QEMU | QEMU | HW | [root.md](root.md) |
| Variant A: `Shell` command in `InstallDesc` runs as root | QEMU | QEMU | QEMU | QEMU | QEMU (uid 0) | [root.md](root.md) |
| Variant B: custom `user` partition, persistent root | QEMU | HW | QEMU | QEMU | HW | [root.md](root.md) |
| Production SSH image (key-only TCP 2222) | UNTESTED | HW | UNTESTED | UNTESTED | HW (fleet) | [production.md](production.md) |
| Official package restore / downgrade (`Ret 515`, root removed, config kept) | — | HW | — | — | HW | [recovery.md](recovery.md) |
| Boot-media root (ConfigImport → `mtd5` cramfs `/init` + forged `mtd0` env, root on TCP 2323) | QEMU | QEMU | QEMU | QEMU | QEMU | [boot-media-root.md](boot-media-root.md) |

The same V5.01 rooted `user-x` payload was accepted and rooted on V5.00, V5.02, V5.04 and V5.07
(**QEMU**). Per-build payloads are still preferred: `user` partition sizes differ (V5.02 is
0x40 bytes shorter), and DVRIP reports the payload's build after a mixed `/usr`.

### Attack surface

| Item | V5.00 | V5.01 | V5.02 | V5.04 | V5.07 | Details |
|---|---|---|---|---|---|---|
| ConfigImport (DVRIP msg 1540) path-traversal write; `mtd0`/`mtd1`/`mtd5` writable | QEMU (`Ret 103`) | QEMU | QEMU (`Ret 103`) | QEMU (`Ret 103`) | QEMU (`Ret 103`) | [boot-media-root.md](boot-media-root.md) |
| HTTP bridge as `admin` + empty password; `ConfigExport` leaks accounts/Wi-Fi PSK | QEMU (`Ret 100`) | HW (stock) | QEMU (`Ret 100`) | QEMU (`Ret 100`) | QEMU (`Ret 100`) | [security.md](security.md) |
| ONVIF/RTSP unauthenticated access | QEMU (200 / 401→200) | HW | QEMU (200 / 401→200) | QEMU (200 / 401→200) | QEMU; `GetStreamUri` 401 unauth | [security.md](security.md) |
| 12901 `/usr/bin/debug` listening by default | STATIC (byte-identical binary) | NO (HW) | STATIC | STATIC | NO (HW, stock and production) | [debug-services.md](debug-services.md) |
| 12901 VSC auth downgrade (RSA not required), pre-auth heap overflow (DoS, no RCE) | QEMU | QEMU | QEMU | QEMU | QEMU | [debug-services.md](debug-services.md) |
| 12901 post-auth root shell | NO (fixed `timetest`) | NO | NO | NO | NO | [debug-services.md](debug-services.md) |
| 50119 hidden telnetd (`/sbin/timetest`) listening by default | STATIC | NO (HW) | STATIC | STATIC | NO (HW) | [debug-services.md](debug-services.md) |
| telnetd on TCP 23 / 9530 subsystem | NO (STATIC) | NO (HW, QEMU) | NO (STATIC) | NO (STATIC) | NO (HW, QEMU) | [negative-results.md](negative-results.md) |
| DVRIP `EnableKey` opens telnet (decoy) | NO (STATIC) | NO (QEMU) | NO (STATIC) | NO (STATIC) | NO (QEMU) | [debug-services.md](debug-services.md) |

### CVEs

| CVE | Verdict | Level | Details |
|---|---|---|---|
| CVE-2024-3765 (DVRIP msg 1009 access control) | not vulnerable on V5.07: PoC returns `Ret 105`; older builds not tested | HW (V5.07) | [security.md](security.md) |
| CVE-2025-65857 (`GetStreamUri` hard-coded credential) | not applicable as such: `wphd`/`2MNswbQ5` absent from V5.07, `GetStreamUri` 401 unauth. Stock V5.01 leaked another default token (`tlJwpbo6` = `sofia_hash` of empty password) in the ONVIF URI; closed on the fleet | STATIC + HW | [security.md](security.md) |
| CVE-2026-34005 (`HostName` command injection) | negative: value stored literally, no command runs | QEMU | [security.md](security.md) |
| CVE-2026-79393 (`wsa5:Action` heap overflow) | unassessed; same Sofia codebase | UNTESTED | [security.md](security.md) |

### Board-level

| Item | Verdict | Level | Details |
|---|---|---|---|
| UART console | no usable pads on this revision; kernel console `ttyAMA0` | HW | [hardware.md](hardware.md) |
| SPI dump / restore cycle | cam1 dump verified; dump → recovery image → restore cycle | QEMU | [recovery.md](recovery.md) |
| Reconstructed V5.01/V5.07 factory recovery images | boot, first boot formats `mtd5` | QEMU | [recovery.md](recovery.md) |
| SD recording 5–10 min failure | not reproduced on 64 GB | HW | [quirks.md](quirks.md) |

## Open items

All remaining items are optional; none blocks the fleet.

| Item | Note |
|---|---|
| Physical SPI write/restore | recovery images and restore cycle validated in QEMU only; needs a sacrificial board |
| Boot-media root on hardware | QEMU only; destructive to `mtd0`/`mtd5`; only on a unit with its own dump |
| CVE-2026-79393 | unassessed; QEMU or a spare unit only |
| V5.00/V5.02/V5.04 on hardware | research only; intermediate builds |
| 12901/50119 protocol audit | research only; neither is a stock root path |
| Long-term SD recording | keep observing the 64 GB cards |
