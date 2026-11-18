# Getting root — path matrix

Goal: obtain a shell on the XM535D1 without bricking the camera, ideally without opening
it. This page records what exists, what was tested, and what is worth trying.

## Summary

| Path | Status | Effort / risk |
|---|---|---|
| **UART console** | **Works by design**: `/etc/inittab` auto-logs root on the serial console | open the camera, find UART pads (not identified on this board revision yet), USB-TTL |
| SPI flash dump + offline patch | Possible (**FM25Q64**, 8 MiB, SOIC-8, CH341A) | needs a clip/programmer; no recovery button on the board |
| **DVRIP `OPTelnetControl`** | **Decoy**: `EnableKey` not validated; opens nothing (see below) | no hardware access, but no shell either |
| Unsigned upgrade (`InstallDesc` + `Shell`) | **Rejected on V5.01** (`Ret 514/6`), but V5.07 contains a "no pub, skip check Mx8Q" compatibility path | reverse `VerifyMx8QSign` / `doMetadataCheck`; craft package |
| Port **9530** "secret knock" | **Closed** on this unit (23/4321/9530 refused) | not available on this build |
| Vendor debug **12901** (`/usr/bin/debug`) | **Open**, gated by `telnetctrl`; RSA vendor handshake | vendor-only, not a user shell; firewall it |
| Older firmware | **No pre-2020 build for this SoC**; oldest known is V5.00.R02 (2024-04-18), not publicly downloadable | not a root path |

## Older firmware — what exists

The XM535D1/X6E-WEQ board is a 2024 product line (first firmware: **V5.00.R02**,
`...346732.0000010`, built 2024-04-18). Users on the ipcamtalk thread explicitly ask
whether *any* firmware below V5 exists ("e.g. 4.08") — no one has provided one. The
vendor portal keeps only the latest package per product ID (a scan of the neighbouring
IDs found only the latest file for each XM535D1 variant), and the OBS bucket does not
allow listing (403).

Even if a V5.00 archive is found, it is a **2024 build**: the Xiongmai hardening that
closed the old unsigned-upgrade/Telnet paths predates it (2020-2021). A downgrade may
work (people downgraded V5.05 → V5.01) but should not be expected to restore the old
backdoors. **Conclusion: downgrade is not a promising root route.** Do it only for
functional regressions, and never without a full SPI dump.

## What the current V5.07 firmware still contains

`user_sq/bin/Sofia` (strings / symbol names):

```
VerifyMx8QSign, no pub, skip check Mx8Q
VerifyMx8QSign, no pub, Mx8Q check failed
CUpgrader::doMetadataCheck no need check Mx8Q
CUpgrader::doMetadataCheck uparate file was craked NO Mx8Q!
Mx8QCheck   UpMx8Q   VerifyMx8QSign
OPTelnetControl   TelnetCommand   TelnetDisEnable
TelnetDebugOpen   TelnetDebugOpenForever   TelnetDebugClose
EnableKey   GetSaftyCode   telnetd
close 9530 port!   /mnt/mtd/Log/9530Disable
```

Interpretation:

1. **"no pub, skip check Mx8Q"** — an explicit compatibility path for packages without
   a public key. Worth reversing: it may be reachable by crafting an `InstallDesc` with
   the right fields (the naive fake package tried earlier was rejected — probably missing
   CRC/metadata values, not because the path is absent).
2. **`OPTelnetControl` + `EnableKey`/`GetSaftyCode`** — a DVRIP operation to turn telnet
   on. Community tools (XMTelnet) implement this handshake with a "safety code". The code
   to validate it is in `Sofia`; reversing it would give a **network-only root path**.
3. `TelnetDebugOpenForever` suggests a persistent debug mode, not just a one-shot.

## Recommended plan (in order)

1. **Static reverse of `Sofia`** (radare2 is available in the workspace):
   - locate the functions around `GetSaftyCode` / `EnableKey` / `OPTelnetControl`;
   - derive the challenge-response algorithm and the DVRIP message sequence;
   - test it against the camera (DVRIP `admin`/blank works, so sending the operation is
     easy).
2. If that fails, reverse `VerifyMx8QSign`/`doMetadataCheck` and try the **no-pub skip**
   upgrade path with a minimal `InstallDesc` (`Shell` command) — same idea as the old
   telnet-opener but with correct package metadata.
3. Keep **UART** as the fallback: open the camera, locate the pads (115200 8N1), catch
   U-Boot (`Ctrl+C`), take a full `sf read` dump over TFTP, then `setenv telnetctrl 1;
   saveenv`.
4. Only after a **verified full SPI dump** consider flashing an older firmware.

## Safety

- No documented recovery button/SD recovery mode on this board.
- A full **8 MiB** SPI dump (twice, compared) is the only safety net.
- Never flash a package for a different `Hardware`/`DevID`; the `Mx8Q`/metadata check will
  reject it at best, brick it at worst.
- Test network-level changes (PMS/cloud) separately from flashing.



## Network telnet — definitive reverse-engineering result

(2026-11-18, stock `V5.01.R02…` and official `V5.07.X02`, unit at `192.168.0.153`; validated in the `xm535` QEMU machine)

The DVRIP `OPTelnetControl` operation is a **decoy**:

- `GetSaftyCode` returns an RSA-1024 challenge (`Code`, 172-char base64) and creates
  `/var/T8aYMi2q` (32 hex) from
  `UPPER(MD5(sprintf("%sHk2W#5%d%d%d", derive8(SN,date), Y%109, M, D)))`;
- `{"Name":"OPTelnetControl","OPTelnetControl":{"TelnetCommand":"TelnetEnable","EnableKey":"…"}}`
  accepts **any** `EnableKey`, deletes `/mnt/mtd/Log/9530Disable` and returns `Ret=100`.
  There is no comparison, hash or RSA check of the key in the handler (`Sofia`
  `0x1bf1ac`, one `EnableKey` xref only), and **no port starts listening**;
- the `GetSaftyCode.Code` cannot be decrypted without the vendor RSA private key, but it
  is not used by the telnet path anyway.

The real debug shell is **`/usr/bin/debug` on TCP 12901**. It is started by `dvrHelper`
only when the U-Boot env variable **`telnetctrl=1`**, and its protocol authenticates with
an **RSA signature verified against the vendor public key** (`/mnt/mtd/Log/TelPubBase`).
After that handshake it can `popen()` root commands, but only the holder of the **vendor
private key** can get there. Its login record is `/mnt/mtd/Log/ns` =
`root:697SJ23Ru0j3M:…` (DES crypt(3), clear password not in firmware). Ports 23, 4321 and
9530 are closed; 12901 is the vendor backdoor and should be firewalled.

**Conclusion:** there is **no network-only root/telnet path** on this firmware. The
vendor's `EnableKey` gate was removed/ignored in V5.01/V5.07, but the only service it
would have enabled is the RSA-protected vendor debug channel. Root therefore still needs
**UART** (auto-login in `/etc/inittab`) or a **full 8 MiB SPI dump + offline rootfs patch**.
Details and emulator reproduction: [telnet.md](telnet.md), [emulation.md](emulation.md).
