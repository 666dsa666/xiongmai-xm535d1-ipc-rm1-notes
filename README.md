# Xiongmai XM535D1 — IPC-RM1-BLK535-2M6P board notes

Notes for a no-name 2 MP PTZ camera built on the Xiongmai **XM535D1** SoC and the
**`IPC-RM1-BLK535-2M6P V1.03`** board (dated `X-20240827`).

> **Status: no modification needed.** The stock firmware already exposes RTSP and ONVIF on the LAN, and
> both streams carry video with the default credentials. OpenIPC can boot on this SoC but has **no video
> backend** for it, so it is not a useful replacement here.

## Board

| field | value |
|---|---|
| Board | `IPC-RM1-BLK535-2M6P V1.03` (silkscreen), `X-20240827` |
| SoC | Xiongmai **XM535D1** (dual-core 32-bit DSP, Cortex-A5 class, H.265X) |
| Firmware | `V5.01.R02.000A07F3.10010.346732.S.ONVIF 21.06` |
| Model string | `XM535_X6E-WEQ_8M` (from ONVIF `GetDeviceInformation`) |
| Flash | Winbond **W25Q128** family, 16 MB SPI NOR |
| Lens / sensor | 2 MP, 6 mm (`2M6P`) |
| PTZ | 2 stepper motors, ULN2803A driver |
| Storage | microSD slot |
| Stock ports | 80 (Web Viewer), 554 (RTSP), 8899 (ONVIF), 34567 (Xiongmai P2P) |

## It already streams — with the default credentials

```
rtsp://<ip>:554/user=admin_password=_channel=1_stream=0.sdp?real_stream    main
rtsp://<ip>:554/user=admin_password=_channel=1_stream=1.sdp?real_stream    sub
```

Observed with `ffprobe -rtsp_transport tcp`:

| stream | codec | resolution | frames |
|---|---|---|---|
| `stream=0` | HEVC | 2304×2592 | 60 / 5 s |
| `stream=1` | HEVC | 640×720 | 60 / 5 s |

ONVIF also works unauthenticated on `:8899` (`/onvif/device_service`, `/onvif/media_service`) and returns
stream URIs of the form:

```
rtsp://<ip>:554/user=admin_password=tlJwpbo6_channel=0_stream=0&onvif=0.sdp?real_stream
```

Profiles reported: `000 mainStream` (H.264 3072×2048), `001 subStream` (H.264 800×448),
`002 snapStream` (JPEG 800×448).

See [`docs/stock-streaming.md`](docs/stock-streaming.md) for the full probe results.

## Read this before exposing it

The camera ships with a **blank `admin` password** and ONVIF media calls that answer without auth. Change
the password in the web UI and keep 554/8899/80 on the LAN only — see [`docs/security.md`](docs/security.md).

## OpenIPC

`xm535d1_lite` exists in OpenIPC, but the firmware itself says *"No majestic yet"* for the V200 media
pipeline — the image boots without any RTSP/ONVIF. Do not flash it and expect video. Details and citations
in [`docs/openipc.md`](docs/openipc.md).

## Documents

- [`docs/stock-streaming.md`](docs/stock-streaming.md) — ports, RTSP/ONVIF endpoints, observed streams
- [`docs/openipc.md`](docs/openipc.md) — what OpenIPC supports on XM535D1 and why it has no video
- [`docs/security.md`](docs/security.md) — default credentials, hardening
- [`docs/backup.md`](docs/backup.md) — full flash dump / recovery notes if you ever modify it

## Legal

Notes on personally owned hardware. No vendor firmware is redistributed. Use at your own risk.
Documentation CC BY 4.0, snippets MIT (see [`LICENSE`](LICENSE)).
