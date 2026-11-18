# Cutting the cloud — towards a 100% local camera

Goal: use the XM535D1 as a **LAN-only camera** (RTSP/ONVIF/web), with **no dependency on
Xiongmai's cloud** (`umeye.cn`, TUTK P2P, cloud agent, cloud upgrade, PMS push).

What the stock firmware does at boot (see [firmware-v507.md](firmware-v507.md)):

- starts `Sofia`, which hosts RTSP (554), ONVIF (8899), web UI (80), DVRIP (34567);
- starts the **cloud agent** (`CCloudAgentManager`, RPS config over HTTP);
- starts **PMS push** to `push.umeye.cn` (config `NetWork.PMS`);
- obtains a **TUTK P2P id** (`/mnt/mtd/Log/TUTKID`) and may register with the P2P service;
- can run **cloud upgrade** and **cloud storage** helpers when the app asks for them.

There is no single "cloud off" switch in the web UI or DVRIP config. Cutting the cloud is
therefore done at the network level first, optionally combined with disabling PMS.

## What is independent of the cloud (validated on a stock unit)

These keep working with the camera online and are **LAN services**, not cloud services:

| Service | Test result |
|---|---|
| RTSP `rtsp://<ip>:554/user=admin_password=<pwd>_channel=1_stream=0.sdp?real_stream` | `200 OK`, HEVC 2304×2592, ~25 fps |
| RTSP sub stream (`stream=1`) | HEVC 640×720 |
| ONVIF `:8899` (`GetProfiles`, `GetStreamUri`, PTZ) | answers on LAN (unauthenticated on stock fw) |
| Web UI `http://<ip>/` | login `admin` + blank password |
| DVRIP `:34567` | login `admin` + blank password |
| SD recording | local, no cloud needed |
| Snapshot via ONVIF / RTSP | local |

RTSP even advertises an audio track in its SDP (`m=audio 0 RTP/AVP 8`, PCM A-law), so
audio is available on the local stream when the client supports G.711.

## Cut options (best → worst)

### 1. Router-level WAN block (recommended)

Block the camera's outbound internet access on the router (by IP/MAC or in an isolated
VLAN), **without** blocking LAN traffic to your NVR/PC/HA.

- Pros: reversible, applies to all cloud paths (PMS, TUTK, agent, upgrades), no firmware
  modification, no lockout risk.
- Cons: the camera may retry periodically and log errors; app access stops working.
- Verification from the LAN: RTSP/ONVIF/web/DVRIP work as before; check the router's
  firewall counters/logs to confirm outbound attempts are dropped.

Example (router-side, vendor syntax varies):

```
# block camera MAC from WAN, keep LAN
iptables -I FORWARD -m mac --mac-source 00:12:34:03:5c:f0 -o wan0 -j DROP
```

Also **disable UPnP** on the router: cheap cameras often create their own port mappings
that expose 80/554/8899/34567 to the internet.

### 2. Disable PMS push over DVRIP (tested, reversible)

PMS is the alarm/notification push to `push.umeye.cn`. It can be disabled without any
shell, using the DVRIP protocol (port 34567, `admin` + blank password):

Read:

```json
{"Name": "NetWork.PMS", "SessionID": "0x…"}
→ {"BoxID": "", "Enable": true, "Port": 80, "PushInterval": 10, "ServName": "push.umeye.cn"}
```

Disable (write `Enable=false`, keep the other fields):

```json
{"Name": "NetWork.PMS", "NetWork.PMS": {"BoxID": "", "Enable": false,
 "Port": 80, "PushInterval": 10, "ServName": "push.umeye.cn"}}
→ Ret 100
```

Read-back confirmed `Enable=false`; restoring `Enable=true` also works. This stops the
push channel but does **not** remove the cloud agent or P2P — use it together with
option 1.

### 3. Static IP + unreachable gateway/DNS (camera-side internet cut)

