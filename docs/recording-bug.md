# SD recording bug on V5.05/V5.07 ("Recording partition error")

## Symptom

After ~5–10 minutes of recording, iCSee/XMEye shows:

> Recording partition error – Please format the SD card

Reported on **V5.05** and **V5.07**, with several cards; one user fixed it by **downgrading**
(ICSee VMS) to an earlier firmware, another tried all firmwares without success (suggesting a
card/wear factor on top of the firmware regression).

Public reports:
[V5.05 report](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/page-2#post-953874),
[V5.04 downgrade fixed it](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/post-980252),
[all firmwares tried](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/page-3).

## Likely cause (firmware regression, high confidence)

- The text is **app-side**; it is absent from all firmware strings. Camera-side, V5.05+ adds a
  new `Sofia`/`StorageManagerIn` SD-health subsystem that raises a storage alarm.
- After the first extended write (default `PacketLength:5` → 5-minute rotation), the new logic
  records a bad "record partition" state, **persists it per card CID** as
  `Storage.SDCheckStatus` in `/mnt/mtd`, and emits `Detect SD Error %u` to the cloud.
- Observed statuses include 4 (write stall), 20/21 (format stuck), 23 (no WFS). Formatting does
  not necessarily help because the state is keyed to the card CID and can be restored from
  cloud; V5.04 does not have this state key, which explains why the downgrade restores recording.
- The on-card format is WFS 0.4 "record+snap" auto-partition, not standard FAT32/exFAT; generic
  cluster-size advice is irrelevant.

Regression evidence (V5.04 → V5.07):

- `Sofia` md5 changes (`c302114b…` → `45618e81…`, +148 KB);
- new strings/functions absent in V5.00–V5.04: `Storage.SDCheckStatus`,
  `SaveSDStatusConfig Status:%u`, `Detect SD Error %u`, `This SD card was error(N) last time,
  ignore it!`, `AsyncInitFS`, `FormatUnrecognizeDev` (format stuck), `NoBitrateByWriteSDStuck`,
  `readMmcblk0WriteStat`, `CRecord::start checkStart failed`, `m_dwFSError`, AOV auto-reboot;
- the SD/MMC kernel code and config defaults (`Record`/`Storage`) are essentially unchanged.

## Workarounds (in order)

1. **Downgrade to V5.04** (via ICSee VMS or an official package after a verified SPI dump).
   This is the user-validated fix; no SD-health state key.
2. Temporary: **high-endurance card**, lower bitrate, pre-record off, in-camera format,
   factory reset. These reduce the chance of tripping the new check but do not remove it.
3. Keep a **known-good card imaged before formatting**; the status is keyed by CID, so a
   problematic card can stay "marked bad".

## Reproduction protocol (hardware, user-run)

1. Baseline on V5.04 with card A, record 60 min; confirm no error.
2. Upgrade to V5.07, cloud on, record; capture the exact time of the error and a screenshot.
3. Do **not** format immediately: check whether files after the error exist/play, and whether a
   power-cycle produces "error last time".
4. Differential: new card B, high-endurance C, camera-format/factory-reset, low bitrate +
   pre-record off + cloud off, then downgrade V5.04 with the failed card (must work), then
   re-upgrade.
5. Collect: UART 115200 log, card read-only image **before formatting**, and from a rooted V5.07
   `/mnt/mtd/Config/Json/*`, `sofia.log`, `halted.log`, `dmesg | grep mmc`,
   `/sys/block/mmcblk0/stat`.

## Fix candidate

- Patch the V5.07 `user` image (existing unsigned-package pipeline) to neutralise or fix the
  status setters / `SaveSDStatusConfig` / `Detect SD Error` path, **after** identifying which
  check trips from the reproduction logs; or
- swap the V5.04 `Sofia` + `libdvr.so` into a V5.07 `user` image while keeping the V5.07
  kernel/romfs (ABI risk; test in QEMU, then spare camera only).
- Do not deploy a fix to the production camera without a verified SPI dump and a QEMU test.

## Hardware reproduction status (2026-11-19)

Test on `.161` (V5.07 production root, local-only) with a **Samsung 64 GB Evo Plus U3**:

- kernel sees the card as `mmcblk0` (59.6 GiB, SDXC) but logs **`unknown partition table`**
  and cannot read a valid FAT;
- `OPStorageManager` actions (`SetType`, `Clear`, `Partition`) return 100/603 but do **not**
  create a partition; the camera log shows `WFS,sys_init_s2 disk 0 read_parts failed,
  ret:1002` and earlier `StorageDeviceEr ... /dev/sd0a`;
- no `/mnt/sd` mount, so recording cannot start and the bug is **not yet reproduced**.

Next: retry with a **32 GB or smaller, known-good card** (or a card already formatted by
another XM camera), then follow the reproduction protocol. This first test suggests part of
the field reports may be card/SDXC compatibility, not only the V5.05+ firmware check.

