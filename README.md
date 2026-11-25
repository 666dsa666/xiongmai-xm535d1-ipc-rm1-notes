# Xiongmai XM535D1 — IPC-RM1-BLK535-2M6P notes

Research notes on a no-name PTZ camera built on the Xiongmai **XM535D1** SoC
(board `IPC-RM1-BLK535-2M6P V1.03`): stock behaviour, root access, a hardened
local-only production image, recovery, and known quirks.

## Board

| Field | Value |
|---|---|
| Board | `IPC-RM1-BLK535-2M6P V1.03` |
| SoC | Xiongmai XM535D1 (Cortex-A5 class, H.265) |
| Flash | Fudan FM25Q64A13, 8 MiB SPI NOR, SOIC-8 |
| Model string | `XM535_X6E-WEQ_8M` (ONVIF `GetDeviceInformation`) |
| Firmware studied | `V5.01.R02` (2024-09-14), `V5.07.X02` (2025-09-06) |
| Sensor / lens | two-sensor head; board suffix `2M6P`; RTSP main stream HEVC 2304×2592 at 12 fps ([firmware.md](docs/firmware.md#rtsp)) |
| PTZ | 2 stepper motors, ULN2803A driver |
| Storage | microSD |
| Serial console | `ttyAMA0`; no usable UART pads on this revision |

Details and photos: [docs/hardware.md](docs/hardware.md).

## Key findings

| Topic | Result | Status |
|---|---|---|
| Stock exposure | blank `admin` password; unauthenticated ONVIF; RTSP accepts the empty password | HW |
| Root | unsigned upgrade: `Mx8Q`/CRC compiled in but not enforced on V5.01 and V5.07 (`Ret 515`); custom `user` partition gives persistent root | HW |
| Vendor debug TCP 12901 | closed by default; VSC auth downgrade; runs only a fixed `timetest`; no root shell | HW (closed) + QEMU |
| TCP 50119 | BusyBox `timetest` (hidden telnetd), inactive by default | HW + STATIC |
| UART / telnet 23, 4321, 9530 | not available on this board / closed | HW |
| OpenIPC | reported to boot by OpenIPC; no video backend for this SoC; not flashed here | STATIC |
| Production image | V5.07, SSH key-only on TCP 2222, port 80 closed, cloud cut, NTP on | HW (3 units) |

Current state of every unit and every test: [docs/status.md](docs/status.md).

## Before exposing a stock camera

Never port-forward TCP 80, 554, 8899, 34567 or 12901; disable UPnP. Set an admin password,
re-check RTSP/ONVIF, and isolate the camera (VLAN or WAN block).
See [docs/security.md](docs/security.md) and [docs/hardening.md](docs/hardening.md).

## Documents

| Document | Content |
|---|---|
| [status.md](docs/status.md) | fleet state, firmware × vulnerability matrix, open items |
| [hardware.md](docs/hardware.md) | board photos, probed points, flash layout |
| [firmware.md](docs/firmware.md) | official packages, hashes, package format, OTA, stock streams |
| [security.md](docs/security.md) | stock exposure, CVE table, residual risks |
| [root.md](docs/root.md) | root path matrix, unsigned-upgrade procedure (V5.01/V5.07) |
| [boot-media-root.md](docs/boot-media-root.md) | network-only root via ConfigImport (QEMU only) |
| [debug-services.md](docs/debug-services.md) | 12901 debug service, 50119, GetSaftyCode, EnableKey decoy |
| [production.md](docs/production.md) | production SSH image, install and verification checklists |
| [hardening.md](docs/hardening.md) | DVRIP settings, local-only operation, time/NTP, VMS |
| [recovery.md](docs/recovery.md) | SPI dump, recovery images, return to stock, SSH key loss |
| [quirks.md](docs/quirks.md) | known traps (time, SD/WFS, DVRIP, VMS, web UI) |
| [emulation.md](docs/emulation.md) | booting the official image in QEMU |
| [negative-results.md](docs/negative-results.md) | XMTelnet, OpenIPC, abandoned routes |

Build and upload helpers: [tools/](tools/) and [src/](src/), described in
[production.md](docs/production.md#build).

## Glossary

| Term | Meaning |
|---|---|
| AOV | vendor feature name seen in V5.07 `Sofia` strings (AOV auto-reboot); commonly "always-on video" in vendor material, not verified in this firmware |
| DVRIP | Xiongmai binary management protocol on TCP 34567 (NETsurveillance/XMeye; message numbers such as 1488, 1540) |
| `dvrHelper` | vendor init helper started from `rcS`; starts `/usr/bin/debug` (12901) and the `timetest` telnetd (50119) when `telnetctrl=1` |
| `Mx8Q` | signature field in the upgrade `InstallDesc`; checked by `VerifyMx8QSign`, not enforced on the studied builds |
| PMS | Push Message Service: vendor alarm push to `push.umeye.cn` |
| RSV / VSC | the two authentication modes of the 12901 debug protocol: RSV = RSA signature verification, VSC = short safety-code comparison ([debug-services.md](docs/debug-services.md#protocol)) |
| `Sofia` | main vendor application (`/usr/bin/Sofia`): RTSP, ONVIF, web, DVRIP, cloud, upgrader |
| `ttyk` | account name found next to `admin` in the factory JFFS2 configuration; role not determined |
| VMS | Windows video-management client (version 2.0.28.1) used to view and configure the cameras; its UI was used in French ([hardening.md](docs/hardening.md#vms-setup)) |
| WFS | vendor raw recording layout on the microSD card (WFS 0.4, record and snapshot partitions, no DOS partition table) |

Vendor spellings are kept as they appear in the firmware: `GetSaftyCode` (safety code),
`Conneted` (connected).

DVRIP `Ret` codes, as observed in these notes:

| Ret | Meaning |
|---|---|
| 100 | success; also the progress frames of an upgrade |
| 101 | operation refused (`DelUser` on the cloud service account, V5.07) |
| 103 | error reply to `ConfigImport` (the data is written anyway) and to `TelnetDebugOpen*` |
| 105 | request rejected (CVE-2024-3765 PoC on V5.07) |
| 203 | `Pwd error`: password refused |
| 515 | upgrade accepted and written; the camera reboots |
| 607 | unknown or unavailable configuration name |

## Legal

Notes on personally owned hardware. No vendor firmware is redistributed.
Documentation CC BY 4.0, snippets MIT (see [LICENSE](LICENSE)).
