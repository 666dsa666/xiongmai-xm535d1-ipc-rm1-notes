# Vendor debug services

The vendor debug daemon on TCP 12901, the hidden BusyBox telnetd on TCP 50119, DVRIP
`GetSaftyCode`, and the DVRIP OP 2040 `OPTelnetControl` decoy. None is a stock root path.

## Summary

| Item | Default state | Gate / trigger | Result | Status |
|---|---|---|---|---|
| TCP 12901 `/usr/bin/debug` | closed on stock and production | U-Boot env `telnetctrl=1`, started by `dvrHelper` or by DVRIP `GetSaftyCode`; blocked by `9530Disable` marker | auth bypassable (VSC), post-auth runs fixed `timetest`; pre-auth heap overflow (DoS) | **HW** (closed), **QEMU** |
| TCP 50119 BusyBox `timetest` | inactive | `dvrHelper`, only with `telnetctrl==1` | hidden root telnetd when started | **HW** (closed), **STATIC** |
| DVRIP `GetSaftyCode` | available after DVRIP login | none | writes `/var/T8aYMi2q`, returns RSA-encrypted `Code`, starts 12901 if gate allows | **QEMU**, **STATIC** |
| DVRIP OP 2040 `OPTelnetControl` | available after DVRIP login | none | `TelnetEnable` deletes a marker, opens nothing | **QEMU**, **STATIC** |
| TCP 23, 4321, 9530 | closed | none found | no telnetd | **HW** |

The stock U-Boot environment has no `telnetctrl` key. Mitigation: `/mnt/mtd/Log/9530Disable`
stops 12901 (`/usr/bin/debug` exits at start); 50119 is not affected by the marker and stays
off only while `telnetctrl` is unset. Block both ports at the firewall. The production image starts
neither ([production.md](production.md)).

## DVRIP OP 2040 `OPTelnetControl` (decoy)

`Sofia` (ELF32, fixed base `0x10000`), V5.07 handler `0x1bf1ac`. Dispatch: `0x1bf318` (Name) →
`0x1bf334` (`== "OPTelnetControl"`) → `0x1bf36c` (`TelnetCommand`) → `0x1bf430`
(`== "TelnetEnable"`).

```json
{"Name":"OPTelnetControl","OPTelnetControl":{"TelnetCommand":"TelnetEnable","EnableKey":"…"}}
```

For `TelnetEnable`:

1. `0x1bf448` reads `EnableKey` as a JSON string;
2. `0x1bf45c` builds a temporary `std::string`, destroyed at `0x1bf468`;
3. `0x1bf460` `unlink("/mnt/mtd/Log/9530Disable")`;
4. `0x1bf470` replies `Ret 100`.

- One `EnableKey` xref in the whole binary; no compare, hash, RSA call or file lookup.
- **QEMU** (GDB): identical traces for `"AAAA"`, `""` and the real `/var/T8aYMi2q` value. On
  V5.01, empty, `"AAAA"`, file value, lowercase, MD5, SHA-256, `Code` and `SessionID` all give
  `Ret 100`, delete the marker and open no port.
- `TelnetDisEnable` creates `/mnt/mtd/Log/9530Disable` containing `"close 9530 port!\n"`.
- `TelnetDebugOpen*` returns `Ret 103`.
- V5.01 handler = V5.07 address minus `0x17C14` (entry `0x1a7598`, `EnableKey` xref
  `0x1a7834`), instruction-identical.

The only effect of `TelnetEnable` is to allow the next 12901 start (see gate below).

## DVRIP `GetSaftyCode`

- Writes `/var/T8aYMi2q` (32 hex) and returns `Code`, a 172-char base64 RSA-1024 ciphertext.
- `/var/T8aYMi2q` is also created at boot (about 20–22 s, without any DVRIP request);
  `GetSaftyCode` rewrites the same deterministic value. It depends on device identity, not on
  the session.
- Success branch calls `LibXmDvr_Debug_open()` (V5.01 `0x1a7ff4`, V5.07 `0x1bfc08`,
  instruction-identical): `GetPidByName("debug")`, otherwise `system("debug&")`. An
  authenticated DVRIP client (stock: `admin`, empty password) can start 12901 remotely if
  `telnetctrl=1` and no marker exists.

Derivation (**STATIC**, validated in QEMU):

```
S       = UPPER(MD5(sprintf("%sHk2W#5%d%d%d", derive8(SN, date), Y%109, M, D)))
derive8 = MD5(SN[0] + "YYYYMMDD" + SN[9:]), digest bytes 4..11 as 16 lowercase hex,
          chars 5..12 mapped ascii % 10      (Sofia 0x3e18c, mode 0 at 0x3be818)
Code    = base64(RSA_public_encrypt(S))      (random PKCS#1 padding)
```

- Emulator check: empty SN and `Y=M=D=0` give
  `S = C52DEAF11BBF968925BA13DEC6D88EB5 = MD5("08217688Hk2W#5000")`.
- `TelPubBase` is AES-128-CBC encrypted: key `32DA1079E2B83679C22E8137C9223E53`,
  IV `6D353F2551502466473D2D0000000000` (IV reset per 128-byte chunk). Plaintext is an RSA-1024
  public key (`N = 9F25737B…4217F7`, `E = 010001`).
- `Code` cannot be decrypted without the vendor private key. No private key, certificate or
  CRT material exists in any extracted firmware tree.

## TCP 12901 `/usr/bin/debug`

