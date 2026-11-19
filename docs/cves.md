# CVEs and known weaknesses affecting XM535D1 / XM530-family cameras

Scope: Xiongmai **XM535D1** (`XM535_X6E-WEQ_8M`, `IPC-RM1-BLK535-2M6P V1.03`), stock
`V5.01.R02.000A07F3.10010.346732.0000000` (2024-09-14) and official `V5.07.X02`
(2025-09-06).

**There is no CVE naming XM535D1.** The XM535D1 shares the **Sofia** daemon (RTSP, ONVIF,
web, cloud, DVRIP) and the debug/service model with the **XM530** family, so XM530 CVEs
are the relevant class. The `Status` column distinguishes what was **validated on this
unit** from what is **assumed from the shared codebase**.

| CVE / issue | What it is | Status on this unit |
|---|---|---|
| **CVE-2026-79396** | Hard-coded default accounts (`admin/admin`, `user/123456`) in `bin/config.xml` and compiled into `Sofia`; seed logic recreates them. | **Consistent / likely**: `config.xml` and `need_auth` strings exist in `Sofia`; DVRIP and web accept `admin` + **empty** password; the JFFS2 config contains factory `admin` and `ttyk` accounts. Not byte-for-byte disassembled. |
| **CVE-2026-79395** | ONVIF `wsse:UsernameToken` auth bypass when the stored admin password is empty: `admin` + any password is accepted. | **Validated equivalent**: ONVIF `GetProfiles`/`GetStreamUri` work without a real credential; DVRIP login `admin`/empty succeeds. |
| **CVE-2026-79394** | RTSP server ships with authentication disabled (`need_auth=0`): unauthenticated H.264/H.265 + G.711 stream. | **Partially applies**: a bare `DESCRIBE rtsp://<ip>:554/streamtype=0` returns **401**, but the default URL `…/user=admin_password=_channel=1_stream=0.sdp?real_stream` returns **200** and streams. In practice, anyone on the LAN can stream with the blank default password. |
| **CVE-2026-79393** | Heap overflow in `Sofia` WS-Addressing `wsa5:Action` handling (>128 bytes) — remote unauth DoS / possible RCE. | **Family-wide, unassessed here**: our `Sofia` is a 2025 build of the same codebase; no crash tests run (would disrupt the live unit). |
| **CVE-2026-34005** | Root command injection via `HostName` shell metacharacters in an **authenticated DVRIP** request (Sofia DVR/NVR 4.03.R11). | **Not reproduced on this IPC in QEMU**: setting `NetWork.NetCommon.HostName` (and `General.General.MachineName`) to `;id>/tmp/x`, `$(…)`, backticks or newline payloads returns `Ret=100` and stores the value literally, but **no command runs** (no marker file). Likely DVR/NVR-only code path. |
| **CVE-2025-65856** | Authentication bypass on XM530 `V5.00.R02.000807D8…ONVIF 21.06`: unauthenticated device info + live video. | **Likely inherited**: unauth `GetProfiles`/`GetStreamUri` on `:8899` works on this unit (newer V5.07 build, same lineage). |
| **CVE-2025-65857** | `GetStreamUri` returns an RTSP URI with a **hard-coded credential**. | **Validated**: unauthenticated ONVIF `GetStreamUri` returns `rtsp://…user=admin_password=tlJwpbo6…`. |
| **CVE-2024-3765** | Critical vulnerability in XM530 `R80X30-PQ_8M` (details withheld in NVD). | **Unassessed**; same SoC family. |
| **CVE-2020-22253** | Port **9530** "secret knock" starts telnet on older Xiongmai devices. | **Not applicable**: 23/4321/9530 are closed. This vendor moved the debug service to the RSA-protected **12901** (`/usr/bin/debug`); see [telnet.md](telnet.md) and [xmtelnet.md](xmtelnet.md). |
| **CVE-2018-17917 / 17919** | XMeye P2P cloud: MAC→Cloud-ID enumeration; undocumented `default` account/password. | **Cloud side**: relevant while the camera uses `push.umeye.cn` (PMS). Cut the cloud or isolate the camera. |
| **CVE-2018-17915** | XMeye cloud communication not fully encrypted. | Same: cloud side only. |
| **CVE-2017-16725 / CVE-2018-10088** | NetSurveillance/uc-httpd stack overflows. | **Not applicable**: this firmware's web/ONVIF/RTSP stack is `Sofia`, not `uc-httpd`. |
| Mirai-class botnets | Exploit default credentials on Xiongmai devices. | Relevant **only** if the camera is reachable from the Internet. |

## Non-CVE finding: vendor debug service on 12901

