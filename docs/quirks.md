# Known quirks and traps — XM535D1 / X6E-WEQ

Field notes from the project. These are behaviours that cost time and can mislead debugging.
Validated on V5.07 (and V5.01 where noted), 2026-11-19/20.

## 1. Time: SSH `date` is NOT the camera time

**Symptom:** over SSH, `date` shows something like `Fri Nov 20 01:58 GMT-1`, while VMS and the
application show the correct local time.

- The root shell has a different/missing `TZ`; busybox `date` and `date -u` do **not** reflect
  what VMS/recording uses.
- The camera application (Sofia/VMS) displayed the correct time when NTP was enabled.
- **Do not "fix" the camera clock based on `date` over SSH.** Use VMS as the reference;
  for programmatic checks use ONVIF/`OPTimeQuery` and compare with a known-good client.

Other time facts:

- **No RTC** on this board (no `/dev/rtc*`, no rtc driver, `hwclock` fails).
- Sofia persists time to `/mnt/mtd/Config/SysTime` (JFFS2) and restores it at boot
  (`RecoverTime`); it survives reboot but not a long power-off, and there is save lag.
- `NetNTP.Enable` is a separate switch. VMS can fill `Server`/`NtpServerList` while leaving
  `Enable=false`; then nothing syncs. Enable it explicitly.
- `UpdatePeriod` is in **minutes** (10 by default), not seconds.
- NTP server log proof (public pool): `NTPD: UpdateTime …` in `/var/sofia.log`.
- ONVIF `SetSystemDateAndTime` with explicit UTC is the most exact manual setter.
- DVRIP `OPTimeSetting` (1450) on V5.07 applies the +1 h timezone twice → clock 1 h slow;
  prefer ONVIF.
- `NetNTP.TimeZone` is an index in `[0,33]`; `System.TimeZone.timeMin` is a separate field
  (was `-60` here). The ONVIF timezone string was `CET-1CEST`. Do not deduce the wall clock from
  these alone.
- **Recording clock can be shifted by `System.TimeZone.timeMin` while live/OPTimeQuery is
  correct.** With `timeMin=-60`, new recordings were stamped +1 h (e.g. file at 01:20 while
  camera/OPTimeQuery said 00:20). Setting `timeMin=0` fixed new files; files already written keep
  their bad timestamps until deleted or the card is formatted.
- Public NTP works with `time.cloudflare.com` / `0.fr.pool.ntp.org`; allow **UDP 123 out** only.

## 2. Storage: WFS has no DOS partition table

- After a valid in-camera/VMS format, `/proc/partitions` can still show **only `mmcblk0`**
  (no `mmcblk0p1`) and there is **no `/mnt/sd` mount**.
- This does **not** mean the card is unformatted. The recorder uses **WFS raw partitions**
  (`/idea0/...`), exposed by the StorageManager/app, not by a DOS partition table.
- VMS storage page showed `2-1 Read/Write` and `2-2 Snapshot` and recording worked while the
  shell still showed `unknown partition table`.
- `/mnt/idea0` / `/mnt/idea1` in logs are the storage-manager names, not mounted filesystems.
- `OPStorageManager` direct calls (`SetType`, `Clear`, `Partition`) can return `Ret 100` yet do
  nothing on an uninitialised card. The **VMS/app format path** (`ClearDriver /mnt/idea0`,
  `/mnt/idea1`) is what actually created the WFS layout here.
- A 64 GB Samsung Evo Plus U3 was formatted via the old VMS PC app; recording then ran
  continuously in 5-minute files (`OPFileQuery` msg 1440), `SDCheckStatus=0`.
- The V5.05+ recording "partition error" regression was **not reproduced** on this card/config.

## 3. DVRIP / configuration API

- `NetWork.NetCommon.HttpPort` is **cosmetic**: setting it to 0 or 8080 and rebooting still
  leaves the HTTP server on **TCP 80**. No native web-disable flag was found.
- No `iptables`/`nft` on the camera, so an on-device port-80 DROP needs a binary patch or a
  preload hook (work in progress, QEMU only).
- `get_info("Status")` / some `SystemInfo` blocks return `Ret 607`; not all DVRIP info blocks
  are available to this account.
