# Boot-media root (network-only, QEMU)

Persistent root on a factory-state camera using only DVRIP `ConfigImport` and a reboot: no
upgrade package, no 12901, no UART. **QEMU** only; not tested on hardware.

## Status

- **QEMU**: works on stock V5.07; portable across all five emulated versions (V5.00, V5.01,
  V5.02, V5.04, V5.07).
- **UNTESTED** on hardware. It writes the boot partition (`mtd0`) and overwrites the data
  partition (`mtd5`): more destructive than the unsigned upgrade ([root.md](root.md)), which is
  the preferred path.

## Chain

1. DVRIP login `admin` with empty password: `Ret 100` (factory default, same as V5.01).
2. `ConfigImport` (msg 1540) with a ZIP path-traversal entry `../../dev/mtdblock5` containing
   a small **cramfs root image** with a freestanding 4 KB ARM `/init` (mode 0755, PID 1).
   - The reply is `Ret 103`, but the block device is written: flash at `0x7B0000` starts with
     the cramfs magic `45 3d cd 28`.
3. `ConfigImport` traversal to `../../dev/mtdblock0` containing the **official U-Boot binary**,
   `0xFF` padding, and a forged environment with a valid CRC32. This rewrites the whole
   boot partition, including the unit identity block at `0x2FC00`
   ([recovery.md](recovery.md#identity-block)), which the padding leaves erased. Build the
   `mtd0` image from the unit's own `mtd0` (read it first from a root shell or an SPI dump)
   if the identity must be kept; the QEMU runs used the padded official image:

   ```
   root=/dev/mtdblock5 rootfstype=cramfs init=/init xmuart=0 mtdparts=…
   ```

4. Reboot. U-Boot boots the official kernel with the forged `bootargs`:
   `VFS: Mounted root (cramfs filesystem) on device 31:5`, `/init` runs, brings up `eth0` and
   opens a root console on TCP 2323 (`uid=0 gid=0`, PID 1). `/proc/cmdline` shows the override.
5. The root console persists across reboots. Uploading and `exec`-ing another static ARM binary
   works (`uid=0 euid=0`): arbitrary code execution over the LAN.

## Why it works

- `ConfigImport` (msg 1540) extracts a raw ZIP into `/var/config_tmp`, then `/mnt/mtd/Config`.
  `../` entries escape the target directory.
- The extracting process runs as root and can open unmounted block devices (`mtdblock0` boot,
  `mtdblock1` kernel) and the mounted JFFS2 `mtdblock5`.
- `mtd2`, `mtd3`, `mtd4` (romfs, user squashfs, custom cramfs) are mounted read-only and cannot
  be replaced this way. `mtd5` is writable and survives reboot.
- ZIP external file modes are ignored (extracted files are 0644). Writing a whole cramfs image
  to `mtd5` carries the executable bit inside the filesystem.
- U-Boot honours the forged `bootargs` if the env CRC is valid. The U-Boot binary itself is
  rewritten unchanged; the environment changes, and the identity block is erased unless the
  written image carries it.

Partition offsets: [hardware.md](hardware.md).

## What does not work

- **TFTP initramfs**: U-Boot networking stalls on TX in the `xm535` QEMU machine, and the stock
  kernel has no initramfs/cpio support. A uImage ramdisk is loaded but ignored
  (`No filesystem could mount root … unknown-block(1,0)`); `initrd=` does not help.
- `init=/mnt/mtd/...` or `init=/mnt/custom/...`: `init` runs before `rcS` mounts those
  partitions. `rdinit=` is inert without initramfs.

## Risks and recovery

- **Identity loss:** writing the padded official U-Boot erases the serial/identity block; only
  a dump of the unit restores it.
- **`mtd0` is brick-sensitive.** A bad env CRC makes U-Boot fall back to its default env; a
  broken `bootcmd` leaves SPI as the only recovery (no usable UART pad on this board).
- `mtd5` (config and data) is overwritten: export the configuration first.
- From the custom root console, saved `mtd0`/`mtd5` images can be written back, or the official
  package re-flashed. SPI recovery: [recovery.md](recovery.md).
- Hardware-specific U-Boot/MTD timing and `ConfigImport` block-device behaviour are not
  confirmed.
- The custom `/init` opens an unauthenticated root console on 2323.

The `ConfigImport` traversal as an exposure: [security.md](security.md).
