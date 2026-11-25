# Negative results

Routes investigated and abandoned: XMTelnet / port 9530, UART, U-Boot console, older firmware,
OpenIPC. Each entry says why it does not apply to this board.

## Summary

| Route | Verdict | Status |
|---|---|---|
| XMTelnet / CVE-2020-22253 port 9530 knock | 9530 subsystem absent; no telnetd to enable | **HW**, **STATIC**, **QEMU** |
| DVRIP `OPTelnetControl` `EnableKey` | decoy ([debug-services.md](debug-services.md)) | **QEMU**, **STATIC** |
| UART console | no usable pad on this board revision | **HW** |
| U-Boot password prompt | needs UART; unreachable | **UNTESTED** |
| Older firmware (pre-V5) | does not exist for this board | n/a |
| OpenIPC `xm535d1_lite` | reported to boot by OpenIPC, no video backend; not flashed here | **STATIC** |

## XMTelnet

XMTelnet is a paid Windows GUI that wraps public Xiongmai telnet exploits behind an offline
licence gate. It is not a new vulnerability and contains no vendor signing key.

- The 10-digit **Safety Code** is generated locally when the app starts, before any device IP is
  entered.
- The 12-digit **Secur Pass** is the reseller's keygen answer to that local code.
- A third field ("Activation code", base64 starting `V1.0.0`) is a licence token.
- The predecessor OpenTelnetV3 (2022) uses the same Safety Code / Secur Pass flow, so the pair
  is not a camera challenge. No evidence it is sent to the device.

Techniques underneath:

1. **CVE-2020-22253 / port 9530**: challenge-response (`OpenTelnet:OpenOnce` → `randNum:` →
   3DES-like `verify:OK` → `CMD:`) that starts `telnetd` on old Xiongmai/HiSilicon firmware
   (about 2016–2020). Default PSK `2wj9fsa2` or `/mnt/custom/TelnetOEMPasswd`. Public PoC:
   <https://github.com/Snawoot/hisilicon-dvr-telnet>; disclosure:
   <https://habr.com/en/articles/486856/>.
2. **DVRIP msg 2040 `OPTelnetControl`** on newer `Sofia`: a decoy on this board
   ([debug-services.md](debug-services.md)).

Why it fails on V5.01 and V5.07:

- no `OpenTelnet`/`OpenOnce`/`randNum:`/`verify:`/`TelnetOEMPasswd`/`2wj9fsa2` strings in romfs,
  custom or user (**STATIC**);
- no standalone `telnetd` binary or `telnetd`-named applet. The only telnetd is the hidden
  `timetest` applet on 50119, inactive by default ([debug-services.md](debug-services.md));
- QEMU listeners are 80/554/8899/34567 (+23000); a 9530 knock gets a TCP RST (**QEMU**);
  ports 23, 4321 and 9530 are closed on the cameras (**HW**).

## UART

- No usable UART pad on board revision `V1.03` (**HW**, owner-probed): the 3-pad group is I2C,
  the red point is the speaker, the 2×3 group is resistors. Photos: [hardware.md](hardware.md).
- Kernel console is `ttyAMA0` (bootargs). `/etc/inittab` starts a userspace getty on `ttyS000`
  (`getty … -n root`), which is not reachable.
- U-Boot env `xmuart=0` showed the kernel console in QEMU (not confirmed from code); useless
  without pads.
- `telnetctrl=1` only starts the vendor 12901 daemon, not a login.

## U-Boot password

OpenIPC firmware issue #1892 ("Clarification on how to downgrade XM530 Firmware needed") covers
the same XM535D1 / U-Boot family:

- recent U-Boot builds are password-protected; the known vendor-wide OEM default is
  **`#Ux6@9V&4_Rz`** (fallback `ubootpwd`);
- reachable only from a UART console, so not reachable on this board. Not verified in QEMU
  either (Ctrl+C does not reliably stop the emulated U-Boot) (**UNTESTED**);
- the issue's downgrade advice (an old XM530 image reflashes U-Boot and removes the password)
  applies to the XM530 archive (58 builds), not to XM535D1 / X6E-WEQ.

## Older firmware

- First firmware for this board family: `V5.00.R02` (`...346732.0000010`, built 2024-04-18). Not
  publicly downloadable. No build below V5 is known.
- The vendor portal keeps only the latest package per product ID; neighbouring IDs also expose
  only their latest file. The OBS bucket does not allow listing (403).
- OpenIPC `OpenIPC/xmupdates` (`firmware-archive` release, `archive/index.json`) holds one
  revision for `000A07F3` / X6E-WEQ: labelled `V5.00.R02`, but the inner update binary is
  `V5.07.X02` (sha256 `f9ed99f3…`, see [firmware.md](firmware.md)). Other XM535D1 variants also
  have one recent revision only.
- A downgrade adds no access: the unsigned upgrade already works on V5.01 and V5.07
  ([root.md](root.md)). Flashing another model's package (`Hardware`/`DevID` mismatch) is
  rejected at best, a brick at worst.

## OpenIPC

OpenIPC has `br-ext-chip-xiongmai/configs/xm535d1_lite_defconfig` (plus `xm535d2_lite`,
`xm535w1_lite`; D1/D2/W1 are separate chips). It targets Cortex-A5 (Thumb2), the XM530 family
kernel 3.10.103, 8 MB flash (`BR2_OPENIPC_FLASH_SIZE="8"`, matches this board), the
`xiongmai-osdrv-xm530v200` driver package and `ATBM603X` USB Wi-Fi.

The defconfig states there is no Majestic: its xm backend drives the XM530 media interface,
while the V200 series uses a different one (sys/vb/vpss/venc) linked into the vendor `Sofia`
with no shared library. Without Majestic there is no RTSP and no ONVIF. According to the
OpenIPC sources the lite image boots with a shell, `ipctool`, Wi-Fi and the vendor modules
(`general/package/xiongmai-osdrv-xm530v200/files/xm535d1/load_xiongmai`), but no video. OpenIPC was not flashed on any unit here (**STATIC**: source reading only).

Verdict: do not flash OpenIPC if video is needed; the stock firmware already streams
([firmware.md](firmware.md)). For shell/Wi-Fi experiments only, keep a full SPI dump to restore
([recovery.md](recovery.md)).

References: OpenIPC wiki `en/wifi-xm530.md`; OpenIPC board pages for XM535D1 devices
(X4-4GE2Q, X6M-4GEQ-A, IPG-X6E-WEQ, IPG-80X30PSB-WPN).
