# Network-only root on stock V5.07 via boot media (QEMU)

> **Status: QEMU-only (2026-11-19).** Not validated on real hardware. This method writes
> the boot partition (`mtd0`) and uses the JFFS2 data partition (`mtd5`) as a custom
> rootfs; it is **more destructive** than the upgrade root path. Prefer
> [upgrade-root-v507.md](upgrade-root-v507.md) for production, and take a verified SPI
> dump before any real test.

## The chain

The camera is in its **factory state** (admin empty password). Only two DVRIP requests and
a reboot are needed; no upgrade package, no signed firmware, no 12901, no UART.

1. **DVRIP login** `admin` + empty password → `Ret 100` (same weak default as V5.01).
2. **`ConfigImport` (msg 1540) with ZIP path traversal** →
   `../../dev/mtdblock5` = a small **cramfs root image** with a freestanding 4 KB ARM
   `/init` (mode 0755, PID 1).
   - `mtd5` is the writable JFFS2 data partition; it is overwritten with the cramfs image.
   - The request returns `Ret 103`, but the block device is written; flash at `0x7B0000`
     starts with cramfs magic `45 3d cd 28`.
3. **`ConfigImport` traversal → `../../dev/mtdblock0`** = the **official U-Boot binary**
   plus a forged **U-Boot environment with a valid CRC32**:
   `root=/dev/mtdblock5 rootfstype=cramfs init=/init xmuart=0 mtdparts=…`
4. **Reboot.** U-Boot starts the official kernel with the forged env; the kernel reports
   `VFS: Mounted root (cramfs filesystem) on device 31:5`, executes the 4 KB `/init`,
   brings up `eth0`, and exposes a **root console on TCP 2323**:
   `V507RT-ROOT uid=0 gid=0 (PID1)`, `id` = uid 0, `/proc/cmdline` confirms the override.
5. The root shell **persists across reboots** (same flash). Uploading another static ARM
   binary and `exec`-ing it works (`ROOTPROOF-EXEC uid=0 euid=0`) — arbitrary code
   execution over the LAN.

## Why this works

- `ConfigImport` (msg 1540) extracts a raw ZIP into `/var/config_tmp` and then
  `/mnt/mtd/Config`; `../` entries escape the target. The root process can open **unmounted
  block devices** — `mtdblock0` (boot) and `mtdblock1` (kernel) — and the mounted JFFS2
  `mtdblock5`.
- `mtd2`, `mtd3`, `mtd4` are mounted read-only (romfs, user squashfs, custom cramfs) and
  cannot be replaced this way; `mtd5` is writable and survives the reboot.
- ZIP external file modes are ignored, so a script placed in JFFS2 would be `0644`; the
  chosen design bakes the executable bit into a **cramfs image** written to `mtd5`, which
  the kernel mounts as root and runs as `/init`.
- U-Boot honours the forged `bootargs` (root/init), and the official U-Boot binary is
  rewritten only to update its environment; a valid CRC is required.

## What does not work

- **TFTP initramfs:** U-Boot networking stalls on TX in the `xm535` QEMU model, and the
  stock kernel has **no initramfs/cpio support**; a uImage ramdisk is loaded but the kernel
  ignores it (`No filesystem could mount root … unknown-block(1,0)`), `initrd=` does not
  help.
- `init=/mnt/mtd/...` or `/mnt/custom/...`: `init=` runs before `rcS` mounts those
  partitions; `rdinit=` is inert without initramfs.

## Risks / recovery

- **`mtd0` is brick-sensitive.** The PoC keeps the official U-Boot binary and a valid env
  CRC; a bad CRC makes U-Boot fall back to its default env, a broken `bootcmd` leaves only
  the password-gated UART. There is **no SPI dump yet**.
- `mtd5` (config/data) is overwritten by the cramfs rootfs: the vendor config is lost
  unless exported/backed up. Recovery from the custom root shell can write back saved
  `mtd0`/`mtd5`, or re-flash the official package/SPI dump.
- This is a **QEMU-only proof**; real U-Boot/MTD timing, flash size/layout and the
  `ConfigImport` block-device behaviour must be confirmed on hardware (ideally after an
  SPI dump).
- The custom init opens an **unauthenticated root console on 2323**; firewall it.

## Ranking for a stock V5.07

1. **Boot-media root** (this page) — proven in QEMU, network-only, persistent; destructive
   to `mtd0`/`mtd5` and needs recovery media.
2. **Unsigned upgrade** — validated in QEMU and on hardware; less destructive, keeps the
   vendor partitions, root via SSH/2323; preferred for production.
3. **Downgrade V5.07 → V5.01** — validated; no advantage over upgrade except reusing the
   V5.01 packages.
4. **12901 auth downgrade / heap overflow** — no ready root primitive (fixed `timetest`);
   see [debug-12901.md](debug-12901.md).
5. **UART/SPI** — physical fallback.

## Related

- [upgrade-root-v507.md](upgrade-root-v507.md) — preferred root on latest (hardware-validated)
- [production-firmware-v507.md](production-firmware-v507.md) — SSH production image
- [debug-12901.md](debug-12901.md) — 12901 auth downgrade/heap overflow
- [return-to-stock.md](return-to-stock.md) — recovery