On the documented unit, **TCP 12901 is open** — `/usr/bin/debug`, started by `dvrHelper`
when the U-Boot env variable **`telnetctrl`** is set. It can also be **started remotely**
through DVRIP: the `GetSaftyCode` success path calls `LibXmDvr_Debug_open()` →
`system("debug&")` (V5.01 `0x1a7ff4`); `TelnetEnable`/`TelnetDisEnable` only remove/create
the `/mnt/mtd/Log/9530Disable` startup marker. `/usr/bin/debug` on 12901 has a **client-selectable auth downgrade**: a short field uses a
weak, offline-computable safety code (VSC) and bypasses the vendor RSA check; a long field
uses the real RSA signature check (RSV). The post-auth `Run` command is the fixed literal
`timetest` (not a shell), and a **pre-auth heap overflow** exists in the `Update` stage
(up to 225 bytes). There is no ready-made root primitive in this service, but it is a
network attack surface and an RCE research target. Details:
[debug-12901.md](debug-12901.md). It is a vendor backdoor, not a user-accessible shell:
block 12901 at the firewall/router, and never port-forward it. It can be disabled at boot
by creating `/mnt/mtd/Log/9530Disable` (or `/mnt/custom/9530Disable`) — the daemon exits
with `LIBDVR : Debug: is Disabled!` when either marker exists. Details:
[telnet.md](telnet.md).

## Non-CVE finding: unsigned upgrade → root (confirmed on hardware)

This is not a named CVE yet, but it is the most serious issue found on this product:
the **V5.01** `CUpgrader` accepts a modified/unsigned package. The `Mx8Q` signature is
not enforced, a `Shell` command in `InstallDesc` is executed **as root**, and the
`user-x.cramfs.img` payload can be replaced by a custom squashfs. The latter gives a
persistent root shell on TCP 2323 after the automatic reboot.

Status:

- **QEMU**, exact V5.01 stock image: package accepted (`Ret 515`), `Shell` marker survives
  reboot, custom `user` gives root sessions and survives a full QEMU restart;
- **real hardware**, spare camera on V5.01.R02: package accepted (`Ret 515`), automatic
  reboot, three sequential root sessions (`Uid: 0`), no power-cycle;
- V5.04/V5.07 add CRC/metadata checks and were **not** tested with a modified payload.

Full write-up, package hashes, procedure and risks:
[upgrade-root.md](upgrade-root.md). This should be reported to the vendor as a firmware
integrity / privilege-escalation issue; do not expose port 2323 on a rooted camera.

## Practical exposure of a stock unit

| Service | Port | Auth |
|---|---|---|
| HTTP web UI | 80 | `admin` + blank password |
| RTSP | 554 | blank default password embedded in the URL; bare DESCRIBE gets 401 |
| ONVIF | 8899 | unauthenticated `GetProfiles` / `GetStreamUri` (hard-coded password in URI) |
| Xiongmai P2P/DVRIP | 34567 | `admin` + blank password |
| Vendor debug (`/usr/bin/debug`) | **12901** | vendor RSA handshake (backdoor) |
| Cloud push (PMS) | outbound | `push.umeye.cn:80` |

This camera **cannot be considered secure on an untrusted LAN** and must never be exposed
with port forwarding/DMZ. The defaults are enough to watch, control PTZ and read settings.

## Hardening checklist

1. **Do not forward** 80/554/8899/34567/**12901**; disable UPnP on the router.
2. Change the web admin password (also changes the RTSP path password; re-check ONVIF).
3. Put the camera on an **isolated VLAN/SSID** and block its WAN access.
4. Disable **PMS** (`NetWork.PMS.Enable=false` via DVRIP, see [cloud-cut.md](cloud-cut.md))
   and block outbound traffic.
5. Block TCP **12901** (vendor debug) at the router even on the LAN.
6. If compromise is suspected: block WAN, reset credentials, remove the device from the
   cloud account, and restore a known firmware/SPI dump.

## References

- NVD entries: CVE-2026-79393, CVE-2026-79394, CVE-2026-79395, CVE-2026-79396,
  CVE-2026-34005, CVE-2025-65856, CVE-2025-65857, CVE-2024-3765, CVE-2020-22253,
  CVE-2018-17915/17917/17919, CVE-2017-16725, CVE-2018-10088.
- CISA ICSA-26-113-05 (XM530 IP camera, CVE-2025-65856).
- Aliyun AVD / VulDB analyses for the 2026 Sofia CVEs.
- Vladislav Yarmak, 2020 "backdoor in Xiongmai firmware" (9530) — not applicable here.
