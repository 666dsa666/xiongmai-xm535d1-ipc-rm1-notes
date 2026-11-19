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
6. If the camera is rooted (see [upgrade-root.md](upgrade-root.md)), the full validated
   hardening recipe — extra-account removal, ONVIF password checkout, PMS/NAT/online
   upgrade off, `9530Disable`, firewall — is in [hardening.md](hardening.md).

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
| upgrade manifest | **V5.01 accepts a modified/unsigned package**: a `Shell` command is executed as root and a custom `user` partition is flashed. This is the confirmed root path — see [upgrade-root.md](upgrade-root.md). The official V5.07 metadata checks are stricter and were not hardware-tested with a modified payload |

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

## Legacy HTTP JSON bridge — admin auth bypass and file read (2026-11-18)

On V5.01, the web server exposes a **legacy JSON bridge** below `/cgi-bin/`
(`getinfo.cgi`, `getconfig.cgi`, `getability.cgi`, `getdefault.cgi`,
`usermanager.cgi`, `getlog.cgi`, `opdev.cgi`). It parses `Name`, `UserName` and
`Password` from a JSON body and dispatches an internal DVRIP operation **without**
performing the RSA web login. With the factory state (`admin` has an empty password),
`UserName=admin` plus **any/empty** `Password` returns `Ret 100` and full admin RPC:

```http
POST /cgi-bin/usermanager.cgi
{"Name":"GetAllUser","UserName":"admin","Password":""}
```

Consequences observed on a stock unit:

- `/cgi-bin/usermanager.cgi` returns all accounts **with plaintext `Password` fields**
  (including the extra/hidden account — see above);
- **`ConfigExport`** (`opdev.cgi`, `{"Name":"ConfigExport","DataType":"Config",...}`)
  returns a base64 ZIP of `/mnt/mtd/Config`: accounts, network/DHCP/resolv, all
  `Json/*` tables, logs, and **`wpa.conf` with the home Wi-Fi SSID and PSK in clear**;
- DVRIP still accepts `admin`/empty for the same admin operations, and DVRIP messages
  1482/1486/1488 can add/delete users and change the admin password.

Treat this as a **credential/config disclosure** vulnerability. If you have run an
affected camera on a network with real credentials, **rotate the Wi-Fi PSK and any
reused admin password**, and do not expose port 80.

### `ConfigImport` — root file write

The write half of the same mechanism (`ConfigImport`, DVRIP msg 1540, raw ZIP body)
extracts a ZIP into `/var/config_tmp` and then into `/mnt/mtd/Config`. ZIP entries with
`../` escape the target directory and are written **as root** under `/mnt/mtd` (JFFS2,
persistent). Demonstrated in QEMU with a marker file and a replaced `Config/Account1`.

Do **not** send `ConfigImport` to a camera you cannot restore: entries such as
`../../dev/mtd0` or `../../dev/mtdblock0` overwrite the boot partition and **brick**
the unit (verified on a QEMU image: U-Boot no longer starts). This primitive is a
root-write/DoS issue, not a shell by itself; it is documented here because it is part of
the same unauthenticated admin surface.

## Rooted camera: the 2323 shell

The unsigned-upgrade root path ([upgrade-root.md](upgrade-root.md)) leaves an
**unauthenticated root shell on TCP 2323**. That is a deliberate management backdoor
while experimenting, not a production configuration:

- never port-forward 2323; firewall it to a single management host;
- keep the camera on an isolated VLAN/SSID;
- after the experiment, restore the official `user` partition or replace the daemon with
  an authenticated service;
- also create `/mnt/mtd/Log/9530Disable` to keep the vendor debug service (12901) off at
  boot.
