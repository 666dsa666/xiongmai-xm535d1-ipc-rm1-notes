# Security

Exposure of the stock firmware, CVE applicability on this board, non-CVE findings, the
attack surface of the production image and the remaining risks. Hardening steps are in
[hardening.md](hardening.md).

Scope: `XM535_X6E-WEQ_8M` on `IPC-RM1-BLK535-2M6P V1.03`, stock
`V5.01.R02.000A07F3.10010.346732.0000000` (build 2024-09-14) and official
`V5.07.X02.000A07F3.10010.346732.0000000` (build 2025-09-06).

## Stock exposure

Measured on stock V5.01 (**HW**).

| Service | Port | Authentication on stock |
|---|---|---|
| Web UI (`Sofia`) | TCP 80 | `admin` + empty password; legacy JSON bridge accepts `admin` + any password |
| RTSP | TCP 554 | empty password embedded in the URL `user=admin_password=_channel=1_stream=0.sdp?real_stream` → `200`; bare `DESCRIBE …/streamtype=0` → `401` |
| ONVIF | TCP 8899 | `GetSystemDateAndTime`, `GetProfiles`, `GetStreamUri` answer without auth; URI carries `password=tlJwpbo6` (`sofia_hash` of the empty password) |
| DVRIP / Xiongmai P2P | TCP 34567 | `admin` + empty password |
| Vendor debug `/usr/bin/debug` | TCP 12901 | closed by default; starts only with U-Boot `telnetctrl=1` or DVRIP `GetSaftyCode` |
| BusyBox `timetest` (hidden telnetd) | TCP 50119 | present in firmware, inactive by default, gated by `telnetctrl` |
| Telnet | TCP 23 / 4321 / 9530 | closed |
| PMS push | outbound | `push.umeye.cn:80` (`NetWork.PMS.Enable=true`) |
| Online upgrade | outbound | `upgrade.secu100.net:8083` (`Enable`, `AutoCheck`, `AutoUpgradeImp` all true); package download on 9083 ([firmware.md](firmware.md#ota-and-official-updates)) |
| NAT/P2P, cloud agent, TUTK | outbound | NAT channel `Conneted` while online; TUTK id in `/mnt/mtd/Log/TUTKID` |

Consequence: anyone on the LAN can watch the streams, move the PTZ, read the full
configuration and change accounts without credentials. Never port-forward 80, 554, 8899,
34567, 12901; disable UPnP on the router.

## CVEs

No CVE names the XM535D1. It shares the `Sofia` daemon (RTSP, ONVIF, web, cloud, DVRIP) and
the debug model with the XM530 family, so XM530 CVEs are the relevant class.

| CVE | Description | Status on this board |
|---|---|---|
| CVE-2026-79396 | Hard-coded default credentials stored in `bin/config.xml` and compiled into `Sofia` | Consistent: **STATIC** `config.xml`/`need_auth` strings in `Sofia`; **HW** web and DVRIP accept `admin` + empty; factory JFFS2 config holds `admin` and `ttyk` ([Glossary](../README.md#glossary)). Not fully disassembled |
| CVE-2026-79395 | ONVIF `wsse:UsernameToken` bypass when the stored admin password is empty | Equivalent validated (**HW**, stock V5.01): `GetProfiles`/`GetStreamUri` work without a real credential. Closed by a non-empty password + `OnvifPwdCheckout=true` (**HW**) |
| CVE-2026-79394 | Embedded RTSP server with authentication disabled by default (`need_auth=0`) | Partial (**HW**): bare URL → `401`, default URL with empty password → `200`. Closed by a non-empty password (**HW**: empty → `401`) |
| CVE-2026-79393 | `Sofia` WS-Addressing `wsa5:Action` heap overflow (>128 bytes), unauth DoS / possible RCE | **UNTESTED** (no crash tests on live units); reported on the older XM530 line |
| CVE-2026-34005 | Authenticated DVRIP `HostName` command injection (DVR/NVR 4.03.R11) | Not reproduced (**QEMU**): `NetWork.NetCommon.HostName` / `General.General.MachineName` payloads (`;id>/tmp/x`, `$(…)`, backticks, newline) → `Ret 100`, stored literally, no execution. **STATIC**: dead code / no caller |
| CVE-2025-65856 | XM530 auth bypass: unauth device info + live video | Same class observed (**HW**, stock V5.01): unauth ONVIF read surface. Closed by `OnvifPwdCheckout=true` (**HW**); returns after a factory reset |
| CVE-2025-65857 | `GetStreamUri` returns a URI with hard-coded `wphd` / `2MNswbQ5` | Not applicable as such: strings absent from V5.07 (**STATIC**), unauth `GetStreamUri` → `401` (**HW**). Related stock V5.01 leak of the default token `tlJwpbo6`; closed on the hardened fleet |
| CVE-2024-3765 | DVRIP msg 1009 unauth access control (affected list ends at V5.00.R02) | Not vulnerable on V5.07 (**HW**): published PoC → `Ret 105`. Older builds untested |
| CVE-2020-22253 | Port 9530 knock starts telnetd | Not applicable (**HW**): 23/4321/9530 closed; debug moved to 12901 |
| CVE-2018-17917 / CVE-2018-17919 | XMeye cloud: MAC → Cloud-ID enumeration; undocumented `default` account | Cloud side; irrelevant once the cloud is cut (**UNTESTED** on device) |
| CVE-2018-17915 | XMeye cloud traffic not fully encrypted | Cloud side; same as above |
| CVE-2017-16725 / CVE-2018-10088 | NetSurveillance `uc-httpd` stack overflows | Not applicable (**STATIC**): the web stack is `Sofia`, not `uc-httpd` |
| CVE-2026-88833 | BusyBox `udhcpc` integer underflow on crafted DHCP packets, DoS from the same network segment | Applies (**STATIC**, BusyBox 1.33.1; `udhcpc` runs on `eth3`). Mitigation: DHCP snooping or static IP |
| CVE-2021-27419 | uClibc-ng | Affected version 1.0.26 (**STATIC**); no standalone exploit path shown |
| CVE-2022-45045 class | Post-auth admin → root | Not demonstrated |
| Mirai-class botnets | Default-credential abuse | Relevant only if reachable from the internet |

ID verification (web lookup of the public CVE records):

- CVE-2026-79393, -79394, -79395, -79396: published 2026-09-11 by MITRE for Xiongmai IP Camera
  XM530 firmware `HMT.CM2005-v220608.1837` and earlier (NVD status "Deferred"). Records:
  `https://nvd.nist.gov/vuln/detail/<ID>`, mirrored at `https://app.opencve.io/cve/<ID>`.
- CVE-2026-88833: BusyBox `udhcpc`; listed by the Debian security tracker
  (<https://security-tracker.debian.org/tracker/CVE-2026-88833>) as unfixed in current
  BusyBox packages. Not version-matched against BusyBox 1.33.1 beyond the description.
- ICSA-26-113-05: CISA advisory "Hangzhou Xiongmai Technology Co., Ltd XM530 IP Camera",
  released 2026-04-23, covering CVE-2025-65856 on `XM530V200_X6-WEQ_8M`
  `V5.00.R02.000807D8.10010.346624` (checked via the GCVE mirror,
  <https://db.gcve.eu/vuln/icsa-26-113-05>).
- Other IDs in the table: NVD entries, not re-checked in this revision. The Aliyun AVD / VulDB
  analyses of the 2026 `Sofia` CVEs are cited as reported, without a verified link.
- Xiongmai 9530 backdoor write-up (2020, not applicable here): see
  [negative-results.md](negative-results.md#xmtelnet).

## Non-CVE findings

- **Unsigned upgrade → root** (most serious): V5.01 and V5.07 accept modified packages
  (`Mx8Q`/CRC not enforced, `Ret 515`, **HW**). A custom `user` partition gives persistent
  root (**HW**); the `InstallDesc` `Shell` command variant is **QEMU** only. An official
  update removes the custom root but the path stays open. See [root.md](root.md).
- **12901 vendor debug**: closed by default; client-selectable auth downgrade (VSC instead of
  vendor RSA), post-auth command is the fixed literal `timetest`, pre-auth heap overflow in the
  `Update` stage (up to 225 bytes). No root shell. Disabled at boot by
  `/mnt/mtd/Log/9530Disable` or `/mnt/custom/9530Disable`. See
  [debug-services.md](debug-services.md).
- **50119 hidden telnetd** and **DVRIP `OPTelnetControl`/`EnableKey` decoy** (any key accepted,
  no listener): [debug-services.md](debug-services.md).
- **Legacy HTTP JSON bridge** (**HW**, V5.01): `/cgi-bin/` `getinfo.cgi`, `getconfig.cgi`,
  `getability.cgi`, `getdefault.cgi`, `usermanager.cgi`, `getlog.cgi`, `opdev.cgi` parse
  `Name`/`UserName`/`Password` from a JSON body and dispatch DVRIP operations without the RSA
  web login. With an empty admin password, `admin` + any password → `Ret 100`:
  ```http
  POST /cgi-bin/usermanager.cgi
  {"Name":"GetAllUser","UserName":"admin","Password":""}
  ```
  `GetAllUser` returns plaintext passwords; `ConfigExport` via `opdev.cgi`
  (`{"Name":"ConfigExport","DataType":"Config",...}`) returns a base64 ZIP of
  `/mnt/mtd/Config`, including `wpa.conf` with the Wi-Fi SSID and PSK in clear. DVRIP msgs
  1482/1486/1488 add/delete users and change the admin password. After hardening, any non-empty
  password, including the correct one, gives `Ret 203 Pwd error` (**HW**); with block80, port
  80 is closed. Rotate any Wi-Fi PSK or
  reused password exposed before hardening.
- **`ConfigImport` path traversal** (DVRIP msg 1540, raw ZIP body; **QEMU**): extracted to
  `/var/config_tmp` then `/mnt/mtd/Config`; `../` entries are written as root under
  `/mnt/mtd` (persistent). Entries such as `../../dev/mtd0` or `../../dev/mtdblock0` overwrite
  the boot partition and brick the unit. Root write / DoS primitive; used for the V5.07
  network-only root in [boot-media-root.md](boot-media-root.md).
- **Cloud-created service account**: one per paired camera, in `System.ExUserMap` and the user
  list, hidden from the web UI account list. Not deletable on V5.07 (`Ret 101`). Handling:
  [hardening.md](hardening.md#service-account).

## Production surface

Read-only audit of a V5.07 block80 production camera (**HW**). All vendor binaries were
SHA-256-identical to the official V5.07 package.

| Component | Version / note |
|---|---|
| Kernel | Linux 3.10.103+ #84 (build 2025-08-06), EOL |
| libc | uClibc-ng 1.0.26 / NPTL (Buildroot 2017.11) |
| BusyBox | 1.33.1 (custom `timetest` = telnetd applet) |
| `Sofia` | V5.07.X02, ONVIF `hsoap/2.8`, `S.ONVIF 21.06` |
| `libdvr`, `libXMcrypto` | vendor |
| wpa_supplicant | 2.10 (station) |
| hostapd | 2.10_ATBM, shipped, not running |
| dropbear | 2024.86, static, publickey only |
| block80 | `LD_PRELOAD` bind shim, blocks TCP 80 |
| OpenSSL | absent; no TLS listener |

Reachable: TCP 554 (RTSP), 8899 (ONVIF), 34567 (DVRIP), 2222 (SSH), UDP 3702
(WS-Discovery), DHCP client. RST-closed from the LAN: 80, 443, 2323, 8443, 9530, 12901, 23000,
50119, 23. `Sofia` listens on TCP 23000 on `127.0.0.1` only (seen in `netstat` under **QEMU**),
so it is not reachable from the LAN. 4321 was not in this audit's probe list; it is closed in
the other scans recorded in [status.md](status.md).

No unauthenticated RCE, credential or video path was found on this surface.

## Residual risks

1. **Hardening is not baked in.** It lives in `/mnt/mtd`. A factory reset restores
   `OnvifPwdCheckout=false` and the unauthenticated ONVIF read surface; an official upgrade
   removes dropbear and block80. Re-run the post-flash checklist of
   [production.md](production.md#post-flash-checklist) after every reset or upgrade.
2. **Root SSH on TCP 2222**, key-only: the private key is the root credential. Controls: key
   custody and network ACL.
3. **Cleartext protocols and pass-the-hash**: RTSP, DVRIP and ONVIF are cleartext; the
   8-character `Sofia` hash works as an RTSP password. Protect config exports and backups.
4. **`udhcpc` DoS** (CVE-2026-88833): DHCP snooping or static IP.
5. **Latent**: uClibc-ng CVE-2021-27419, EOL kernel (local/DoS, unknown patch level),
   CVE-2022-45045-class post-auth admin → root (not demonstrated), CVE-2026-79393 (untested).
6. **Re-root by others**: the unsigned-upgrade path accepts any package from anyone holding
   the admin password.

Operational controls:

- VLAN/ACL: restrict TCP 2222/34567/8899/554 and UDP 3702 to the clients that need them;
  block camera egress except NTP.
- Rotate the Wi-Fi PSK exposed by `ConfigExport`.
- Optional: close 8899 and 554 with the same bind-shim method if VMS/Home Assistant does not
  need them; rebuild dropbear ≥ 2025.88.
- If compromise is suspected: block WAN, reset credentials, remove the device from the cloud
  account, restore a known firmware or SPI dump ([recovery.md](recovery.md)).
