# Quirks and traps

Behaviours that mislead debugging on the XM535D1 / `XM535_X6E-WEQ_8M`. Validated on V5.07
(V5.01 where noted). Configuration procedures live in [hardening.md](hardening.md).

## Time

- **SSH `date` is not the camera time.** The root shell may lack `TZ` and show UTC while VMS and
  the app show local time. Do not change the clock based on `date`; use VMS, ONVIF or
  `OPTimeQuery` as reference. **HW**
- **Recording time depends on two fields.** Correct configuration: `/mnt/mtd/Config/localtime` =
  `GMT-1` TZif and `System.TimeZone.timeMin=-60`. Changing only one of them shifts the app or new
  recordings by 1 h. Files already written keep their timestamps until deleted or the card is
  formatted. Full settings: [hardening.md](hardening.md). **HW**
- **No RTC** (no `/dev/rtc*`, `hwclock` fails). Sofia saves time to `/mnt/mtd/Config/SysTime`
  and restores it at boot (`RecoverTime`): the time survives a reboot but not a power-off, and
  saving lags. **HW**
- `NetNTP.Enable` is a separate switch. VMS can fill `Server`/`NtpServerList` and leave
  `Enable=false`: nothing syncs. **HW**
- `UpdatePeriod` is in minutes (default 10). Sync proof: `NTPD: UpdateTime` in `/var/sofia.log`.
- DVRIP `OPTimeSetting` (msg 1450) on V5.07 applies the +1 h offset twice: clock 1 h slow. Use
  ONVIF `SetSystemDateAndTime` with explicit UTC. **HW**
- `NetNTP.TimeZone` is an index in `[0,33]`, independent of `System.TimeZone.timeMin`; the ONVIF
  timezone string was `CET-1CEST`. None of them alone gives the wall clock.

## SD card / WFS

### WFS layout

- After a valid format, `/proc/partitions` shows only `mmcblk0` (no `mmcblk0p1`), the shell
  reports `unknown partition table`, and there is no `/mnt/sd`. This is normal: the recorder uses
  WFS 0.4 raw partitions (record + snapshot), not a DOS partition table. **HW**
- `/mnt/idea0` and `/mnt/idea1` in logs are storage-manager names, not mounted filesystems.
- `OPStorageManager` `SetType`/`Clear`/`Partition` can return `Ret 100` and do nothing on an
  uninitialised card. The VMS/app format path (`ClearDriver /mnt/idea0`, `/mnt/idea1`) creates the
  WFS layout. **HW**
- VMS storage page after a good format: `2-1 Read/Write`, `2-2 Snapshot`.
- Recording rotates in 5-minute files (`PacketLength:5`); list them with `OPFileQuery` (msg 1440).

### Card size (HW, all three cameras)

| card | result |
|---|---|
| 64 GB (e.g. Samsung Evo Plus U3), formatted via VMS | `SDCheckStatus=0`, continuous recording on cam1, cam2, cam3 |
| 128 GB SDXC (cam1) | WFS init failed: `AsyncInitFS init error`, `SDCheckStatus=17`, no files |

Use 64 GB known-good cards. 128 GB is not validated.

### "Recording partition error" regression (V5.05+)

