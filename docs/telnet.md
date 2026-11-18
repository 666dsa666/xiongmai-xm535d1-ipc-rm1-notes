# Telnet / debug shell — what exists and what the reverse engineering proved

> **Which firmware was analysed?**
> The **real unit** runs stock `V5.01.R02.000A07F3.10010.346732.0000000`
> (build 2024-09-14). Its exact **V5.01.R02** package was later obtained and rebuilt into
> QEMU; the deep protocol reverse used the official **`V5.07.X02`** package. Crucially,
> the `/usr/bin/debug` binary (12901) is **byte-identical in V5.01 and V5.07**, so the
> 12901 analysis applies to the unit build. `Sofia` differs (V5.01 SHA `4d43505c…`,
> V5.07 `532045f0…`) but contains the same telnet strings; the V5.01 image was booted in
> QEMU (`xm535`) and the real unit's DVRIP behaviour matches.

Tested on `IPC-RM1-BLK535-2M6P V1.03`, XM535D1; see the note above for versions.

## TL;DR

- Ports **23, 4321 and 9530 are closed**. There is **no telnet daemon** on the stock firmware.
- DVRIP message **2040** / `OPTelnetControl` is a **decoy**: `EnableKey` is *not* validated;
  it only deletes `/mnt/mtd/Log/9530Disable` and answers `Ret=100`. It opens nothing.
- The real debug service is **`/usr/bin/debug` on TCP 12901**, enabled by the U-Boot env
  variable **`telnetctrl`**. It is a **vendor-only** binary protocol protected by an
  **RSA signature** (the device holds only the public key). After a successful handshake
  it can popen() root commands — but that requires the vendor RSA private key.
- **Conclusion: there is no network-only root/telnet path on this firmware.** Use the UART
  console (auto root login) or a full SPI dump and offline rootfs patch.

## DVRIP OP 2040 — `OnTelnetControl`

Handler in `Sofia` (ELF32, fixed base `0x10000`): `0x1bf1ac`, dispatch through
`0x1bf318` (Name) → `0x1bf334` (`== "OPTelnetControl"`) → `0x1bf36c` (`TelnetCommand`)
→ `0x1bf430` (`== "TelnetEnable"`).

For `TelnetEnable` the code:

1. `0x1bf448` reads `OPTelnetControl["EnableKey"]` as a JSON string;
2. `0x1bf45c` builds a temporary `std::string` and destroys it at `0x1bf468`;
3. `0x1bf460` `unlink("/mnt/mtd/Log/9530Disable")`;
4. `0x1bf470` replies `Ret=100`.

There is **exactly one** `EnableKey` string reference in the whole binary, and no
comparison, hash, RSA call or file lookup between reading it and returning. GDB confirmed
identical breakpoint traces for `"AAAA"`, the real `/var/T8aYMi2q` value and `""`.
`TelnetDisEnable` just creates `/mnt/mtd/Log/9530Disable` with `"close 9530 port!\n"`.

`GetSaftyCode` is a **separate cloud/RSA flow** and is not needed for telnet. It was
nevertheless fully reversed (see below) because it documents the vendor key material.

## The real debug service: `/usr/bin/debug`, TCP 12901

`/usr/bin/debug` (126 KB ARM binary, in `user_sq`):

- main `0x115b8`; gate at `0x14d90` = `atoi(envgetvalue("telnetctrl"))` plus an obfuscated
  licence path under `/mnt/custom`. If disabled it prints
  `LIBDVR : Debug: is Disabled!` and exits.
- **startup gate verified dynamically** (strace in `qemu-user` + gdb): the daemon also
  exits when `/mnt/mtd/Log/9530Disable` **or** `/mnt/custom/9530Disable` exists. This is
  the only link to DVRIP `TelnetEnable` (which unlinks the former) /
  `TelnetDisEnable` (which creates it); the check happens **once at startup**. Create the
  marker (root/clip) to keep the vendor debug service disabled.
- if enabled: `pthread_create(DebugProc_thrd)` binds **hard-coded port 12901**
  (`movw r0,#0x3265` at `0x14460`).
