# Reproducing the stock firmware in QEMU (OpenIPC qemu-bench, `xm535`)

> **Not the unit's own dump, but now its exact build.** This image was first built from
> the official **`V5.07.X02`** package. The exact **`V5.01.R02` (2024-09-14)** package —
> the unit's shipping build — was later obtained and rebuilt the same way
> (`xm535d1_v501_flash.img`), verifying U-Boot `Apr 26 2024`, kernel `#27 Aug 1 2024`.
> A real 8 MiB flash dump (CH341A) is still the only way to see the unit's private config
> (`/mnt/mtd` JFFS2) and any production-time divergence.

This is the analysis setup used to reverse the telnet/debug handling **without touching the
camera**. The official 8 MiB flash layout can be reconstructed from the vendor `V5.07.X02`
package and booted in the `qemu-bench` `xm535` machine.

## Flash layout (8 MiB, from the vendor U-Boot env `mtdparts`)

| offset | size | partition | content |
|---|---|---|---|
| `0x000000` | 256 KiB | `boot` | raw U-Boot + environment (64 KiB at `0x30000`) |
| `0x040000` | 1536 KiB | `kernel` | kernel uImage |
| `0x1C0000` | 1280 KiB | `romfs` | CRAMFS rootfs (`/`) |
| `0x300000` | 4544 KiB | `user` | SquashFS `/usr` |
| `0x770000` | 256 KiB | `custom` | CRAMFS `/mnt/custom` |
| `0x7B0000` | 320 KiB | `mtd` | JFFS2 `/mnt/mtd` (writable config) |

Notes learned while building the image:

- the uImage payloads in the official package are **not** gzipped: strip the 64-byte uImage
  header and use the raw CRAMFS/SquashFS payload;
- `uImage.img` is a **container**: the outer uImage (flagged gzip, but not gzip) holds the
  real uncompressed kernel uImage (load `0x80008000`). Put the **inner** uImage at
  `0x40000`;
- the U-Boot environment at `0x30000` is a standard `crc32 + "k=v\0…"` block; adding
  `xmuart=0` enables the kernel console, adding `telnetctrl=1` starts the vendor debug
  service on 12901.

## Build QEMU

```sh
git clone https://github.com/OpenIPC/qemu-bench
cd qemu-bench
bash qemu/setup.sh        # builds QEMU 10.2 with the xiongmai machines
```

`-machine help` must list `xm535`. (The CI artifacts `qemu-arm` are built against a newer
glibc and may not run on older distros; building locally is the reliable option.)

## Boot

```sh
qemu-system-arm -M xm535,flash-file=xm535d1_v507_flash.img -nographic
```

Expected: vendor U-Boot 2014.04, Linux 3.10.103, then the full **Sofia** application
(`X6E-WEQ`, ports 80/554/8899/34567, DHCP on the QEMU user network).

## Getting a root shell inside the emulator

The stock `/etc/inittab` auto-logs root on `ttyS000`, which the `xm535` machine does not
model. For analysis, repack the CRAMFS rootfs with:

```
ttyAMA1::respawn:/bin/sh -i
```

plus `/dev/ttyAMA1` (`mknod … c 204 65`) and expose a second serial:

```sh
qemu-system-arm -M xm535,flash-file=shell.img -display none \
  -serial mon:stdio \
  -serial tcp:127.0.0.1:4447,server=on,wait=off
```

Connect to `127.0.0.1:4447` to get a root prompt. Use the same technique to add a debug
hook to `/etc/init.d/rcS` if you only need boot-time output.

## What the emulator confirms

- full boot of the official image, Sofia and cloud/PMS startup;
- `/mnt/mtd/Log/ns` (bind-mounted over `/etc/passwd`) = `root:697SJ23Ru0j3M:…`;
- `/var/T8aYMi2q` is **created by `GetSaftyCode`** and its value is deterministic from
  SN/date (`C52DEAF1…` for an empty SN, emulator build);
- `/usr/bin/debug` starts on **12901** only when `telnetctrl` is set;
- DVRIP `EnableKey` is ignored, as proven by breakpoints and by port checks from the guest.

## Limitations

- No camera sensor/video pipeline realism is needed here; the machine models enough for
  control-plane analysis.
- Flash writes done by the guest go back to the image file — use a copy, never the only
  master dump.
- The emulator cannot produce the vendor RSA private key; the 12901 service stays
  vendor-only in emulation too.

See [telnet.md](telnet.md) for the protocol results and [cves.md](cves.md) for the CVE map.
