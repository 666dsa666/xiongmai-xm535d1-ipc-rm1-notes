# CVEs and known weaknesses affecting XM535D1 / XMeye cameras

Scope: Xiongmai **XM535D1** (`XM535_X6E-WEQ_8M`, `IPC-RM1-BLK535-2M6P` board), stock firmware
`V5.01.R02.000A07F3.10010.346732.0000000` (build 2024-09-14) and the newer official
`V5.07.X02` (2025-09-06) package.

These CVEs were published for the XM530/XMeye platform family. The XM535D1 shares the
same **Sofia** application daemon (RTSP, ONVIF, web UI, cloud agent), so the class of
issues applies even where a CVE text names XM530. Items marked **validated** were
reproduced on the unit documented here.

| CVE / issue | What it is | Status on this unit |
|---|---|---|
| **CVE-2026-79394** | Sofia RTSP server does not enforce Digest auth (`need_auth=0` in `bin/config.xml`); unauthenticated `DESCRIBE`/`SETUP`/`PLAY` yields H.264/HEVC + G.711 audio. | **Validated equivalent**: `DESCRIBE rtsp://<ip>:554/user=admin_password=_channel=1_stream=0.sdp?real_stream` → `200 OK`, video plays with a blank password. |
| **CVE-2026-79396** | Plain-text built-in accounts (`admin/admin`, `user/123456`) in `bin/config.xml` and in `Sofia` `.rodata`; seed logic can re-create them. | **Consistent**: `admin` with an **empty** password logs into web UI and DVRIP; RTSP path auth accepts empty password. Not disassembled on this specific build. |
| **CVE-2025-65857** | `GetStreamUri` returns an RTSP URI containing a hard-coded credential token. | **Validated**: unauthenticated ONVIF `GetProfiles`/`GetStreamUri` on `:8899` returns `rtsp://…user=admin_password=tlJwpbo6_channel=0_stream=0…`. |
| **CVE-2018-17919** | XMeye P2P cloud used an undocumented `default` account / default password. | Cloud side; relevant only while the device uses XMeye/umeye cloud services. |
| **CVE-2018-17917** | MAC address → Cloud ID enumeration on XMeye cloud. | Cloud side; same caveat. |
| **CVE-2017-16725** | NetSurveillance web stack overflow; **port 9530** "secret knock" that enables telnet on older Xiongmai/HiSilicon firmware. | **Not exploitable here**: ports **23, 4321 and 9530 are closed**; `/mnt/mtd/Log/9530Disable` gate exists in `Sofia`. |
| Mirai-class botnets | Opportunistic exploitation of default credentials on Xiongmai devices. | Relevant **only if** the camera is reachable from the internet; see hardening. |

## Why "9530" does not work on this firmware

The 2020 public "backdoor" research (Vladislav Yarmak / Censys / VulnCheck) relies on a
special sequence sent to TCP **9530**, which starts a telnet daemon. On this unit:

- `9530/tcp` is closed (connection refused), `23/tcp` and `4321/tcp` are closed;
- the firmware contains `/mnt/mtd/Log/9530Disable` and `Ability.TelnetDebugMode` gates;
- the upgrade package is signed (`InstallDesc` → `Mx8Q`), so the older "unsigned
  `InstallDesc` + `Shell` command" telnet-opener path is rejected (see
  [telnet.md](telnet.md)).

Shell access therefore still requires **UART** (or an SPI dump), not a network exploit.

## Practical exposure of a stock unit

| Service | Port | Auth |
|---|---|---|
| HTTP web UI | 80 | `admin` + blank password |
| RTSP | 554 | blank password embedded in the URL path; unauth `DESCRIBE` accepted |
| ONVIF | 8899 | unauthenticated `GetProfiles`/`GetStreamUri` |
| Xiongmai P2P/DVRIP | 34567 | `admin` + blank password for DVRIP login |
| Cloud push (PMS) | outbound | `push.umeye.cn` |

This is a camera that **cannot be considered secure on an untrusted LAN**, and must never
be exposed with a port forwarding/DMZ. The default credentials + unauth ONVIF/RTSP are
enough for anyone on the same network to watch, control PTZ and read settings.

## Hardening checklist (before any internet exposure)

1. **Do not forward ports** 80/554/8899/34567; disable UPnP on the router.
2. Change the web admin password (this also changes the RTSP path password; re-check
   ONVIF afterwards).
3. Put the camera on an **isolated VLAN/SSID** or block its WAN access.
4. If the cloud/app is not needed, disable **PMS** (`NetWork.PMS.Enable=false` via
   DVRIP, see [cloud-cut.md](cloud-cut.md)) and block outbound traffic.
5. Treat the device as untrusted: it can still talk to the vendor cloud while online.
6. If you suspect compromise: block WAN, reset the admin password, remove the device
   from the cloud account, re-flash a known official firmware (signed package only).

## References

- CVE-2026-79394 / CVE-2026-79396 — Xiongmai Sofia RTSP auth bypass / hard-coded
  credentials (Aliyun AVD entries, 2026-09-12).
- CVE-2025-65857 — XM530 `GetStreamUri` hard-coded RTSP credentials.
- CVE-2018-17917 / CVE-2018-17919 — XMeye P2P cloud design issues.
- CVE-2017-16725 — NetSurveillance web stack + 9530 telnet activation.
- Vladislav Yarmak, "Backdoor in Xiongmai firmware" (2020), Censys/VulnCheck analyses.