- packet layer: receiver is silent, `recv(fd,buf,1024)`, processing starts once >95 bytes
  are buffered. **Header = 16 bytes**: `sum = buf[8..15]`, checked with
  `XmDvr_RandNum_procString(buf,8,sum,0,1)` (`libXMcrypto` `0x210b4`), valid iff
  `(v&0xffff)|(v>>16) == 0xffff`; otherwise `LIBDVR : Invalid nDatLen!` and the connection
  closes. A five-stage handler table at `debug:0x3cf04` follows
  (`0x14008` Debug_handleConnect, `0x13b04`, `0x13378`, `0x13020`, `0x12d14`); stage 0
  does the random-token handshake, opens files and `calloc(0x122)`.
- packet layer: 8-byte random token, 8-byte checksum, length consistency, CRC32; dispatch
  Open / Run / Check / Update / RS session; fields named DDD/CCC/MMM/OOO/EEE.
- **authentication**: `RS` session performs an **RSA PKCS#1 signature verification**
  (`Debug RSV: V OK/V Failed`) against the public key in `/mnt/mtd/Log/TelPubBase`
  (fallback `/usr/bin/Squirrel/rs485/TelPubBase`). The device stores **only the public
  key**, so a client must hold the vendor's RSA private key.
- after authentication, the `Run` handler at `0x12c80` calls `popen(cmd,"r")` on the
  client-supplied command — root command execution, but behind the vendor key.
- login record: `LibXmDvr_Debug_setDefaultPasswd` writes
  `/mnt/mtd/Log/ns` = `root:697SJ23Ru0j3M:0:0:root:/:/bin/sh` (DES crypt(3) hash,
  salt `69`). The clear password is not stored in the firmware; the daemon **does not read
  `ns` during a 12901 session** (dynamic trace), so it is a local passwd line, not the
  12901 auth. The hash is not in a 15k XM/device wordlist nor in all numeric masks ≤8
  digits — not a trivial factory default.
- no `set_uboot_env` import **reachable** in the 12901 path: the protocol cannot enable
  itself or change `telnetctrl`/`xmuart`; invalid frames close before stage 0. A single
  connection can be used for a trivial DoS (resource exhaustion) but no RCE was reached
  without a valid RSA session.

On the unit documented here **12901 is reachable** (the vendor debug service is running).
It is a vendor backdoor, not a usable user shell; block it at the firewall if you do not
need vendor support.

## How to actually get a shell

1. **UART console** — `/etc/inittab` contains
   `::respawn:/sbin/getty -L ttyS000 115200 vt100 -n root -I "Auto login as root ..."`:
   root without password on the serial console. Locate the board UART pads, 115200 8N1.
   In U-Boot: `setenv xmuart 0` keeps the kernel console, `saveenv`.
2. **SPI dump + offline patch** — read the **8 MiB** flash (FM25Q64, SOIC-8, CH341A),
   patch the rootfs (e.g. add your own `telnetd`/SSH, disable cloud) and write it back.
   See [backup.md](backup.md).
3. The U-Boot env variable **`telnetctrl=1` only starts the vendor 12901 debug service**,
   not a telnet login. Do not mistake it for a usable shell.

## Appendix — `GetSaftyCode` / `/var/T8aYMi2q` (fully reversed and emulator-validated)

- `TelPubBase` is an AES-128-CBC encrypted blob; key
  `32DA1079E2B83679C22E8137C9223E53`, IV `6D353F2551502466473D2D0000000000`
  (IV reset per 128-byte chunk). Plaintext is an RSA-1024 public key
  (`N = 9F25737B…4217F7`, `E = 010001`).
- `S = UPPER(MD5(sprintf("%sHk2W#5%d%d%d", derive8(SN,date), Y%109, M, D)))`
  (32 hex), written to `/var/T8aYMi2q`.
- `derive8` (`0x3e18c`) = `MD5(SN[0] + "YYYYMMDD" + SN[9:])`, digest bytes 4..11 as
  16 lowercase hex, then chars 5..12 mapped `ascii % 10` (mode 0 at `0x3be818`).
- `Code = base64(RSA_public_encrypt(S))` with random PKCS#1 padding → 172 chars.
- Emulator proof: with an empty SN and `Y=M=D=0`, `S` is exactly
  `C52DEAF11BBF968925BA13DEC6D88EB5 = MD5("08217688Hk2W#5000")`.
- The returned `Code` cannot be decrypted without the vendor **private** key; and on this
  firmware `S`/`Code` are not used by `TelnetEnable` anyway.

## References

- CVE notes: [cves.md](cves.md).
- Root path matrix: [root.md](root.md).
- Reproducing the stock firmware in QEMU: [emulation.md](emulation.md).
- The 2020 "9530 secret knock" research does **not** apply to this build (see cves.md).
