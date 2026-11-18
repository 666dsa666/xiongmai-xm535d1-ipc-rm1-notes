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
| **CVE-2026-34005** | Root command injection via `HostName` shell metacharacters in an **authenticated DVRIP** request (Sofia DVR/NVR 4.03.R11). | **Unknown / worth testing**: DVRIP `admin`/empty authenticates, and the XM535D1 uses the same Sofia family. Test in the QEMU emulator before trying on hardware. |
| **CVE-2025-65856** | Authentication bypass on XM530 `V5.00.R02.000807D8…ONVIF 21.06`: unauthenticated device info + live video. | **Likely inherited**: unauth `GetProfiles`/`GetStreamUri` on `:8899` works on this unit (newer V5.07 build, same lineage). |
| **CVE-2025-65857** | `GetStreamUri` returns an RTSP URI with a **hard-coded credential**. | **Validated**: unauthenticated ONVIF `GetStreamUri` returns `rtsp://…user=admin_password=tlJwpbo6…`. |
| **CVE-2024-3765** | Critical vulnerability in XM530 `R80X30-PQ_8M` (details withheld in NVD). | **Unassessed**; same SoC family. |
| **CVE-2020-22253** | Port **9530** "secret knock" starts telnet on older Xiongmai devices. | **Not applicable**: 23/4321/9530 are closed. This vendor moved the debug service to the RSA-protected **12901** (`/usr/bin/debug`); see [telnet.md](telnet.md). |
| **CVE-2018-17917 / 17919** | XMeye P2P cloud: MAC→Cloud-ID enumeration; undocumented `default` account/password. | **Cloud side**: relevant while the camera uses `push.umeye.cn` (PMS). Cut the cloud or isolate the camera. |
| **CVE-2018-17915** | XMeye cloud communication not fully encrypted. | Same: cloud side only. |
| **CVE-2017-16725 / CVE-2018-10088** | NetSurveillance/uc-httpd stack overflows. | **Not applicable**: this firmware's web/ONVIF/RTSP stack is `Sofia`, not `uc-httpd`. |
| Mirai-class botnets | Exploit default credentials on Xiongmai devices. | Relevant **only** if the camera is reachable from the Internet. |

## Non-CVE finding: vendor debug service on 12901

On the documented unit, **TCP 12901 is open** — `/usr/bin/debug`, started by `dvrHelper`
when the U-Boot env variable **`telnetctrl`** is set. Its protocol is protected by an
**RSA signature check with the vendor's private key**; after a successful handshake it can
`popen()` root commands. It is a vendor backdoor, not a user-accessible shell:
block 12901 at the firewall/router, and never port-forward it. Details:
[telnet.md](telnet.md).

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