- `OPPTZControl` (msg 1400) returns `Ret 100` but does **not move** this pan/tilt head.
  Use **ONVIF PTZ** (`ContinuousMove` speed 1..8 + `Stop`); ONVIF `GetStatus` is stubbed
  (-1/-1).
- `OPFileQuery` uses msg **1440** and returns the recording list; msg 1444 produced a malformed
  reply in the Python client (decode error). File timestamps follow the camera's app clock.
- DVRIP port is 34567; ONVIF 8899; RTSP 554; SSH (production) 2222. VMS uses 34567.
- `getUsers` exposes per-account fields; treat the second admin account as sensitive.

## 4. VMS PC 2.0.28.1

- Device connection must use **admin** (IP/34567), not the cloud-created service account.
- Cloud pairing creates a **second admin service account**, with a **different login per
  camera**: `jfxe` on `.161`, `twhn` on `.153`. Do not hardcode `jfxe`.
- On V5.07 that account cannot be deleted (`DelUser` → `Ret 101`); it can be downgraded to
  group `user` with a strong random password.
- If VMS is left on that account after neutralisation, the device connects and live/storage
  work, but VMS shows **607** on Version/stream pages (sometimes "Pas d'alimentation").
  Fix: VMS device credentials = `admin`.
- Isolated on hardware with reboot: NAT off, `DisableXmServerConn` true, PMS/upgrade/NTP off,
  strong admin password, production firmware, `OnvifPwdCheckout=true` all still allow VMS.
  The service account was the blocker.
- VMS/app pairing can change the admin password; if a previously working password fails,
  check what was set during pairing.

## 5. Web UI / HTTP

- The built-in web UI is only a **login shell for the Windows VideoPlayTool ActiveX plugin**
  (`ocx.jftechws.com`). Menus are Preview/Playback/Alarm/Remote Setting, all delegated to the
  plugin. It is useless without the Windows plugin and exposes no native HTML settings.
- The legacy `/cgi-bin` bridge rejects a non-empty admin password (`Ret 203`) even with the
  correct credential; it is not a general local API.
- Removing `/usr/web` saves ~49 KiB compressed, but the httpd still listens on 80 until the
  binary/preload patch lands.

## 6. Debug services / root

- **50119 `timetest`** is not a time service: it is a hidden BusyBox **telnetd**, started by
  `dvrHelper` only when U-Boot env `telnetctrl==1`. Stock cameras have no such env and no
  listener. It is a post-exploitation/persistence add-on, not a stock root primitive.
- **12901 `debug`** has a VSC auth downgrade (no vendor RSA key needed) but no root path;
  PATH hijack/core_pattern/hotplug are blocked; heap overflow gives a clean pre-auth DoS.
- Root production access is **SSH key-only on 2222**; 2323/12901/9530/50119/23 are closed.
- `/mnt/mtd/Log/9530Disable` is the marker used to keep 9530/12901 closed.

## 7. Cloud cut / hardening

- PMS = Push Message Service (`push.umeye.cn`), not video/P2P. NAT = P2P (`secu100.net`).
- Cloud cut (`PMS/NAT/OnlineUpgrade/NTP` off + `DisableXmServerConn` true) does **not** break
  local RTSP/ONVIF/DVRIP, SD recording, PTZ or VMS on the LAN — tested variable by variable.
- `OnvifPwdCheckout=true` and `TelnetDebugMode=false` did not break VMS.
- The VMS breakage was the neutralised **cloud-created service account**, not the cloud cut.
- Voice prompts live in the read-only `/usr` squashfs; an official flash restores them, a
  config/factory reset does **not**.
- Factory/config reset restores vendor defaults and recreates the service account; re-apply
  hardening and VMS account settings afterwards.

## 8. Misc

- `ConfigExport` before hardening exposed accounts and the Wi-Fi PSK; rotate the PSK.
- Camera time zone/app display and shell time are independent (see §1).
- The storage manager logs `ClearDriver /mnt/idea0|1` and `OPStorageManager` around a format;
  absence of `mmcblk0p1` after that is normal WFS behaviour.
- The 64 GB card is usable; a card that does not initialise may be incompatible/worn, not
  necessarily a firmware bug.

