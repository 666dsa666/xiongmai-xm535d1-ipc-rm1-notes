# QEMU emulation

Rebuild an 8 MiB flash image from an official package and boot it in the OpenIPC `qemu-bench`
`xm535` machine. Used for all **QEMU** results in this repository.

## Images

| Image | Source | Check |
|---|---|---|
| `xm535d1_v507_flash.img` | official `V5.07.X02` package | full boot |
| `xm535d1_v501_flash.img` | official `V5.01.R02` (the cameras' shipping build) | U-Boot `Apr 26 2024`, kernel `#27 Aug 1 2024` |

The emulated `/mnt/mtd` is empty: a unit's own configuration and identity are only in its SPI
dump ([recovery.md](recovery.md)).

## Building the flash image

Partition offsets and sizes: [hardware.md](hardware.md). Place each payload at its partition
offset:

- uImage payloads in the package are not gzipped: strip the 64-byte uImage header and use the
  raw CRAMFS/SquashFS payload;
- `uImage.img` is a container: the outer uImage (flagged gzip, but not gzip) holds the real
  uncompressed kernel uImage (load `0x80008000`). Put the **inner** uImage at `0x40000`;
- the U-Boot environment at `0x30000` (64 KiB) is a standard `crc32 + "k=v\0…"` block.
  With `xmuart=0` set, kernel console output appears in QEMU (meaning of the value not
  confirmed from code, see [hardware.md](hardware.md#spi-flash-layout)); `telnetctrl=1` starts
  the 12901 daemon.

## Build QEMU

```sh
git clone https://github.com/OpenIPC/qemu-bench
cd qemu-bench
bash qemu/setup.sh        # QEMU 10.2 with the xiongmai machines
```

`-machine help` must list `xm535`. The CI `qemu-arm` artifacts need a newer glibc and may not
run on older distributions; build locally.

## Boot

```sh
qemu-system-arm -M xm535,flash-file=xm535d1_v507_flash.img -nographic
```

Expected: vendor U-Boot 2014.04, Linux 3.10.103, then `Sofia` (`X6E-WEQ`, ports
80/554/8899/34567, DHCP on the QEMU user network).

## Root shell in the emulator

The `xm535` machine does not model `ttyS000` (the `inittab` getty); the kernel console is
`ttyAMA0`. Repack the CRAMFS rootfs with an extra `inittab` line:

```
ttyAMA1::respawn:/bin/sh -i
```

plus `/dev/ttyAMA1` (`mknod … c 204 65`), and add a second serial port:

```sh
qemu-system-arm -M xm535,flash-file=shell.img -display none \
  -serial mon:stdio \
  -serial tcp:127.0.0.1:4447,server=on,wait=off
```

Connect to `127.0.0.1:4447` for a root prompt. The same repack can add a hook to
`/etc/init.d/rcS` for boot-time output. Emulation only: the physical board has no usable UART.

## What the emulator confirmed

- full boot of the official image, `Sofia`, cloud/PMS startup;
- `/mnt/mtd/Log/ns` bind-mounted over `/etc/passwd`;
- `/var/T8aYMi2q` deterministic from SN/date;
- 12901 starts only when `telnetctrl` is set; `EnableKey` ignored;
- unsigned-upgrade variants ([root.md](root.md)) and boot-media root
  ([boot-media-root.md](boot-media-root.md)).

Details: [debug-services.md](debug-services.md).

## Limitations

- No sensor/video realism; control-plane analysis only.
- U-Boot networking stalls on TX; Ctrl+C does not reliably stop U-Boot.
- Guest flash writes go back to the image file: work on a copy.
