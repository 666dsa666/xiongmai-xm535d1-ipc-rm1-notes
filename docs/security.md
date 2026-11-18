# Security — default credentials and hardening

## What the stock firmware exposes

| service | port | authentication |
|---|---|---|
| RTSP | 554 | none for the Xiongmai URL form with `password=` empty |
| ONVIF | 8899 | `GetSystemDateAndTime`/`GetProfiles` answer without auth |
| Web UI | 80 | `admin` with empty password |
| Xiongmai P2P | 34567 | cloud/app channel |
| Vendor debug (`/usr/bin/debug`) | **12901** | RSA vendor handshake (backdoor; nobody else can log in) |

The RTSP URL embeds the credentials in the path
(`user=admin_password=<password>_channel=1_stream=0.sdp`), and with the factory default the password field
is empty. Anyone on the LAN can watch the stream.

## Harden it

1. **Open the web UI** (`http://<ip>/`, `admin` / empty) and set a non-empty admin password.
2. **Re-test RTSP** — the URL must then carry the password:
   `rtsp://<ip>:554/user=admin_password=<password>_channel=1_stream=0.sdp?real_stream`
   ONVIF `GetStreamUri` will return the corresponding token.
3. **Keep ports on the LAN**: 80, 554, 8899, 34567 and the vendor debug **12901** must never be forwarded from the internet.
4. **Block WAN if you do not use the cloud app.** These Xiongmai firmwares normally keep streaming when
   the internet is unavailable; block the camera's outbound traffic at the router (or its MAC) and verify
   RTSP still works.
5. If you do not use the mobile app at all, consider blocking 34567 outbound too — that is the P2P channel.

## Notes

- Changing the password may also change the ONVIF device credentials; re-check ONVIF after the change.
- The web UI is plain HTTP; do not administer it over an untrusted network.
- As with any cheap IP camera, treat it as an untrusted device: put it on an isolated VLAN/SSID if you can.

## Verification

```bash
ffprobe -v error -rtsp_transport tcp -read_intervals "%+3" \
        -select_streams v:0 -count_frames \
        -show_entries stream=codec_name,width,height,nb_read_frames \
        -of default=noprint_wrappers=1 \
        'rtsp://<ip>:554/user=admin_password=<password>_channel=1_stream=0.sdp?real_stream'
```

A non-zero frame count confirms the new credentials work.

## Validated on the 2024 firmware (V5.01.R02)

Re-tested on a stock unit with firmware `V5.01.R02.000A07F3.10010.346732.0000000`:

| check | result |
|---|---|
| web UI login | `admin` + **blank** password accepted |
| DVRIP (34567) login | `admin` + **blank** password accepted |
| RTSP DESCRIBE with blank password in path | `200 OK` (streams HEVC) |
| ONVIF `GetProfiles` / `GetStreamUri` on `:8899` without auth | answered; URI contains `password=tlJwpbo6` (hard-coded token) |
| telnet 23 / 4321 / 9530 | **closed** |
| vendor debug `/usr/bin/debug` | **12901 open**; RSA vendor handshake, not usable without the vendor private key |
| DVRIP `OPTelnetControl` / `EnableKey` | **decoy**: any key accepted, no listener opened (see [telnet.md](telnet.md)) |
| upgrade manifest | signed (`Mx8Q`), so the old unsigned telnet-opener upgrade is rejected |

This matches the class of **CVE-2026-79394** (RTSP default auth),
**CVE-2026-79395** (ONVIF WSSE empty-password bypass),
**CVE-2026-79396** (hard-coded/default accounts) and **CVE-2025-65857**
(ONVIF `GetStreamUri` hard-coded credential); the same Sofia codebase is also affected by
**CVE-2026-79393** (WS-Addressing heap overflow, unassessed here). See [cves.md](cves.md).

**Consequence:** on a shared LAN, anyone can watch the streams, move the PTZ and read
the configuration with no credentials at all. Treat the camera as untrusted until the
admin password is set and WAN access is blocked.

## Going local-only

There is no single cloud switch in the stock UI. See [cloud-cut.md](cloud-cut.md) for the
tested options (WAN block at the router, PMS disable over DVRIP, static IP caveats).


## Hidden/extra account and cloud channels (2026-11-18)

On a stock unit, DVRIP `System` config contains an **extra user** not visible in the normal
web UI account list:

```json
"ExUserMap": { "UserNum": 1,
  "User": [ { "Name": "twhn", "Password": "", "PasswordV2": "YeRwfERlGFUXJIkMfSCQkQ==" } ] }
```

Who/what created it is unknown (it may be an extended/cloud user). Audit it before
trusting the device; it is a candidate for "unexpected account on the camera".

Other cloud channels seen in config:

- `NetWork.OnlineUpgrade`: `Enable=true`, `AutoCheck=true`, `AutoUpgradeImp=true`,
  `ServerAddr=upgrade.secu100.net`, `ServerPort=8083` — **remote firmware upgrade path**,
  disable it if the camera must stay local.
- `Status.NatInfo`: `{"NaInfoCode":"2:18.195.77.158/1/0/+111","NatStatus":"Conneted"}`
  — the P2P/NAT channel is established while online.
- `NetWork.PMS.Enable=true` → `push.umeye.cn:80` (push/alarms).

None of these are required for local RTSP/ONVIF/web; all are blocked by cutting WAN.
