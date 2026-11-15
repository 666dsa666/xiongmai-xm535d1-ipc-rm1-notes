# Backup and recovery notes

Only needed if you decide to modify the camera. For normal local RTSP use (see
[`stock-streaming.md`](stock-streaming.md)) none of this is required.

## Flash

| field | value |
|---|---|
| chip | Winbond **W25Q128** family (16 MB / 128 Mbit) |
| package | SOIC-8 |
| contents | bootloader, kernel, rootfs, config |

There is no documented recovery button or SD recovery mode on this board, so a full read is the only
safety net.

## Full dump (CH341A)

1. Power the camera off and disconnect it.
2. Clip the SOIC-8 flash with the CH341A (3.3 V).
3. Read it **twice** and compare:

   ```
   flashrom -p ch341a_spi -r dump1.bin
   flashrom -p ch341a_spi -r dump2.bin
   fc /b dump1.bin dump2.bin     # or cmp / sha256sum
   ```

4. Keep at least two copies off-device, with the SHA-256 recorded.

Expected size: 16,777,216 bytes.

## UART

The board has several unpopulated headers (motor, speaker, IR), and the UART pads have not been identified
on this revision yet. If you go looking:

- typical Xiongmai XM535 boards run U-Boot at **115200 8N1**;
- look for a 3- or 4-pad group near the SoC, often labelled `TX`/`RX`/`GND`;
- adapter `TXD` → board `RX`, adapter `RXI` → board `TX`, common `GND`; do not feed 3V3/5V;
- capture the boot log before touching anything.

## If you experiment with OpenIPC

Remember [`openipc.md`](openipc.md): the XM535D1 lite image has **no video backend**. Boot it only if you
accept losing RTSP, and keep the full dump for restoring the stock firmware.

## Restore

Write the verified dump back with the same CH341A setup:

```
flashrom -p ch341a_spi -w dump1.bin
```

Verify by reading again and comparing, then power on.