The DVRIP config exposes `NetWork.NetDHCP`, `NetWork.NetDNS` and `NetWork.NetCommon`.
In theory you can turn DHCP off, keep the same LAN IP, and set a gateway/DNS that does
not exist, so the camera keeps working on the LAN but has no route to the internet.

Values are stored byte-swapped (see [firmware-v507.md](firmware-v507.md)):

| Field | Value for this LAN |
|---|---|
| `NetDHCP[0].Enable` | `false` (eth0) |
| `NetWork.NetCommon.HostIP` | `0x9900A8C0` (192.168.0.153) |
| `NetWork.NetCommon.Submask` | `0x00FFFFFF` |
| `NetWork.NetCommon.GateWay` | `0xFE00A8C0` (192.168.0.254 — unused) |
| `NetWork.NetDNS.Address` | unreachable, e.g. `0xFE00A8C0` |

**Not validated end-to-end yet**: while DHCP is enabled, a gateway write is ignored on
this firmware. Turning DHCP off + static IP likely applies only after a **reboot**, and a
mistake can leave the camera on the wrong subnet (factory fallback `192.168.1.10`), which
is harder to recover without UART/console. Do it only with a full flash dump and console
access available; router blocking (option 1) achieves the same result safely.

### 4. Firmware modification / root shell (UART or SPI)

With a root shell (UART auto-login on this board, or SPI dump + repack) one can:

- disable/rename the cloud agent or PMS init in the rootfs;
- add `iptables -o <wan> -j DROP` at boot;
- set `telnetctrl=1` in the U-Boot environment for persistent telnet;
- remove the cloud account binding.

The upgrade path is signed (`Mx8Q`) and the network backdoor (9530/telnet) is closed on
this build, so this is the only way to remove the cloud code itself. It is a real
firmware-modification project, not a setting.

### 5. Unbind from the cloud account

`General.AppBindFlag.BeBinded` is `true` on a unit that has been paired with the app.
Unbinding (through the app or the cloud account) stops app access but does not remove
the cloud agent/P2P stack; the camera still talks to the cloud while online. Use the
app to remove the device if you are decommissioning it, then apply option 1.

## Recommended recipe for a local-only camera

1. Set a **strong admin password** in the web UI (affects the RTSP path password too).
2. Disable UPnP on the router and make sure **no port forwarding** exists for the camera.
3. Put the camera on an isolated VLAN/SSID or block its **WAN** access (option 1).
4. Optionally disable **PMS** over DVRIP (option 2).
5. Keep RTSP/ONVIF on the LAN; use `rtsp://<ip>:554/...` or ONVIF in your NVR/Home
   Assistant.
6. Verify: `ffprobe` on the RTSP URL, ONVIF `GetProfiles`, web UI, DVRIP login, SD
   recording; check the router log for blocked outbound attempts.

## Verification commands

```bash
# main stream, should print hevc + frames
ffprobe -v error -rtsp_transport tcp -read_intervals "%+3" -select_streams v:0 \
  -count_frames -show_entries stream=codec_name,width,height,nb_read_frames \
  -of default=noprint_wrappers=1 \
  'rtsp://<ip>:554/user=admin_password=<pwd>_channel=1_stream=0.sdp?real_stream'

# ONVIF device info
curl -s http://<ip>:8899/onvif/device_service -H 'Content-Type: application/soap+xml' \
  --data '<?xml version="1.0"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><GetDeviceInformation xmlns="http://www.onvif.org/ver10/device/wsdl"/></s:Body></s:Envelope>'
```

## Open questions / next steps

- Confirm on-device that `NetWork.PMS.Enable=false` persists across a reboot.
- Validate the static-IP/no-gateway path on a unit with UART recovery available.
- Check whether the cloud agent stops retrying after a WAN block or keeps hammering DNS
  (observation only; it has no effect on LAN streaming).
- For true "100% local" without router involvement: firmware patch or local firewall
  rules from a root shell.
