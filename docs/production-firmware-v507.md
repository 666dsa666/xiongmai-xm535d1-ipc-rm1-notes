# Production firmware for V5.07 (SSH key-only root on 2222)

> **Status: validated in QEMU only (2026-11-19).** No real V5.07 camera was available.
> `.161` remains the validated V5.01 production camera; `.153` remains stock.
> Take a verified SPI dump ×2 before flashing a real V5.07 unit.

This is the V5.07 version of [production-firmware.md](production-firmware.md): the latest
vendor firmware, with an authenticated SSH root and no unauthenticated shell, cloud off
and the same hardening as the V5.01 production image.

## Deliverable

| Item | Value |
|---|---|
| Package | `v507_prod_ssh.bin` (7,452,850 B) |
| SHA-256 | `327e90fe46febb5673892f0cd91a41ffd074a32be1202bc20044bb151cf39253` |
| Base | official V5.07.X02 `_all.bin` — only `user-x.cramfs.img` differs |
| Root access | SSH key-only `root@<ip>:2222` |
| Host key fingerprint | `SHA1:de:fc:27:eb:4c:85:66:b4:a9:62:02:ce:f6:82:50:8f:3f:c8:03:16` |
| Client public key fingerprint | `SHA256:bbpcgLpKBX9e39n9RVkse7SFBtXhjsoF+ZwLTmvtSbc` |
| Client key / admin password | local workspace `stack/analysis/access/v507-production/` (sensitive) |

Keys are **new for this variant** (not the V5.01 keys).

## What changes

Only the `user` partition is replaced with a V5.07 vendor `/usr` tree plus:

- `/usr/bin/dropbear` — same static ARM, key-only dropbear as V5.01 (699,120 B);
- `/usr/share/ssh/dropbear_host_key` — new ed25519 host key;
- `/usr/share/ssh/authorized_keys` — new client public key;
- `/usr/share/ssh/passwd` — `/etc/passwd` with root home `/mnt/mtd`, bind-mounted at
  boot so dropbear finds `/mnt/mtd/.ssh/authorized_keys`;
- `/usr/bin/quick_venc.sh` — boot hook run by V5.07 `rcS`: creates
  `/mnt/mtd/Log/9530Disable`, installs the authorized key, bind-mounts the passwd, starts
  `dropbear -p 2222 -P /tmp/dropbear.pid -E`;
- `/usr/share/music/` removed (voice prompts) to fit the 4,544 KiB partition:
  squashfs 4,456,448 B < 4,652,992 B payload limit.

U-Boot/env/kernel/romfs/custom and `InstallDesc` are **byte-identical** to official
V5.07 (verified by `prod_integrity.py`).

## Why the V5.07 verifier accepts it

V5.07 sets the CRC/Mx8Q flags to 0 and never reaches `VerifyMx8QSign`; the only
revalidation is the uImage header CRC (`tryDoDataCheck`), which passes because the
payloads are re-wrapped. See [upgrade-root-v507.md](upgrade-root-v507.md).

## QEMU validation (both paths)

| Start state | Result |
|---|---|
| V5.07 stock | upload `Ret 515`, reboot, V5.07 (kernel #84), SSH root 2222 key-only, `Uid 0`, no 2323/12901/9530/23, `9530Disable` present |
| V5.01 rooted | same: `Ret 515`, V5.07 + production SSH |
| second reboot | SSH still works (~4 s uptime) — persistence |
| hardening | admin password changed, only `admin`, PMS/NAT/OnlineUpgrade/NTP off, `DisableXmServerConn` all true, `OnvifPwdCheckout` true, `TelnetDebugMode` off — all re-read after reboot |
| network/auth | RTSP empty **401**, hash/plain **200**; ONVIF media/device unauth **401**; snapshot unauth **401**; HTTP bridge wrong pw **203**; listeners only 2222 + 80/554/8899/34567/23000 |

Images archived by the agent: `prod_v507_from_stock.img`, `prod_v507_from_v501root.img`.

## Install method (real V5.07, after SPI dump)

1. Verified SPI dump ×2; note admin password and config.
2. Upload `v507_prod_ssh.bin` via DVRIP `OPSystemUpgrade` (32 KiB blocks). Expect
   `Ret 100` frames, progress, **`Ret 515`**, reboot.
3. `ssh -i id_ed25519_v507 -p 2222 root@<ip>` → `Uid 0`.
4. Apply hardening, then **reboot from the guest** (`sync; reboot`) — do **not** cut
   power right after `set_info`: JFFS2 flush is asynchronous and can lose the config.
5. Verify with the production check script.

The full agent method is in the local analysis workspace
(`v507-upgrade/prod/PROD_SSH_V507_METHOD.md`).

## Recovery

- Official V5.07 package (`Ret 515`): restores vendor `/usr`; config kept.
- Downgrade to V5.01 official, then the V5.01 root/production package.
- SPI dump: exact restore (mandatory once available).

## Risks / limits

- **Not yet validated on physical V5.07 hardware**; QEMU covers upgrade, SSH, hardening,
  but real `rcS` timing, bind-mount, JFFS2 flush and USB/ethernet behaviour remain.
- SSH 2222 is root over the LAN; firewall it; key-only, no password fallback.
- Client private key is the root credential; losing it means restoring the official
  package and rebuilding.
- Baked host key is specific to this build; generate a new one for another camera.
- Voice prompts removed; official flash restores them.
- Future vendor firmware that enforces CRC/Mx8Q will reject this package.
- The static dropbear was built for the V5.01 family; it runs on V5.07 in QEMU (same
  ARM kernel ABI), but this is one of the points to confirm on hardware.

## Related

- [upgrade-root-v507.md](upgrade-root-v507.md) — V5.07 verifier finding and root variants
- [production-firmware.md](production-firmware.md) — V5.01 production image (validated on hardware)
- [hardening.md](hardening.md) — hardening fields
- [return-to-stock.md](return-to-stock.md) — recovery / downgrade
