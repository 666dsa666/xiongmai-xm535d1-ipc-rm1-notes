# Hardening and local-only operation

DVRIP settings that turn a stock or rooted camera into an authenticated, local-only device;
the cloud cut; time/NTP configuration; local controls (PTZ, flip, audio); VMS setup.
The production image ([production.md](production.md)) assumes these settings.

Validated on V5.01 (**HW**, one camera) and on the V5.07 production fleet (**HW**, cam1,
cam2, cam3) unless marked otherwise.

## Admin password

The factory admin password is empty, which also opens the legacy HTTP bridge
([security.md](security.md#non-cve-findings)). DVRIP msg **1488** changes it; the fields are
stored `sofia_hash` values, not plaintext. Example with the `python-dvr` `DVRIPCam` client
([firmware.md](firmware.md#update-methods)):

```python
from dvrip import DVRIPCam
ip = "<camera-ip>"
new_plaintext = "<new-admin-password>"
cam = DVRIPCam(ip, user="admin", password="")   # factory state
cam.login()
old_stored = "tlJwpbo6"                         # sofia_hash("")
new_stored = cam.sofia_hash(new_plaintext)
cam.send(1488, {
    "EncryptType": "MD5",
    "NewPassWord": new_stored,
    "PassWord": old_stored,
    "SessionID": "0x%08X" % cam.session,
    "UserName": "admin",
})
```

The RTSP URL then carries the password (plaintext or stored hash):
`rtsp://<camera-ip>:554/user=admin_password=<password>_channel=1_stream=0.sdp?real_stream`.
Change the admin password first, before any other setting.

## Service account

Cloud pairing creates a second admin account (one per camera, the login differs per unit),
present in `System.ExUserMap` and in the user list. It is not a user-created backdoor.

- Do **not** delete it: on V5.07 `DelUser` returns `Ret 101` (on V5.01 deletion may work but
  is unnecessary).
- Neutralise it: group `user` and a strong random password (msg 1488 path).
- Do **not** use it for VMS (see [VMS setup](#vms-setup)).
- Identify it with DVRIP `getUsers` (the second admin account). Re-check it after a cloud
  re-pairing, which may recreate or reset it.

```python
cam.getUsers()
cam.modifyUser("<service-account>", group="user")
```

## DVRIP settings

Read the whole `NetWork` object, change the fields, write the **whole object** back
(`set_info("NetWork", nw)` → `Ret 100`), re-read it, then reboot from a root SSH session
(`sync; reboot`) or wait for the JFFS2 flush before any power cut.

| Field | Value | Effect |
|---|---|---|
| `NetWork.PMS.Enable` | `false` | stops push/alarms to `push.umeye.cn` |
| `NetWork.Nat.NatEnable` | `false` | stops the NAT/P2P channel |
| `NetWork.OnlineUpgrade.Enable` | `false` | blocks cloud-triggered upgrades (`upgrade.secu100.net:8083`; downloads use 9083, see [firmware.md](firmware.md#ota-and-official-updates)) |
| `NetWork.OnlineUpgrade.AutoCheck` | `false` | |
| `NetWork.OnlineUpgrade.AutoUpgradeImp` | `false` | |
| `NetWork.DisableXmServerConn` | `{"DisableAll":true,"DisableDSS":true,"DisableNAT":true,"DisableRPS":true}` | disables vendor server connections |
| `NetWork.OnvifPwdCheckout.Enable` | `true` | ONVIF requires WS-Security credentials |
| `NetWork.NetNTP.Enable` | `true`, public servers | deliberate exception to the cloud cut; see [Time and NTP](#time-and-ntp) |
| `Ability.TelnetDebugMode.Open` | `false` | default; setting `true` had no visible effect on any port (**HW**) |
| `/mnt/mtd/Log/9530Disable` (file, needs root) | present | `/usr/bin/debug` exits at boot (`LIBDVR : Debug: is Disabled!`); the production boot hook creates it |

Without the production image, create the marker from a root shell:

```sh
touch /mnt/mtd/Log/9530Disable
killall debug 2>/dev/null
```

Not exposed over DVRIP: `System.Cloud` is null; `NetWork.NetP2P`, `NetWork.P2P`,
`NetWork.TUTK`, `NetWork.RPS` return `Ret 607`. No setting disables the web server
(`NetWork.NetCommon.HttpPort` is cosmetic); port 80 is closed by the production block80 shim.

### Verification

| Check | Before | After |
|---|---|---|
| Admin password | empty | strong; empty/old refused on DVRIP |
| Users | admin + service account (admin group) | admin + service account (group `user`, random password) |
| RTSP with empty password | `200` | `401` |
| RTSP with new password or stored hash | — | `200` |
| ONVIF `GetProfiles` unauthenticated | `200` | `401 NotAuthorized` |
| `/webcapture.jpg` unauthenticated | `200` | `401` (port 80 closed with block80) |
| Legacy HTTP bridge, any password | `Ret 100` (bypass) | `Ret 203 Pwd error` for any non-empty password, including the correct one (port 80 closed with block80) |
| PMS / NAT / online upgrade | on | off |
| NTP | on (`time.windows.com`) | on (public servers) |
| 12901 / 9530 / 23 | closed | closed |

All values persist across reboot (**HW**). A factory reset restores the vendor defaults;
re-apply and re-verify.

## Local-only operation

### Cloud components on stock

At boot `Sofia` hosts RTSP (554), ONVIF (8899), web (80) and DVRIP (34567), and also starts
the cloud agent (`CCloudAgentManager`, RPS config over HTTP), PMS push, a TUTK P2P id
(`/mnt/mtd/Log/TUTKID`) and, on app request, cloud upgrade and cloud storage helpers. There is
no single "cloud off" switch. `General.AppBindFlag.BeBinded` is `true` on a paired unit;
unbinding from the app stops app access but not the cloud stack.

LAN services that do not need the cloud (**HW**): RTSP main (HEVC 2304×2592, 12 fps measured) and sub
(HEVC 640×720), RTSP audio (PCM A-law, `m=audio 0 RTP/AVP 8`), ONVIF including PTZ, DVRIP,
SD recording, snapshots.

### Options tested

| Option | Status | Result |
|---|---|---|
| DVRIP `NetWork.PMS.Enable=false` | **HW** | read-back `false`, persists across reboot, reversible; stops push only |
| DVRIP `NetWork.OnlineUpgrade` off | **HW** | blocks cloud-triggered upgrades |
| DVRIP `Nat`, `DisableXmServerConn` | **HW** | applied on the fleet; VMS unaffected |
| Router WAN block (by MAC or VLAN) | recommended | the only cut that covers the cloud agent and TUTK, which have no DVRIP switch |
| Static IP + unreachable gateway/DNS | **UNTESTED** | gateway writes are ignored while DHCP is on; a wrong static config can strand the camera (factory fallback `192.168.1.10`) with no console to recover |
| Firmware modification | not used | the production image keeps the vendor cloud code in `Sofia`; the fleet relies on the DVRIP switches and the egress block |

Static-IP fields, for reference: `NetDHCP[0].Enable=false`, `NetWork.NetCommon.HostIP`,
`Submask`, `GateWay`, `NetWork.NetDNS.Address`. Values are stored byte-swapped
(`192.168.1.10` → `0x0A01A8C0`).

### Working recipe

1. Strong admin password ([Admin password](#admin-password)).
2. Service account neutralised ([Service account](#service-account)).
3. DVRIP settings table applied and re-read; reboot.
4. Router: disable UPnP, no port forwarding, block camera egress except NTP (UDP 123):

   ```
   # router side, syntax varies; keep LAN traffic
   iptables -I FORWARD -m mac --mac-source <camera-mac> -o wan0 -j DROP
   ```

   Insert an NTP accept rule before the drop if the camera uses public NTP.
5. Isolated VLAN/SSID where possible; restrict 2222/34567/8899/554 to the clients that need
   them ([security.md](security.md#residual-risks)).

### Verification

```bash
# main stream: prints hevc + a non-zero frame count
ffprobe -v error -rtsp_transport tcp -read_intervals "%+3" -select_streams v:0 \
  -count_frames -show_entries stream=codec_name,width,height,nb_read_frames \
  -of default=noprint_wrappers=1 \
  'rtsp://<camera-ip>:554/user=admin_password=<password>_channel=1_stream=0.sdp?real_stream'

# ONVIF device info (401 without WS-Security once OnvifPwdCheckout=true)
curl -s http://<camera-ip>:8899/onvif/device_service -H 'Content-Type: application/soap+xml' \
  --data '<?xml version="1.0"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><GetDeviceInformation xmlns="http://www.onvif.org/ver10/device/wsdl"/></s:Body></s:Envelope>'
```

Also check DVRIP login, a new recording file, and the router counters for dropped outbound
attempts. Open question: whether the cloud agent stops retrying after a WAN block (no effect
on LAN service).

## Time and NTP

Canonical time configuration for this board (**HW**, all three cameras).

- **No RTC**: no `/dev/rtc*`, no RTC driver, `hwclock` fails. `Sofia` saves the clock to
  `/mnt/mtd/Config/SysTime` (JFFS2) and restores it at boot (`RecoverTime`): the time
  survives a reboot but not a power-off, and saving lags.
- The SNTP client is inside `Sofia`, driven by `NetWork.NetNTP`; there is no `ntpd`/`ntpdate`
  applet. `UpdatePeriod` is in minutes (default 10). Stock default server: `time.windows.com`.
- `NetNTP.Enable` is a separate switch: VMS can fill `Server`/`NtpServerList` while leaving
  `Enable=false`, and then nothing syncs. Enable it explicitly.
- Fleet setting: NTP on with public servers (`time.cloudflare.com`, a regional `pool.ntp.org` zone). Proof of sync:
  `NTPD: UpdateTime …` in `/var/sofia.log`.

**Correct combination** (written by the VMS time configuration):

| Field | Value |
|---|---|
| `/mnt/mtd/Config/localtime` | `GMT-1` TZif |
| `System.TimeZone.timeMin` | `-60` |

With both, the live clock, SSH `date` and new recording files are correct. Change neither
alone. Observed wrong combinations:

| `localtime` | `timeMin` | Result |
|---|---|---|
| `GMT` | `-60` | live correct, new recordings stamped +1 h |
| `GMT` | `0` | app and recordings 1 h behind |

Files already written keep their bad timestamps until deleted or the card is formatted.

Other rules:

- `NetNTP.TimeZone` is an index in `[0,33]`, separate from `System.TimeZone.timeMin`; the ONVIF
  timezone string was `CET-1CEST`. Do not deduce the wall clock from these alone.
- The root shell's `TZ` comes from `/mnt/mtd/Config/localtime`; SSH `date` can differ from the
  application. Use VMS, ONVIF or `OPTimeQuery` as the reference.
- Manual setters: ONVIF `SetSystemDateAndTime` with WS-UsernameToken and explicit UTC is exact
  to ~1 s (preferred fallback). DVRIP `OPTimeSetting` (msg 1450) on V5.07 applies the +1 h
  offset twice (clock 1 h slow); verify with `OPTimeQuery` and a new file timestamp.

## Local options

Native camera behaviour, independent of VMS/cloud (**HW**, cam2, V5.07 production).

### PTZ

- 305° × 113° pan/tilt head.
- ONVIF PTZ works: node `NODE_000`, `ContinuousMove` speed 1..8, then `Stop`. `GetStatus` is
  stubbed (-1/-1).
- DVRIP `OPPTZControl` (msg 1400) returns `Ret 100` but does not move the head.
- `Ptz.GunBallLocate.motorSpeedX/Y` (13/9) are persisted values; the ONVIF speed is the
  per-command layer. `ResumePtzState` exists, default off.

### Image

- `Camera.Param.PictureFlip` / `PictureMirror` = `0x1` work and persist.
- `CorridorMode=1` is accepted with no visual effect.

### Audio

| Field | Meaning | Default |
|---|---|---|
| `fVideo.Volume` | speaker (`XM_MPI_AO_SetVolume`) | 50/50 |
| `fVideo.VolumeIn` | microphone (`XM_MPI_AI_SetVolume`) | 34/35 |

DVRIP msgs 1040/1042 write/read them; values persist. RTSP audio is PCM A-law 8 kHz mono.
Two-way talk was not tested.

### Web UI and local control

The web UI is only a login shell for the Windows VideoPlayTool ActiveX plugin
(`ocx.jftechws.com`); it has no native HTML settings and is not needed. Local control paths:
DVRIP 34567, ONVIF 8899 (WS-Security), RTSP 554, SSH 2222. A local UI is better hosted off
the camera (Home Assistant/PC bridge); the block80 production `user` partition has about 188 KiB free
([production.md](production.md#image-content)).

## VMS setup

Tested with VMS 2.0.28.1 (see [Glossary](../README.md#glossary)) against V5.07.X02 (**HW**, with
reboot). The VMS and app UI used here were in French; quoted UI strings are given in French
with an English translation.

| Field | Value |
|---|---|
| Type | `"Adresse IP"` (IP address) |
| IP | `<camera-ip>` |
| Port | `34567` |
| User | **`admin`** |
| Password | admin password |

### Service-account trap (error 607)

VMS may use the account it was given for its GetConfig path. If that is the neutralised
service account, live view and storage still work but VMS shows:

- `"Version du système — Obtenir la configuration — Erreur inconnue-607"` (system version, get
  configuration, unknown error 607);
- the same 607 on the stream/encoder page;
- sometimes a misleading `"Pas d'alimentation"` (no power).

Fix: `"Gestion des appareils"` (device management) → edit the device connection → User
`admin` with the admin password.

Isolation on stock V5.07, one change at a time:

| Change | VMS version/config page |
|---|---|
| stock, admin empty | works |
| `Nat.NatEnable=false` | works |
| `DisableXmServerConn` all true | works |
| PMS + OnlineUpgrade off | works |
| strong admin password | works |
| production firmware (root/SSH) | works |
| `OnvifPwdCheckout=true` | works |
| service account downgraded to `user` | **607** |

The cause is the VMS account choice, not the cloud cut, the firmware or the admin password.
SD formatting through VMS creates the WFS layout; see [quirks.md](quirks.md).
