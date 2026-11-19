# Local options after root + cloud cut

Measured on `.161` (V5.07 production root, local-only) on 2026-11-19. These are native
camera behaviours, independent of iCSee/VMS/cloud.

## Time / RTC / NTP

> **Do not trust `date` over SSH.** The root shell's `TZ` differs from the application; VMS
> showed the correct time while `date`/`date -u` over SSH were shifted. Use VMS/ONVIF as the
> reference. Full list: [quirks.md](quirks.md).

- **No RTC** on this board: no `/dev/rtc*`, no rtc driver, `hwclock` fails.
- `Sofia` persists the clock to `/mnt/mtd/Config/SysTime` (JFFS2) and restores it at boot
  (`RecoverTime`); it survives reboot but loses time while powered off (plus save lag).
- **Working local time set:** ONVIF `SetSystemDateAndTime` with WS-UsernameToken, explicit
  UTC → exact to ~1 s.
- DVRIP `OPTimeSetting` (msg 1450) works but applies the +1 h timezone twice on V5.07, so
  the clock ends 1 h slow; prefer ONVIF.
- The SNTP client is inside `Sofia`, driven by `NetWork.NetNTP`; there is no `ntpd`/`ntpdate`
  applet. `UpdatePeriod` is in minutes. A LAN NTP server works (router `192.168.0.10` did not
  serve NTP in this setup); a host-side ONVIF time push is the simplest reliable option.

## PTZ / rotation / speed

- The head is a 305°×113° pan/tilt unit.
- **ONVIF PTZ works** (node `NODE_000`, `ContinuousMove` with speed 1..8 + `Stop`).
  `GetStatus` is stubbed (-1/-1), so do not trust it.
- **DVRIP `OPPTZControl` (msg 1400) returns Ret 100 but does not move the head** on this
  model; use ONVIF.
- `Ptz.GunBallLocate.motorSpeedX/Y` (13/9) are persisted config values; ONVIF speed 1..8 is
  the per-command layer.
- Image flip/mirror (`Camera.Param.PictureFlip/Mirror=0x1`) works and persists.
  `CorridorMode=1` is accepted but has no visual effect on this model.
- `ResumePtzState` exists, default off.

## Speaker / audio

- `fVideo.Volume` = speaker (XM_MPI_AO_SetVolume), default 50/50.
- `fVideo.VolumeIn` = microphone (XM_MPI_AI_SetVolume), default 34/35.
- DVRIP 1040/1042 write/read works, persists across reboot.
- RTSP audio: HEVC video + **PCM A-law 8 kHz mono**.
- Two-way talk/speaker path was not destructively tested.

## Web UI

The built-in web UI is only a login shell for the Windows **VideoPlayTool** ActiveX plugin
(`ocx.jftechws.com`); it offers no native HTML settings. Real local control is via
**DVRIP 34567, ONVIF 8899 (WS-Security), RTSP 554, SSH 2222**.

## Implications for a local UI/bridge

- Bridge binary + UI must be small; the current production `user` squashfs has ~193 KiB
  free (the old web UI occupies ~49 KiB compressed and can be removed).
- A host-side bridge (HA/PC) avoids the camera partition constraint and is recommended for
  live/playback/transcoding; the camera can keep native WFS recording.
