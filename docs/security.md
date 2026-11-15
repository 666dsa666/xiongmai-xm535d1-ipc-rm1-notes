# Security — default credentials and hardening

## What the stock firmware exposes

| service | port | authentication |
|---|---|---|
| RTSP | 554 | none for the Xiongmai URL form with `password=` empty |
| ONVIF | 8899 | `GetSystemDateAndTime`/`GetProfiles` answer without auth |
| Web UI | 80 | `admin` with empty password |
| Xiongmai P2P | 34567 | cloud/app channel |

The RTSP URL embeds the credentials in the path
(`user=admin_password=<password>_channel=1_stream=0.sdp`), and with the factory default the password field
is empty. Anyone on the LAN can watch the stream.

## Harden it

1. **Open the web UI** (`http://<ip>/`, `admin` / empty) and set a non-empty admin password.
2. **Re-test RTSP** — the URL must then carry the password:
   `rtsp://<ip>:554/user=admin_password=<password>_channel=1_stream=0.sdp?real_stream`
   ONVIF `GetStreamUri` will return the corresponding token.
3. **Keep ports on the LAN**: 80, 554, 8899 and 34567 must never be forwarded from the internet.
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
