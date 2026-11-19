# Xiongmai XM535D1 — IPC-RM1-BLK535-2M6P board notes

Notes for a no-name 2 MP PTZ camera built on the Xiongmai **XM535D1** SoC and the
**`IPC-RM1-BLK535-2M6P V1.03`** board (dated `X-20240827`).

> **Status:** stock firmware already exposes RTSP and ONVIF on the LAN, and both streams
> carry video. No modification is needed for local streaming. The interesting work left
> is **security** (default/blank credentials, unauthenticated ONVIF/RTSP) and **cutting
> the cloud link** for a 100% local camera. See
> [docs/cloud-cut.md](docs/cloud-cut.md) and [docs/cves.md](docs/cves.md).
> OpenIPC can boot on this SoC but has **no video backend** for it, so it is not a useful
> replacement here.
>
> The network telnet path was fully reverse-engineered: the DVRIP `EnableKey` gate is a
> decoy, and the only real debug service (`/usr/bin/debug`, TCP **12901**) is protected by
> the vendor's RSA private key. That is **not** the end of the story: the V5.01 unit build
> accepts a **modified/unsigned update package**, and its `InstallDesc` can run a `Shell`
> command as root (or replace the `user` partition with a custom root-shell daemon). This
> was confirmed in QEMU **and on a spare physical camera**; it gives a persistent root
> shell on TCP 2323 after the automatic reboot. See
> [docs/upgrade-root.md](docs/upgrade-root.md). A verified full SPI dump is still mandatory
> before flashing anything.
>
> **Production builds:** a spare camera was used to validate both the **V5.01** and
> **V5.07** production images on real hardware — SSH key-only root on TCP 2222, no
> unauthenticated shell, cloud/PMS/NAT/online-upgrade/NTP disabled, ONVIF/RTSP/snapshot
> password-protected. The V5.01 image went through a full hardware round-trip; the V5.07
> image was applied, verified and rebooted on hardware, then the camera was downgraded to
> stock V5.01 (hardened config preserved) after validation. Builds, tests and recovery:
> [docs/production-firmware.md](docs/production-firmware.md) (V5.01) and
> [docs/production-firmware-v507.md](docs/production-firmware-v507.md) (V5.07). The first
> camera (`.153`) was left stock.

## Board

| field | value |
|---|---|
| Board | `IPC-RM1-BLK535-2M6P V1.03` (silkscreen), `X-20240827` |
| SoC | Xiongmai **XM535D1** (dual-core 32-bit DSP, Cortex-A5 class, H.265X) |
| Firmware tested | `V5.01.R02.000A07F3.10010.346732.0000000` (build 2024-09-14) |
| Model string | `XM535_X6E-WEQ_8M` (from ONVIF `GetDeviceInformation`) |
| Flash | Fudan **FM25Q64A13** (64 Mbit = **8 MiB**) SPI NOR, SOIC-8 |
| Lens / sensor | 2 MP, 6 mm (`2M6P`) |
| PTZ | 2 stepper motors, ULN2803A driver |
| Storage | microSD slot |
| Stock ports | 80 (Web Viewer), 554 (RTSP), 8899 (ONVIF), 34567 (Xiongmai P2P/DVRIP) |

## It already streams

```
rtsp://<ip>:554/user=admin_password=_channel=1_stream=0.sdp?real_stream   main
rtsp://<ip>:554/user=admin_password=_channel=1_stream=1.sdp?real_stream   sub
```

Observed with `ffprobe -rtsp_transport tcp`:

| stream | codec | resolution | frames |
|---|---|---|---|
| `stream=0` | HEVC | 2304×2592 | 60 / 5 s |
| `stream=1` | HEVC | 640×720 | 60 / 5 s |

The SDP also advertises an audio track (`m=audio 0 RTP/AVP 8`, PCM A-law). ONVIF on
`:8899` answers **without authentication** and returns stream URIs of the form
`rtsp://<ip>:554/user=admin_password=tlJwpbo6_…` (see the CVE notes).

## Read this before exposing it

The camera ships with a **blank `admin` password**, unauthenticated ONVIF, and RTSP that
accepts the empty password embedded in the URL. That is a critical exposure if the camera
is ever reachable from the internet, and a privacy problem on a shared LAN.

- Never port-forward 80, 554, 8899, 34567 or the vendor debug port **12901**; disable UPnP.
- Change the admin password, re-check RTSP/ONVIF afterwards.
- Keep the camera on an isolated VLAN/SSID, or block its WAN access.

Details and CVE mapping: [docs/cves.md](docs/cves.md) and
[docs/security.md](docs/security.md).

## Cloud / P2P

