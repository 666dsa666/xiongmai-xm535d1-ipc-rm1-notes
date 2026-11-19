# Firmware × vulnerability compatibility matrix

Last updated: 2026-11-19. XM535D1 / X6E-WEQ. This page tracks **what was actually
tested per firmware**, not assumptions. Two agents are filling the remaining cells
(`fw-compat-matrix`, `fw-static-diff`).

Legend:

- **HW** = validated on real hardware
- **QEMU** = validated on the exact firmware image in QEMU
- **STATIC** = binary/string analysis only
- **—** = not tested yet
- **NO** = tested and absent/negative
- **CHG** = code changed compared with V5.01/V5.07 (needs testing)

## A. Root / upgrade matrix

| Firmware | Official package | QEMU boot | Unsigned upgrade accepted | `Shell` root | Rooted `user` (persistent) | Production SSH | Hardware root validated |
|---|---|---|---|---|---|---|---|
| **V5.00.R02** (2024-04-18) | archived | QEMU | **QEMU** (`Ret 515`) | **QEMU** (marker after reboot) | — | — | **no** |
| **V5.01.R02** (2024-09-14) | exact unit build | QEMU | **QEMU + HW** (`Ret 515`) | **QEMU + HW** | **QEMU + HW** | **HW** (2222) | **yes** |
| **V5.02.R02** | archived | QEMU | — | — | — | — | **no** |
| **V5.04.R02** | archived | QEMU | — (verifier changes) | — | — | — | **no** |
| **V5.07.X02** (2025-09-06) | latest official | QEMU | **QEMU + HW** (`Ret 515`) | **QEMU** | **QEMU + HW** | **HW** (2222) | **yes** |

Notes:

- V5.00 `Shell` root was re-verified in QEMU (marker present before/after reboot).
- V5.01 and V5.07 were the only versions flashed on a physical camera.
- V5.02/V5.04 are bootable but their modified-package acceptance is **not tested** yet.
- Rooted `user` package is built per version; cross-version payloads were not assumed
  portable.

## B. Security-surface matrix

| Firmware | CRC/Mx8Q enforced | ConfigImport msg 1540 write | HTTP bridge admin+empty | 12901 auth downgrade (VSC) | telnetd / 9530 | ONVIF/RTSP unauth | Boot-media root |
|---|---|---|---|---|---|---|---|
| **V5.00** | **NO** (modified package accepted) | — | — | STATIC (same `debug` md5) | **NO** (static) | RTSP `password=_` 200, bare 401 (QEMU) | **QEMU PASS** |
| **V5.01** | **NO** | **QEMU** | **HW** (stock) | **QEMU** (full walk) | **NO** (HW + QEMU) | **HW** (ONVIF 200 before hardening) | **QEMU PASS** |
| **V5.02** | — | — | — | STATIC | **NO** (static) | — | **QEMU PASS** |
| **V5.04** | **CHG** (verifier changes) | — | — | STATIC | **NO** (static) | — | **QEMU PASS** |
| **V5.07** | **NO** (flags 0, setters unused) | **QEMU** | **QEMU** (stock) | **QEMU** | **NO** (HW + QEMU) | **QEMU** (200 unauth stock) | **QEMU** (persistent 2323) |

Shared/known facts:

- `/usr/bin/debug` (12901) is **byte-identical in V5.00–V5.07** (md5
  `f35fcd314982b9ce4cbb2140cf9c6cb1`): the VSC auth-downgrade and heap overflow are
  structurally shared; only V5.01/V5.07 were dynamically exercised.
- The whole 9530/telnetd subsystem is absent from the XM535D1 builds checked; no
  telnetd/9530 string or binary found.
- **Boot-media root (ConfigImport → mtd5 cramfs + forged U-Boot env) passes in QEMU on all
  five versions** (V5.00/V5.01/V5.02/V5.04/V5.07); hardware test is still pending a verified
  SPI dump. Only the version's own official U-Boot/env is needed; the method itself is shared.
- XMTelnet does not apply to this family (no 9530/telnetd; paid offline licence).
- ConfigImport/HTTP bridge are `Sofia`-level paths; only V5.01/V5.07 were tested
  dynamically.

## C. What remains to reach "everything tested on hardware"

Final goal: **all firmwares tested, QEMU results reproduced on hardware, no pending
verification except what requires a dump**.

Blocking requirement: a **verified SPI dump ×2** and a sacrificial camera. The third
camera (new in box) is the intended target.

| Step | Firmware | What to do | Needs |
|---|---|---|---|
| 1 | camera 3 | dump SPI ×2, verify, keep two copies | clip |
| 2 | V5.07 | re-apply V5.07 production SSH on camera 3 (or `.161`) — already HW-validated on `.161` | package + dump |
| 3 | V5.01 | HW re-validate production SSH on the sacrificial unit (already HW-validated on `.161`) | package + dump |
| 4 | V5.00 | build/validate a rooted `user`/Shell package, flash, verify root, then restore | dump + per-version package |
| 5 | V5.02 | same as V5.00 | dump + per-version package |
| 6 | V5.04 | same, verify the changed verifier acceptance | dump + per-version package |
| 7 | V5.00–V5.04 | re-test ConfigImport/HTTP/12901/ONVIF/RTSP per build on hardware (where safe) | dump |
| 8 | all | if desired, hardware-test the boot-media root on a sacrificial unit after dump | dump + risk accepted |
| 9 | — | mark every matrix cell HW/NO, remove all remaining "—" except physical-only | — |

Until the clip arrives, the only honest pending cells are the **per-version QEMU tests
in the two running agents** and the **hardware reproductions** above.

## D. Current conclusion

- **Best production path: V5.07.X02 + patched `user` image (root, SSH 2222, cloud off)** —
  already validated on real hardware on `.161`.
- V5.01 is the fallback with the same properties and more hardware history.
- V5.00/V5.02/V5.04 are **not needed as production**; they only need completion for the
  "all firmwares tested" goal.
- XMTelnet/9530, RSA-private-key and 12901-as-root are **abandoned/excluded**.
