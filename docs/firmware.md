# Firmware

Official firmware for the `XM535_X6E-WEQ_8M` family: builds and hashes, package format,
integrity checks, stock services, cloud components, update methods and OTA behaviour.
Root and production images: [root.md](root.md), [production.md](production.md).

## Identification

ONVIF `GetDeviceInformation` on TCP 8899 (stock, no authentication required):

| Field | Value |
|---|---|
| Manufacturer | `H264` |
| Model | `XM535_X6E-WEQ_8M` |
| FirmwareVersion | `V5.01.R02.000A07F3.10010.346732.S.ONVIF 21.06` (shipping build) |
| HardwareId | `00001` |

`000A07F3` is the Xiongmai product code of the XM535D1 / X6E-WEQ family; the vendor download
site names the firmware with it.

## Official builds

| Build | Package | SHA-256 (outer file) | U-Boot build | Notes |
|---|---|---|---|---|
| `V5.00.R02` (2024-04-18) | `...V5.00.R02.20240418.zip` | `0db884f68be6dc6eb78203281f1002644948df35d5562a0497ef0c36438507bc` | `Mar 11 2024` | oldest public build found |
| `V5.01.R02` (2024-09-14) | `...V5.01.R02...20240914_all.bin` | `53aa58d3498eb43362ac65a8b886ea9d1213f1688abf1c020e0450f301a90005` | `Apr 26 2024` | shipping build; kernel `#27` (Aug 1 2024) |
| `V5.02.R02` + `V5.04.R02` | `...V5.02.R02_5.04.R02.zip` | `6d7cb8c098f309a1d3c2abab2fce622fa0e392f820bf9333d16693a227b2485c` | `Dec 13 2024` | two inner images |
| `V5.07.X02` (2025-09-06) | vendor portal ZIP | `f9ed99f370953ef59e41a7e7656a2594854adf806b57029de3d883c7dd67a5e2` | `Aug 18 2025` | latest official; kernel `#84`; also in `OpenIPC/xmupdates` |

Sources:

- vendor portal: <https://download.xm030.cn/d/MDAwMDE3NTJ=> — version name
  `IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.dss.OnvifS_V5.07.X02`, published
  2025-09-18;
- direct URL (7,561,447 bytes):
  <https://obs-xm-customer.obs.cn-east-2.myhuaweicloud.com/000A07F3.1IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.OnvifS_V5.00.R02.zip>
  (the archive name says `V5.00.R02`; the content is `V5.07.X02`);
- older builds: community thread
  [XM535 X6E WEQ Firmware](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/)
  (V5.00, V5.01, V5.04, V5.05, V5.07). V5.05 is reported there to break SD recording
  ("Recording partition error").

The vendor ZIP is not the upgrade file: unzip it and use the `.bin` inside. This repository does
not redistribute vendor firmware.

Cross-build facts (**STATIC**):

- `/usr/bin/debug` (TCP 12901) is byte-identical across V5.00–V5.07 (SHA-256
  `c9f140e1d69c8c2e3f5e3bb3e3530e0298fb0b64910aa45043dd4d16a77f0816`; the MD5 of the same
  file is given in debug-services.md)
  ([debug-services.md](debug-services.md));
- `Sofia` differs between V5.01 and V5.07 (SHA-256 prefixes `4d43505c…` vs `532045f0…`;
  [quirks.md](quirks.md) quotes MD5 prefixes for V5.04 → V5.07) but carries the
  same telnet strings: `OPTelnetControl`, `TelnetEnable`, `EnableKey`, `GetSaftyCode`,
  `%sHk2W#5%d%d%d`, `/var/T8aYMi2q`;
- every U-Boot build (2024-03 to 2025-08) has the `Password:` gate; downgrading to V5.00 does
  not unlock the bootloader.

## Package format

The `.bin` is a ZIP-like container of U-Boot legacy uImages (64-byte header + payload) plus the
`InstallDesc` manifest. V5.07.X02 manifest:

```
Hardware        = XM535_X6E-WEQ_8M
DevID           = 000A07F31001000003200000
WifiDriverType  = atbm6012b
CompatibleVersion = 3
Vendor          = General
CRC             = 395905494066
Mx8Q            = mK6dK2cGbICnsCr+y6AaekSbV80iEhoC8YWBZSYvTjnjAY/mQr4z4gRWzikGkgS6…
UpgradeCommand  = Burn u-boot.bin.img, u-boot.env.img, custom-x.cramfs.img,
                  uImage.img, romfs-x.cramfs.img, user-x.cramfs.img
```

All builds share `Hardware` and `DevID`.

| File | Payload |
|---|---|
| `u-boot.bin.img` | U-Boot |
| `u-boot.env.img` | U-Boot environment |
| `custom-x.cramfs.img` | CRAMFS v2, `/mnt/custom` (vendor strings, JSON configs) |
| `uImage.img` | Linux kernel |
| `romfs-x.cramfs.img` | CRAMFS v2, read-only rootfs (BusyBox, init scripts) |
| `user-x.cramfs.img` | SquashFS 4.0 (xz), `/usr`: application and web UI |

Flash placement of each file: [hardware.md](hardware.md#spi-flash-layout).

Extraction:

```bash
dd if=romfs-x.cramfs.img bs=64 skip=1 of=romfs.cramfs   # strip the uImage header
cramfsck -x romfs_dir romfs.cramfs                       # extract CRAMFS (util-linux)
dd if=user-x.cramfs.img bs=64 skip=1 of=user.sqfs       # strip the uImage header
unsquashfs -d user_sq user.sqfs                          # extract /usr
```

These are generic commands (**UNTESTED** as written); the original extraction used an
unpublished Python CRAMFS extractor and a Python slice of the first 64 bytes.

The CRAMFS/SquashFS payloads are not compressed by the uImage layer. `uImage.img` is itself a
container: the outer uImage (flagged gzip, not actually gzip) holds the real kernel uImage
(load address `0x80008000`) ([emulation.md](emulation.md)).

## Integrity check (Mx8Q, CRC)

The `Mx8Q` signature and CRC checks are compiled in but not enforced on any build:

- `CUpgrader` sets the CRC/Mx8Q flags to 0 in its constructor; the setters have no direct
  callers and are reachable only through vtable slots that nothing invokes; `VerifyMx8QSign` is never reached (**STATIC**, **QEMU**);
- V5.04 adds a flag-gated CRC read; V5.07 refactors metadata/partition checks
  (`CUpgrader::doMetadataCheck`); neither authenticates the package;
- uImage header CRCs are still checked structurally;
- a modified package with a replaced `user` partition is accepted with `Ret 515` on V5.01 and
  V5.07 (**HW**).

Consequences: root via unsigned upgrade ([root.md](root.md)); free downgrade/upgrade between
official builds with configuration preserved (**HW**). A future vendor build may enforce the
check.

## Stock services

Stock `V5.01.R02`, no modification. Exposure and fixes: [security.md](security.md),
[hardening.md](hardening.md).

| Port | Service | Notes |
|---|---|---|
| TCP 80 | HTTP web UI | title `Web Viewer`; default login `admin`, empty password |
| TCP 554 | RTSP | `Server: H264DVR 1.0` |
| TCP 8899 | ONVIF | `Server: hsoap/2.8` (happytimesoft) |
| TCP 34567 | DVRIP (NETsurveillance/XMeye) | mobile app, Device Manager, `python-dvr` |
| TCP 23, 4321, 9530 | closed | no telnet ([negative-results.md](negative-results.md)) |

### RTSP

A plain `DESCRIBE rtsp://<camera-ip>:554/` returns `401 Unauthorized` with Digest. The Xiongmai
form embeds the credentials in the path and returns `200 OK` (empty `password=` = default blank
password):

```
rtsp://<camera-ip>:554/user=admin_password=_channel=1_stream=0.sdp?real_stream   main
rtsp://<camera-ip>:554/user=admin_password=_channel=1_stream=1.sdp?real_stream   sub
```

Main-stream SDP:

```
m=video 0 RTP/AVP 98
a=rtpmap:98 H265/90000
a=fmtp:98 profile-id=010101; sprop-pps=…; sprop-sps=…; sprop-vps=…
a=framerate:25
m=audio 0 RTP/AVP 8        ; PCM A-law
```

| Stream | Codec | Resolution | Frames in 5 s |
|---|---|---|---|
| `stream=0` | HEVC | 2304×2592 | 60 (12 fps) |
| `stream=1` | HEVC | 640×720 | 60 (12 fps) |

The SDP advertises `a=framerate:25`, but the measured rate is 12 fps, which matches the DVRIP
`AVEnc.Encode` value read on stock V5.01 (H.265 "6M" main stream, 12 fps) (**HW**).

The capability set reports a two-sensor head (`SupportGunBallTwoSensorCamera`), and RTSP/ONVIF
expose channels 0 and 1 that both move with the PTZ (**HW**). A height of 2592 = 2 × 1296 is
consistent with two 2304×1296 images stacked in one frame; this layout and the per-sensor
resolution are not verified. The `2M6P` board suffix does not describe the stream size.

HEVC decoders may log `Could not find ref with POC …` when attaching mid-GOP; playback starts at
the next IDR.

Check:

```bash
ffprobe -v error -rtsp_transport tcp -read_intervals "%+5" -select_streams v:0 \
        -count_frames -show_entries stream=codec_name,width,height,nb_read_frames \
        -of default=noprint_wrappers=1 \
        'rtsp://<camera-ip>:554/user=admin_password=_channel=1_stream=0.sdp?real_stream'
```

Expected: `hevc`, a real resolution, a non-zero frame count.

### ONVIF

Endpoints: `http://<camera-ip>:8899/onvif/device_service` and `/onvif/media_service`. On stock
V5.01, `GetSystemDateAndTime`, `GetDeviceInformation`, `GetProfiles` and `GetStreamUri` answer
without authentication (**HW**).

| Token | Name | Encoding | Resolution |
|---|---|---|---|
| `000` | mainStream | H264 | 3072×2048 |
| `001` | subStream | H264 | 800×448 |
| `002` | snapStream | JPEG | 800×448 |

`GetStreamUri` returns:

```
rtsp://<camera-ip>:554/user=admin_password=tlJwpbo6_channel=0_stream=0&onvif=0.sdp?real_stream
rtsp://<camera-ip>:554/user=admin_password=tlJwpbo6_channel=0_stream=1&onvif=0.sdp?real_stream
rtsp://<camera-ip>:554/user=admin_password=tlJwpbo6_channel=0_stream=2.sdp?real_stream
```

`tlJwpbo6` is `sofia_hash` of the empty password; the URIs play as-is
([security.md](security.md)). The advertised ONVIF encoding (H.264 3072×2048) does not match
the actual RTSP stream (HEVC 2304×2592); trust SDP/ffprobe for the codec and size, and the
frame count for the rate.

## Cloud components in the stock firmware

`custom/CustomConfig/NetWork.custom`:

```json
"PMS": { "Enable": true, "ServName": "push.umeye.cn", "Port": 80, "BoxID": "" },
"NetNTP": { "Enable": true, "Server": { "Name": "time.windows.com", "Port": 123 } }
```

`Sofia` (`/usr/bin/Sofia`) also contains (**STATIC**):

- `CCloudAgentManager` (RPS/cloud agent, HTTP `GetRpsconfig`);
- `CCloudAlarmCli` (PMS alarm push, AI/cloud storage abilities);
- `DssVideoHelper`, `DssAudioHelper`, `CDssPushHelper`;
- `CXmCloudUpgrade`, `OnCloudUpgrade` (cloud-triggered firmware update);
- `/mnt/mtd/Config/CloudDNS.conf`, `CloudAvailDNS.conf`, `cloudExAbility`, `cloudupgradeimp.flag`;
- `/mnt/mtd/Log/TUTKID` (ThroughTek/Kalay P2P device ID);
- `Ability.TelnetDebugMode`, `/mnt/mtd/Log/9530Disable`.

There is no single cloud switch: PMS push, cloud agent/RPS, TUTK P2P and cloud upgrade/storage
are separate. Cutting them: [hardening.md](hardening.md).

### DVRIP configuration blocks

With `admin` and the blank password on DVRIP TCP 34567 (stock, **HW**):

| Config | Content |
|---|---|
| `NetWork.PMS` | `Enable`, `ServName=push.umeye.cn`, `Port`, `PushInterval`; writable |
| `NetWork.NetDHCP` | DHCP enable per interface |
| `NetWork.NetDNS` | primary/spare DNS |
| `NetWork.NetCommon` | IP/mask/gateway/ports (gateway DHCP-managed while DHCP is on) |

`NetWork.NetP2P`, `NetWork.P2P`, `NetWork.TUTK`, `NetWork.RPS` and `NetWork.Cloud` return
`Ret 607` (unknown config): P2P is handled inside `Sofia`.

IP addresses are stored as byte-swapped hex:

| Address | Stored as |
|---|---|
| `192.168.1.1` | `0x0101A8C0` |
| `192.168.1.254` | `0xFE01A8C0` |
| `255.255.255.0` | `0x00FFFFFF` |

## Update methods

Any official `.bin` (extracted from the vendor ZIP) can be applied by:

1. **Web UI**: `http://<camera-ip>/`, log in, system menu, **Upgrade**, select the `.bin`. Do not
   power off; the camera reboots by itself. The upgrade page works without the browser plug-in.
2. **Xiongmai Device Manager** (Windows): LAN discovery, firmware upgrade, IP and password changes.
3. **[`python-dvr`](https://github.com/NeiroNx/python-dvr)** (module `dvrip`) over DVRIP:

   ```python
   from dvrip import DVRIPCam

   cam = DVRIPCam("<camera-ip>", user="admin", password="")
   cam.login()
   print(cam.get_upgrade_info())
   cam.upgrade("IPC_XM535D1_X6E-WEQ_....bin")
   ```

There is no recovery button and no SD recovery mode. The only low-level rollback is the SPI clip
([recovery.md](recovery.md)).

Before an update: record `FirmwareVersion`, save the network/users/encoder configuration, keep the
current firmware file. After: re-check `GetDeviceInformation` → `FirmwareVersion`, the RTSP
`ffprobe` above, ONVIF on TCP 8899 and the web login.

## OTA and official updates

On stock V5.01, the iCSee app (`com.xm.csee`) shows only a generic dialog without a version:
"Important ! N'exécutez pas d'autres actions pendant la mise à niveau / Mettre à niveau ?"
(Important! Do not perform other actions during the upgrade / Upgrade?).

Flow (**HW**):

- the camera has `NetWork.OnlineUpgrade` enabled (configured server `upgrade.secu100.net`,
  port 8083) and a cloud connection (PMS/NAT/RPS);
- the app sends the request through the cloud/P2P channel;
- the camera queries the OTA service and writes the URL to `/mnt/mtd/Log/ota_info.txt`
  (readable with root);
- on confirmation the camera itself downloads the `_all.bin` and runs the normal `CUpgrader`
  flow. Phone-side traffic never contains the firmware URL.

Observed URL:

```
https://upgrade.secu100.net:9083/download?devId=<devId>&ver=2025-09-06&file=General_IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.dss.OnvifS_V5.07.X02.20250906_all.bin
```

The configured port (8083) and the download URL port (9083, HTTPS) differ. A split between a
version-query service on 8083 and a download service on 9083 is the likely reading; it is not
verified from traffic.

The OTA build is `V5.07.X02` (2025-09-06), the same package as the vendor portal (SHA-256
`f9ed99f3…`). No newer build exists at the time of writing.

Effect on a rooted camera: an official update rewrites `/usr` and removes the custom root and
SSH; configuration is kept. Because `Mx8Q`/CRC is not enforced on V5.07, the production package
can be re-flashed to regain root (**HW**). If a future build enforces the check, this path may
close. The fleet has online upgrade disabled ([hardening.md](hardening.md)).

Capturing a future OTA package:

1. Take a full 8 MiB SPI dump, twice ([recovery.md](recovery.md)).
2. With root, read `/mnt/mtd/Log/ota_info.txt` to get the URL without updating.
3. Optionally trigger the update from the app, then dump the flash again.
4. Compare partitions with the pre-update dump; keep both.
5. Restore the pre-update dump (SPI) or re-flash a package if needed.

## Alternative firmware

OpenIPC `xm535d1_lite` has no video backend for this SoC; see
[negative-results.md](negative-results.md).