Binary byte-identical in V5.00, V5.01, V5.02, V5.04 and V5.07 (MD5
`f35fcd314982b9ce4cbb2140cf9c6cb1`, 126,180 B, ARM32 EABI; SHA-256 in [firmware.md](firmware.md#official-builds)).

### Start gate

- `main` `0x115b8`; gate at `0x14d90` = `atoi(envgetvalue("telnetctrl"))` plus an obfuscated
  licence path under `/mnt/custom`. If disabled: `LIBDVR : Debug: is Disabled!`, exit.
- Also exits if `/mnt/mtd/Log/9530Disable` or `/mnt/custom/9530Disable` exists (**QEMU**:
  strace + GDB). The check runs once at startup.
- Started by `dvrHelper` when `telnetctrl=1`, or by `GetSaftyCode`.
- Listener: `pthread_create(DebugProc_thrd)`, hard-coded port 12901 (`movw r0,#0x3265` at
  `0x14460`).
- No `set_uboot_env` reachable from the protocol: it cannot enable itself or change
  `telnetctrl`/`xmuart`.

### Protocol

Five sequential stages: `Open → Update → RS → Check → Run`. Handler table at `debug:0x3cf04`
(`0x14008` `Debug_handleConnect`, `0x13b04`, `0x13378`, `0x13020`, `0x12d14`).

- Receiver is silent: `recv(fd, buf, 1024)`, processing starts once more than 95 bytes are
  buffered.
- 16-byte header: 8-byte random token, 8-byte sum `buf[8..15]` checked by
  `XmDvr_RandNum_procString(buf, 8, sum, 0, 1)` (`libXMcrypto` `0x210b4`), valid iff
  `(v&0xffff)|(v>>16) == 0xffff`. Otherwise `LIBDVR : Invalid nDatLen!` and close. Length
  consistency and CRC32 follow. Field names: DDD/CCC/MMM/OOO/EEE. Freely forgeable, not a
  security control.
- `Open` (no auth): ephemeral 1024-bit RSA key; reply with public N/E and 24-byte connection
  seeds. Stage 0 also opens files and `calloc(0x122)`.
- `Update` (no auth): client uploads its own RSA public key (for reply encryption) and a
  licence text `N=…,E=…,`.
- `RS` (authentication), mode chosen by the client field length:
  - short (≤100 bytes) → **VSC**: reads `/var/T8aYMi2q`, derives 10 decimal digits and compares.
    Offline-computable from device data (SN/date, unsalted MD5);
  - long (>100 bytes) → **RSV**: genuine RSA PKCS#1 v1.5 verification against the public key in
    `/mnt/mtd/Log/TelPubBase` (fallback `/usr/bin/Squirrel/rs485/TelPubBase`).
- `Check`: compares a client value to a constant plus connection seeds (client-computable).
- `Run`: `popen("timetest", "r")`. Fixed literal, not client-controlled.

### Findings

| # | Severity | Finding |
|---|---|---|
| F1 | High | **Auth downgrade**: RSA is optional; the VSC path accepts the offline-computable safety code. No vendor key needed. |
| F2 | High (pre-auth) | **Heap overflow in `Update`**: `E` up to 257 bytes copied to `calloc(0x122)+0x102`, up to 225 bytes past the chunk, with only `Open` + `Update`. |
| F3 | Medium | Client-supplied N/E are attacker-controlled; the N copy also overflows the nominal `PKP` layout. Used only for reply encryption. |
| F4 | Low | `popen()` argument fixed to `timetest`: no command injection. |
| F5 | Info | Framing checksum and seed obfuscation are not security controls. |

**QEMU** (qemu-arm-static chroot): a short-field client completed all five stages, the RSA
verify breakpoint never fired; a long-field client hit RSA verify and failed as expected.

### Exploitation attempts (QEMU)

| Attempt | Result |
|---|---|
| `PATH` hijack of `timetest` | Fails. Daemon `PATH` is `/sbin:/usr/sbin:/bin:/usr/bin` (inherited init → `rcS` → `dvrHelper`), all read-only. `ConfigImport` extraction drops the executable bit (0644) |
| `core_pattern` / hotplug helper | Blocked. `/proc/sys/kernel/core_pattern` is writable via ZIP traversal, but every process has `RLIMIT_CORE=0`, and helpers must be executable |
| `Update` with empty `N=` and valid `E` | Clean pre-auth DoS: `Debug PK: if (nN: 0 < 128)` → SIGSEGV in `mpi_bitlen` |
| `Update` with long `E` | Adjacent chunk corrupted, control-flow influence (`PC=0x3ff1bc18`, `LR` = ASCII bytes of the client key). No reliable exploit (uClibc heap, no leak primitive) |
| Single connection held open | Trivial DoS (resource exhaustion) |

### `/mnt/mtd/Log/ns`

`LibXmDvr_Debug_setDefaultPasswd` writes `/mnt/mtd/Log/ns` =
`root:697SJ23Ru0j3M:0:0:root:/:/bin/sh` (DES crypt(3), salt `69`), bind-mounted over
`/etc/passwd`. The daemon does not read it during a 12901 session (dynamic trace): it is a local
passwd line, not the 12901 auth. Not found in a 15k Xiongmai/device wordlist nor in numeric
masks up to 8 digits.

## TCP 50119 BusyBox `timetest`

- `/sbin/timetest` → `../bin/busybox` (BusyBox 1.33.1). The custom `timetest` applet is a
  patched `telnetd` on TCP 50119, not a time service. It is in the firmware, not a QEMU artifact.
- Launched by `dvrHelper` only when U-Boot env `telnetctrl==1`. Stock env has no such key:
  closed on stock and production scans (**HW**).
- With `telnetctrl=1` (vendor maintenance state), `ConfigImport` → `/mnt/mtd/Log/ns` →
  `timetest` login gives a root shell. This is a post-exploitation/persistence add-on, not an
  independent stock primitive.
- 12901 `Run` calls this same applet, so `popen("timetest")` is not a missing-binary primitive.
