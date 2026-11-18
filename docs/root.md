# Getting root — path matrix

Goal: obtain a shell on the XM535D1 without bricking the camera, ideally without opening
it. This page records what exists, what was tested, and what is worth trying.

## Summary

| Path | Status | Effort / risk |
|---|---|---|
| **UART console** | **Works by design**: `/etc/inittab` auto-logs root on the serial console | open the camera, find UART pads (not identified on this board revision yet), USB-TTL |
| SPI flash dump + offline patch | Possible (W25Q128, SOIC-8, CH341A) | needs a clip/programmer; no recovery button on the board |
| **Telnet opener over DVRIP** (`OPTelnetControl`) | **Present in firmware**, gated by `EnableKey`/`GetSaftyCode` | reverse the key handshake in `Sofia`; no hardware access |
| Unsigned upgrade (`InstallDesc` + `Shell`) | **Rejected on V5.01** (`Ret 514/6`), but V5.07 contains a "no pub, skip check Mx8Q" compatibility path | reverse `VerifyMx8QSign` / `doMetadataCheck`; craft package |
| Port **9530** "secret knock" | **Closed** on this unit (23/4321/9530 refused) | not available on this build |
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
- A full 16 MB SPI dump (twice, compared) is the only safety net.
- Never flash a package for a different `Hardware`/`DevID`; the `Mx8Q`/metadata check will
  reject it at best, brick it at worst.
- Test network-level changes (PMS/cloud) separately from flashing.


## Network telnet — reverse engineering results

(2026-11-18, firmware `V5.01.R02.000A07F3.10010.346732.0000000`, unit at `192.168.0.153`)

DVRIP message **2040 (`0x7f8`)** dispatches the `OnTelnetControl` handler
(`Sofia` function at `0x1bf1ac`). The protocol is:

1. `{"Name":"GetSaftyCode"}` → `{"GetSaftyCode":{"Code":"<base64>"}}` — a fresh
   **RSA-1024 challenge** (128 bytes, random on every call).
2. `{"Name":"OPTelnetControl","OPTelnetControl":{"TelnetCommand":"TelnetEnable","EnableKey":"…"}}`
   — enables telnet when `EnableKey` matches the challenge plaintext.
3. `{"Name":"OPTelnetControl","OPTelnetControl":{"TelnetCommand":"TelnetDisEnable"}}`
   — disables it.

Inside `Sofia`:

- the RSA **public** key is parsed from a text file (fields `N = …`, `E = …`) under
  `/usr/bin/Squirrel/rs485/` (on this build `TelPubBase`, 288-byte encrypted blob);
- the plaintext password is built with `snprintf("%sHk2W#5%d%d%d", …)` and stored in
  `/var/T8aYMi2q`;
- the returned `Code` is that password encrypted with the RSA public key, so `EnableKey`
  must be the password itself.

Setting `Ability.TelnetDebugMode.Open = true` is accepted and persists across a reboot,
but **does not open any telnet port** (23, 4321 and 9530 stay closed before/after reboot).

**Conclusion:** the RSA **private** key (a.k.a. the "super password" of the XMTelnet tool,
which asks the user to send a 10-digit code to the vendor service) is not in the firmware.
A network-only root path on this build needs that vendor secret or a successful
reverse-engineering of the keypair. **UART remains the realistic path.**