Public reports: after 5–10 min of recording on V5.05/V5.07, iCSee/XMEye shows "Recording partition
error – Please format the SD card"; one user fixed it by downgrading to V5.04, another failed on all
firmwares ([V5.05 report](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/page-2#post-953874),
[V5.04 downgrade](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/post-980252),
[all firmwares tried](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/page-3)).

Analysis (**STATIC**):

- The message text is app-side; it is absent from the firmware.
- V5.05+ adds an SD-health subsystem in `Sofia`/`StorageManagerIn`. It stores a per-card-CID state
  as `Storage.SDCheckStatus` in `/mnt/mtd` and reports `Detect SD Error %u` to the cloud. A card
  can stay marked bad after a format. V5.04 has no such key, which explains the downgrade fix.
- Status values seen in the code paths: 4 (write stall), 17 (WFS init error, **HW**),
  20/21 (format stuck), 23 (no WFS).
- V5.04 → V5.07: `Sofia` MD5 `c302114b…` → `45618e81…` (+148 KB). New strings:
  `SaveSDStatusConfig Status:%u`, `This SD card was error(N) last time, ignore it!`, `AsyncInitFS`,
  `FormatUnrecognizeDev`, `NoBitrateByWriteSDStuck`, `readMmcblk0WriteStat`,
  `CRecord::start checkStart failed`, `m_dwFSError`, AOV auto-reboot (AOV: see the
  [Glossary](../README.md#glossary)). SD/MMC kernel code and the
  `Record`/`Storage` defaults are essentially unchanged.

Fleet status (**HW**): **not reproduced** on 64 GB cards on V5.07 production. Observed failures are
at least partly card/SDXC compatibility.

If it reappears, before formatting capture:

- the VMS error and `Storage.SDCheckStatus` value;
- `dmesg | grep mmc`, `/sys/block/mmcblk0/stat`, `/var/sofia.log`, `halted.log`,
  `/mnt/mtd/Config/Json/*`;
- a read-only image of the card;
- whether files after the error exist/play, and whether a power cycle logs "error last time".

Possible fixes, only after a reproduction (**UNTESTED**): patch the `SaveSDStatusConfig` /
`Detect SD Error` path in a V5.07 `user` image, or downgrade to V5.04. Test in QEMU first, never on
a unit without an SPI dump ([recovery.md](recovery.md)).

## DVRIP

- `NetWork.NetCommon.HttpPort` is cosmetic: 0 or 8080 still leaves HTTP on TCP 80 after reboot.
  No native web-disable flag exists. **HW**
- No `iptables`/`nft` on the camera. Port 80 is closed by the `block80.so` `LD_PRELOAD` shim
  (**HW**, all three cameras; `Sofia` unchanged). See [production.md](production.md).
- `get_info("Status")` and some `SystemInfo` blocks return `Ret 607`.
- `OPPTZControl` (msg 1400) returns `Ret 100` but does not move the head. Use ONVIF PTZ
  `ContinuousMove` (speed 1..8) + `Stop`; ONVIF `GetStatus` is stubbed (-1/-1). **HW**
- `OPFileQuery` is msg 1440; msg 1444 returns a reply that a Python client fails to decode.
  File timestamps follow the app clock.
- Ports: DVRIP TCP 34567, ONVIF TCP 8899, RTSP TCP 554, production SSH TCP 2222.
- `getUsers` exposes per-account fields; treat the cloud-created second account as sensitive.
- `ConfigExport` before hardening exposed the accounts and the Wi-Fi PSK; rotate the PSK.

## VMS

- VMS must connect as `admin`, not as the cloud-created `<service-account>` (login differs per
  camera; it cannot be deleted on V5.07, `DelUser` → `Ret 101`). With the neutralised service
  account, VMS shows `607` on Version/stream pages, sometimes "Pas d'alimentation" (no power;
  French UI, see [hardening.md](hardening.md#vms-setup)).
  Setup: [hardening.md](hardening.md). **HW**
- VMS/app pairing can change the admin password.

## Web UI

- The web UI on TCP 80 is a login shell for the Windows VideoPlayTool ActiveX plugin
  (`ocx.jftechws.com`); all menus are delegated to it. No native HTML settings.
- After hardening, the legacy `/cgi-bin` bridge returns `Ret 203 Pwd error` for any non-empty admin
  password, including the correct one (plaintext or stored hash). **HW**
- Removing `/usr/web` saves about 49 KiB compressed but does not stop httpd on TCP 80.

## Debug ports

- TCP 50119 `timetest` is not a time service: it is a hidden BusyBox telnetd started by
  `dvrHelper` only when U-Boot env `telnetctrl=1`. Inactive by default. Details:
  [debug-services.md](debug-services.md).
- TCP 12901 `/usr/bin/debug` is closed by default; its auth accepts VSC (no vendor RSA), but the
  post-auth command is fixed `timetest`: no root shell.
- `/mnt/mtd/Log/9530Disable` is the marker that keeps 12901 closed (`/usr/bin/debug` exits); 9530
  has no listener on this firmware. It does not gate 50119 (`telnetctrl` does).
- Production root is SSH key-only on TCP 2222; 2323/12901/9530/50119/23 are closed. **HW**

## Cloud cut

- PMS is Push Message Service (`push.umeye.cn`), not video. NAT is P2P (`secu100.net`).
- Cloud cut (PMS/NAT/OnlineUpgrade off, `DisableXmServerConn=true`) does not break local
  RTSP/ONVIF/DVRIP, SD recording, PTZ or VMS. `OnvifPwdCheckout=true` and
  `TelnetDebugMode=false` do not break VMS either. NTP stays on as a deliberate exception. **HW**
- The VMS breakage seen during hardening came from the service account, not the cloud cut.
- A factory/config reset restores vendor defaults and recreates the service account: re-apply
  [hardening.md](hardening.md).

## Misc

- Voice prompts live in the read-only `/usr` squashfs: an official flash restores them, a config
  reset does not ([recovery.md](recovery.md)).
- A card that does not initialise may be incompatible or worn; do not assume a firmware bug.
