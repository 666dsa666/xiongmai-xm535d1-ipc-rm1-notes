# XMTelnet: what it is, and why it does not apply to the XM535D1

## Verdict

**XMTelnet is a paid Windows GUI that wraps public Xiongmai telnet exploits behind an
offline licence gate.** It is not a new vulnerability and it does not contain a vendor
signing key.

- The 10-digit **Safety Code** is generated **locally when the app starts**, before any
  device IP is entered.
- The 12-digit **Secur Pass** is the reseller's keygen answer to that local code.
- A third field ("Activation code", base64 starting `V1.0.0`) is a licence token.
- The predecessor **OpenTelnetV3** (2022) uses the same Safety Code/Secur Pass flow,
  before the "post-2020 protocol" existed — so the pair cannot be a camera challenge.
- No evidence that the Safety Code/Secur Pass is sent to the device.

In other words: the tool is a **front-end for known exploits**, sold with a licence
check. The actual camera techniques underneath are:

1. **CVE-2020-22253 / port 9530** — challenge-response
   (`OpenTelnet:OpenOnce` → `randNum:` → 3DES-like `verify:OK` → `CMD:`) that starts
   `telnetd` and a debug service on **old Xiongmai/HiSilicon** firmware (≈2016–2020),
   default PSK `2wj9fsa2` or `/mnt/custom/TelnetOEMPasswd`.
   Public PoC: <https://github.com/Snawoot/hisilicon-dvr-telnet>, disclosure:
   <https://habr.com/en/articles/486856/>.
2. **DVRIP msg 2040 `OPTelnetControl`** — `TelnetEnable` + `EnableKey`, `GetSaftyCode`,
   `TelnetDisEnable` (+ the `/mnt/mtd/Log/9530Disable` marker) on newer `Sofia`
   firmware.

## Why it cannot work on the XM535D1 (V5.01 and V5.07)

Checked on the actual firmware and in QEMU:

- the whole **9530 subsystem is absent**: no `OpenTelnet`/`OpenOnce`/`randNum:`/
  `verify:`/`TelnetOEMPasswd`/`2wj9fsa2` strings in romfs, custom or user;
- **no `telnetd` binary** and no telnet applet in busybox;
- QEMU listeners are only 80/554/8899/34567 (+23000); a public 9530 knock gets a
  **TCP RST**;
- `TelnetDebugOpen*` returns `Ret 103`; `TelnetEnable` returns `Ret 100` but only
  unlinks the marker (the `EnableKey` value is dead code);
- the only remote artefact is DVRIP `GetSaftyCode` → starts `/usr/bin/debug` on **12901**;
  that service has a client-selectable auth downgrade (weak VSC mode) and a pre-auth heap
  overflow, but its post-auth `Run` command is the fixed literal `timetest`, so there is no
  arbitrary root command. See [debug-12901.md](debug-12901.md); no vendor private key is
  present in the firmware in any case.

⇒ do **not** buy/use XMTelnet for this camera; there is no telnetd to enable.

## What to use instead

- **Root on V5.01:** the unsigned-upgrade channel ([upgrade-root.md](upgrade-root.md)),
  and the production SSH image ([production-firmware.md](production-firmware.md)).
- **Latest V5.07:** the same upgrade channel is the only realistic network path
  (`InstallDesc` `Shell`/`Script` and/or replaced `user` squashfs). The V5.07 verifier
  (`doMetadataCheck`/`doPartitionCheck`) is stricter and must be validated in QEMU;
  keep an SPI dump and prefer UART/SPI as the fallback.
- **Physical fallback:** UART or full 8 MiB SPI dump ([backup.md](backup.md)).

## Related

- [cves.md](cves.md) — CVE-2020-22253 and family CVE mapping
- [upgrade-root.md](upgrade-root.md) — the working upgrade root path
- [ota.md](ota.md) — V5.07 is the latest offered firmware
