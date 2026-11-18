# OpenIPC on XM535D1 — supported to boot, but no video

OpenIPC does have an XM535D1 target:

- `br-ext-chip-xiongmai/configs/xm535d1_lite_defconfig`
- plus `xm535d2_lite` and `xm535w1_lite` — Xiongmai treats D1/D2/W1 as separate chips with their own
  vendor firmware.

The defconfig targets Cortex-A5 (Thumb2), the XM530 family kernel 3.10.103, 8 MB flash, and the
`xiongmai-osdrv-xm530v200` vendor driver package, with `ATBM603X` USB Wi-Fi support.

## Why it is not useful for this camera

The defconfig contains this note:

```
# No majestic yet: its xm backend drives the XM530's media interface, and
# the V200 series' is a different one (sys/vb/vpss/venc), linked into
# the vendor's Sofia with no shared library to call.
```

Majestic is OpenIPC's streamer. Without it there is **no RTSP and no ONVIF** on XM535D1: the image boots,
gives you a shell, `ipctool`, Wi-Fi and the vendor kernel modules (via
`general/package/xiongmai-osdrv-xm530v200/files/xm535d1/load_xiongmai`), but no usable video pipeline.

That is the same situation as the Anyka `AK3918EV330` lite image: supported enough to boot, not enough to
stream.

## Additional mismatch

The defconfig sets `BR2_OPENIPC_FLASH_SIZE="8"`, which **matches** this board's 8 MiB
FM25Q64 flash. The reason not to flash OpenIPC is the missing XM535 video backend, not the
flash size.

## Conclusion

Do not flash OpenIPC on this board if you want video. The stock firmware already provides RTSP/ONVIF
locally (see [`stock-streaming.md`](stock-streaming.md)).

If you only want a Linux shell/Wi-Fi experiments, the lite image can be built for 8 MiB and booted after a
full flash dump — but you lose the only working video path, so keep the dump and restore it afterwards.

## References

- `openipc/firmware` — `br-ext-chip-xiongmai/configs/xm535d1_lite_defconfig`,
  `general/package/xiongmai-osdrv-xm530v200/files/xm535d1/load_xiongmai`
- OpenIPC wiki — `en/wifi-xm530.md` (Wi-Fi on XM530/XM533/XM535 boards)
- OpenIPC board pages for XM535D1 devices (X4-4GE2Q, X6M-4GEQ-A, IPG-X6E-WEQ, IPG-80X30PSB-WPN)
