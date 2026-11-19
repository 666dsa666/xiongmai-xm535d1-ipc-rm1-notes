# Firmware × vulnerability compatibility matrix

Last updated: 2026-11-19. XM535D1 / X6E-WEQ. This page tracks **what was actually
tested per firmware**, not assumptions. Dynamic results are from the QEMU harness; only
V5.01 and V5.07 were also exercised on a physical camera.

Legend: **HW** = real hardware; **QEMU** = exact firmware image under QEMU; **STATIC** =
binary/string analysis only; **—** = not tested; **NO** = tested absent/negative.

## A. Root / upgrade matrix

| Firmware | Official package | QEMU boot | Unsigned upgrade accepted | `Shell` root | Rooted `user` (persistent) | Production SSH | Hardware root validated |
|---|---|---|---|---|---|---|---|
| **V5.00.R02** (2024-04-18) | archived | QEMU | **QEMU** (`Ret 515`) | **QEMU** (marker) | **QEMU** (2323 root, reboot) | — | **no** |
| **V5.01.R02** (2024-09-14) | exact unit build | QEMU | **QEMU + HW** (`Ret 515`) | **QEMU + HW** | **QEMU + HW** | **HW** (2222) | **yes** |
| **V5.02.R02** | archived | QEMU | **QEMU** (`Ret 515`) | **QEMU** (marker) | **QEMU** (2323 root, reboot) | — | **no** |
| **V5.04.R02** | archived | QEMU | **QEMU** (`Ret 515`) | **QEMU** (marker) | **QEMU** (2323 root, reboot) | — | **no** |
| **V5.07.X02** (2025-09-06) | latest official | QEMU | **QEMU + HW** (`Ret 515`) | **QEMU** (uid 0) | **QEMU + HW** | **HW** (2222) | **yes** |

Portability: the **exact same V5.01 rooted `user-x` payload was accepted and rooted on
V5.00, V5.02, V5.04 and V5.07** in QEMU (same `CUpgrader`/`InstallDesc` gap); the V5.01
`Shell` package also ran on V5.04. Per-build payloads are still recommended (user partition
sizes differ, e.g. V5.02 is 0x40 shorter), and the build reported by DVRIP after a mixed
`/usr` is the payload's build.

## B. Security-surface matrix

| Firmware | CRC/Mx8Q enforced | ConfigImport msg 1540 write | HTTP bridge admin+empty | 12901 auth downgrade (VSC) | telnetd / 9530 | ONVIF/RTSP unauth | Boot-media root |
|---|---|---|---|---|---|---|---|
| **V5.00** | **NO** | **QEMU** (Ret 103) | **QEMU** (Ret 100) | **QEMU** | **NO** (static) | 200 / 401→200 (QEMU) | **QEMU PASS** |
| **V5.01** | **NO** | **QEMU** | **HW** (stock) | **QEMU** (full walk) | **NO** (HW + QEMU) | **HW** | **QEMU PASS** |
| **V5.02** | **NO** | **QEMU** (Ret 103) | **QEMU** (Ret 100) | **QEMU** | **NO** (static) | 200 / 401→200 (QEMU) | **QEMU PASS** |
| **V5.04** | **NO** (adds CRC-skip log) | **QEMU** (Ret 103) | **QEMU** (Ret 100) | **QEMU** | **NO** (static) | 200 / 401→200 (QEMU) | **QEMU PASS** |
| **V5.07** | **NO** (new verifier, flags off) | **QEMU** (Ret 103) | **QEMU** (Ret 100) | **QEMU** | **NO** (HW + QEMU) | **QEMU** | **QEMU PASS** |

## C. Shared facts / important nuances

- **Integrity verification is compiled in but never enabled** on every build (CRC/Mx8Q
  flags zero, setters called only via unused vtable slots). V5.04 adds a flag-gated CRC read,
  V5.07 refactors metadata/partition checks — still no authentication.
- `Shell`/`Script` root exec, ConfigImport 1540 traversal, HTTP bridge, GetSaftyCode/EnableKey
  decoy, 12901 `debug` and ONVIF unauth reads are shared across V5.00–V5.07.
- `/usr/bin/debug` (12901) is **byte-identical** across V5.00–V5.07.
- **50119 is a hidden telnetd** (`/sbin/timetest` → patched busybox `telnetd`), **not a time
  service**. It is launched by `dvrHelper` only when U-Boot env `telnetctrl==1`; stock env has
  no such key, so it does **not** listen on stock cameras. With `telnetctrl=1` (vendor
  maintenance state) the chain ConfigImport → `/mnt/mtd/Log/ns` → root/timetest gives a root
  shell; this is a post-exploitation/persistence add-on, not an independent stock primitive.
- **Boot-media root is portable in QEMU on all five versions** (ConfigImport → mtd5 cramfs
  `/init` + forged mtd0 U-Boot/env; persistent root 2323). Hardware test still needs a dump.
- SD recording: V5.05+ adds `Storage.SDCheckStatus`; V5.04 downgrade is the known workaround.
  The first hardware test with a 64 GB Samsung Evo Plus U3 did not initialise (unknown
  partition table / WFS read_parts failed), so the recording bug is **not yet reproduced**;
  a smaller or known-good card is needed.

## D. What remains to reach "everything tested on hardware"

Blocking requirement: a **verified SPI dump ×2** and a sacrificial camera.

| Step | Firmware | What to do | Needs |
|---|---|---|---|
| 1 | camera 3 | dump SPI ×2, verify, keep two copies | clip |
| 2 | V5.07 | re-apply production SSH on camera 3/`.161` — already HW-validated | package + dump |
| 3 | V5.01 | re-validate production SSH — already HW-validated | package + dump |
| 4 | V5.00 | flash QEMU-proven rooted payload, verify root, restore | dump + package |
| 5 | V5.02 | same | dump + package |
| 6 | V5.04 | same, verify changed verifier acceptance | dump + package |
| 7 | all | re-test ConfigImport/HTTP/12901/ONVIF on hardware where safe | dump |
| 8 | all | hardware-test boot-media root on a sacrificial unit after dump | dump + risk |

Until the clip arrives, no further QEMU-only cell is worth adding: all root surfaces are
already proven generic. The remaining work is physical/dump-bound.