The stock firmware is cloud-first: PMS push to `push.umeye.cn`, a cloud agent (RPS
config, cloud upgrade, cloud storage helpers) and ThroughTek/Kalay P2P (`TUTKID`). There
is no single "cloud off" switch; the reliable cut is network-level (router WAN block),
optionally combined with `NetWork.PMS.Enable=false` over DVRIP. Tested options, trade-offs
and verification commands: [docs/cloud-cut.md](docs/cloud-cut.md).

## Firmware

Official package `V5.07.X02` (2025-09-06), vendor link, SHA-256, partition list and
what it contains: [docs/firmware-v507.md](docs/firmware-v507.md).

Key points: the **V5.01** unit build accepts a modified/unsigned package: the `Mx8Q`
signature is not enforced, a `Shell` upgrade command is executed as root, and the
`user-x.cramfs.img` payload can be replaced (persistent root shell after reboot). That is
the confirmed root path — see [docs/upgrade-root.md](docs/upgrade-root.md). The official
V5.07 package has stricter metadata/CRC checks and was not hardware-tested with a
modified payload. DVRIP `EnableKey` is still **ignored**; ports 23/4321/9530 are closed
and the real vendor debug service is **12901** (RSA-protected, vendor-only). A verified
SPI dump (8 MiB **FM25Q64**) is still required before any flash.

## Documents

- [docs/stock-streaming.md](docs/stock-streaming.md) — ports, RTSP/ONVIF endpoints, observed streams
- [docs/firmware.md](docs/firmware.md) — current version, official update file, update methods
- [docs/firmware-v507.md](docs/firmware-v507.md) — **new**: V5.07.X02 package analysis (InstallDesc, partitions, PMS/cloud strings)
- [docs/cves.md](docs/cves.md) — CVEs and validated weaknesses (RTSP/ONVIF auth, hard-coded creds, 9530/12901, new 2026 Sofia CVEs)
- [docs/cloud-cut.md](docs/cloud-cut.md) — **new**: how to go 100% local (WAN block, PMS disable, static IP caveats)
- [docs/root.md](docs/root.md) — **new**: root/shell path matrix and the definitive telnet verdict
- [docs/upgrade-root.md](docs/upgrade-root.md) — **new**: confirmed root via the unsigned V5.01 upgrade (Shell command / custom `user` partition, real-hardware evidence, procedure, risks)
- [docs/hardening.md](docs/hardening.md) — **new**: hardening a rooted camera (admin password, extra accounts, ONVIF/RTSP/snapshot auth, cloud/PMS/NAT/online-upgrade off, 9530Disable, firewall)
- [docs/production-firmware.md](docs/production-firmware.md) — **new**: production image with authenticated SSH root (key-only, 2222), cloud off, test matrix and recovery
- [docs/upgrade-root-v507.md](docs/upgrade-root-v507.md) — **new**: root on the latest V5.07 too — no CRC/Mx8Q enforcement, variants and downgrade chain (QEMU-validated)
- [docs/boot-media-root-v507.md](docs/boot-media-root-v507.md) — **new**: network-only persistent root on stock V5.07 in QEMU (ConfigImport → mtd5 cramfs init + forged U-Boot env → root console on 2323)
- [docs/production-firmware-v507.md](docs/production-firmware-v507.md) — **new**: V5.07 production SSH image (key-only 2222, hardened), QEMU validation and hardware-pending notes
- [docs/ota.md](docs/ota.md) — **new**: what the cloud app offers (V5.07.X02, same package we already have), OTA endpoint and why not to update if root is wanted
- [docs/xmtelnet.md](docs/xmtelnet.md) — **new**: what XMTelnet really is (paid exploit + offline licence), and why the 9530/telnetd path is absent on this model
- [docs/debug-12901.md](docs/debug-12901.md) — **new**: 12901 auth downgrade (VSC vs RSA), fixed `timetest` command, pre-auth heap overflow; why it is not a root shell
- [docs/return-to-stock.md](docs/return-to-stock.md) — **new**: official-flash restore vs factory config reset; voice prompts and recovery
- [docs/telnet.md](docs/telnet.md) — **rewritten**: EnableKey decoy, safety-code reverse, 12901 vendor debug, UART path
- [docs/emulation.md](docs/emulation.md) — **new**: rebuild the official 8 MiB image and boot it in qemu-bench `xm535`
- [docs/openipc.md](docs/openipc.md) — why OpenIPC has no video on XM535D1
- [docs/security.md](docs/security.md) — default credentials, hardening
- [docs/backup.md](docs/backup.md) — full flash dump / recovery notes

## Legal

Notes on personally owned hardware. No vendor firmware is redistributed.
Documentation CC BY 4.0, snippets MIT (see [`LICENSE`](LICENSE)).

