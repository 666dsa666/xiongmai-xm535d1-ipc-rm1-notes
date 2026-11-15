# Firmware and update

## What this unit runs

From ONVIF `GetDeviceInformation` on `:8899`:

| field | value |
|---|---|
| Model | `XM535_X6E-WEQ_8M` |
| FirmwareVersion | `V5.01.R02.000A07F3.10010.346732.S.ONVIF 21.06` |
| HardwareId | `00001` |

The `000A07F3` build prefix is the Xiongmai product code for the **XM535D1 / X6E-WEQ** family, which is
exactly what the vendor's download site uses to name the firmware.

## Official firmware

Xiongmai's download portal lists this device:

- Page: <https://download.xm030.cn/d/MDAwMDE3NTJ=>
- Version name: `IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.dss.OnvifS_V5.07.X02` (2025-09-06)
- Published: 2025-09-18
- Archive:
  `000A07F3.1IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.OnvifS_V5.00.R02.zip`

The portal warns: **the ZIP is not the upgrade package** — unzip it and use the `.bin` inside.

Other versions circulate in the community thread
[XM535 X6E WEQ Firmware](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/) (V5.00.R02 from
2024-04-18, V5.04, V5.05). There are reports of SD-recording problems on V5.05
("Recording partition error"), so a newer build is not automatically a better one.

## How to update

### 1. Camera web UI (simplest)

1. Open `http://<ip>/` and log in (default `admin`, empty password).
2. Go to the system/settings menu and find **Upgrade** / **Firmware**.
3. Select the `.bin` extracted from the ZIP and start the upgrade.
4. Do not power off for several minutes; the camera reboots by itself.

The web UI is a single-page app (a browser plug-in may be required for live video, but the upgrade page
usually works without it).

### 2. Xiongmai Device Manager (Windows)

The vendor's Device Manager can find the camera on the LAN and perform a firmware upgrade, along with IP
and password changes.

### 3. python-dvr (cross-platform, scriptable)

[`python-dvr`](https://github.com/vklimk/python-dvr) speaks the NETsurveillance/XMeye protocol:

```python
from dvrip import DVRIPCam

cam = DVRIPCam("192.168.0.152", user="admin", password="")
cam.login()
print(cam.get_upgrade_info())
cam.upgrade("IPC_XM535D1_X6E-WEQ_....bin")
```

This is the same class of tool OpenIPC uses to flash coupler images onto Xiongmai boards.

## Before and after

Before:

- Record the current version (`GetDeviceInformation`).
- Save the configuration screens (network, users, encoder) in case they reset.
- If you can obtain the current firmware file, keep it: an older official build is the only rollback path
  on these boards.

After:

- Re-check the version:

  ```
  GetDeviceInformation -> FirmwareVersion
  ```

- Re-check streaming:

  ```bash
  ffprobe -v error -rtsp_transport tcp -read_intervals "%+4" -select_streams v:0 \
          -count_frames -show_entries stream=codec_name,width,height,nb_read_frames \
          -of default=noprint_wrappers=1 \
          'rtsp://<ip>:554/user=admin_password=_channel=1_stream=0.sdp?real_stream'
  ```

- Re-check ONVIF on `:8899` and the web UI login.

## Hacks, mods and root

- **OpenIPC**: `xm535d1_lite` exists but has **no video backend** for the V200 media pipeline
  ("No majestic yet") — see [`openipc.md`](openipc.md). There is no coupler image for XM535D1. Not
  recommended for a camera you want to keep streaming.
- **Telnet/root**: on this unit ports **23** and **4321** are closed, so the usual Xiongmai
  telnet-opener route is not exposed.
- **python-dvr** can query and change settings, and flash firmware, over the DVRIP protocol.
- **No custom RTSP mods are needed**: the stock firmware already serves RTSP and ONVIF locally (see
  [`stock-streaming.md`](stock-streaming.md)).

## Recommendation

If RTSP/ONVIF already work, **do not update** unless you need a specific fix. An update is a one-way risk
on a board with no recovery button, and the current build is doing what you need.
