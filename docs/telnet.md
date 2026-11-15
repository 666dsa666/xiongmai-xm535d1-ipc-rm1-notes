# Telnet — what works, what does not, and how to keep it

## State of this unit

| item | value |
|---|---|
| Firmware | `V5.01.R02.000A07F3.10010.346732.0000000` |
| Build time | 2024-09-14 15:08:59 |
| DVRIP (port 34567) | open, login `admin` / empty password works |
| telnet 23 | closed |
| telnet 4321 | closed |
| web UI 80 | open ("Web Viewer") |
| ONVIF 8899 | open |

## Attempt: Shell command through the upgrade descriptor

The classic Xiongmai method (implemented by
[`python-dvr`'s `telnet_opener.py`](https://github.com/vklimk/python-dvr/blob/master/telnet_opener.py)) logs in
over DVRIP and submits a fake upgrade package whose `InstallDesc` contains:

```json
"UpgradeCommand": [
  {"Command": "Shell", "Script": "busybox telnetd -F -p 4321 -l /bin/sh"}
]
```

The descriptor used here:

```json
{
  "Hardware": "XM535_X6E-WEQ_8M",
  "DevID": "000A07F31001000000000000",
  "CompatibleVersion": 2,
  "Vendor": "General",
  "CRC": "1ce6242100007636",
  "UpgradeCommand": [{"Command": "Shell", "Script": "busybox telnetd -F -p 4321 -l /bin/sh"}]
}
```

Result:

```
Ready to upgrade
Uploaded 100.00%
End of file
Waiting for upgrade...
{'Name': 'OPSystemUpgrade', 'Ret': 100, ...}
{'Name': 'OPSystemUpgrade', 'Ret': 100, ...}
{'Name': 'OPSystemUpgrade', 'Ret': 514, ...}
{'Name': 'OPSystemUpgrade', 'Ret': 6, ...}
```

`Ret 514` / `Ret 6` = the firmware rejected the package. Ports 23 and 4321 stayed closed, the camera
remained healthy (80/554/8899/34567 up).

**Conclusion:** on this 2024 firmware the unsigned `InstallDesc` + `Shell` path is closed (the post-2020
Xiongmai hardening). The method that worked on 2020-era XM boards does not apply here.

## Alternatives to get a shell

1. **XMTelnet** (Windows utility, post-2020 protocol) — the vendor community tool for opening telnet on
   newer XMeye firmware. It uses a "safety code" handshake with its author, so it is not something that
   can be automated or verified here.
2. **UART** — open the camera, find the debug UART (115200 8N1, XM535 boards typically expose one near the
   SoC), stop U-Boot, get a shell. Requires opening the device and a USB-TTL adapter.
3. **SPI** — full 16 MB dump with the CH341A; offline rootfs modification is possible but riskier than
   UART. See [`backup.md`](backup.md).

Nothing here is needed for RTSP/ONVIF, which already work (`stock-streaming.md`).

## Keeping telnet across a firmware upgrade

This only becomes relevant once a shell is obtained. Firmware upgrades replace the rootfs, so anything
written in `/etc` is lost. The persistence options, best first:

### 1. U-Boot environment — survives upgrades

Xiongmai firmware reads its configuration from the U-Boot environment. The relevant flags:

- `telnetctrl=1` — start the telnet service at boot
- `xmuart=0` — keep the UART console enabled/disabled as desired

From a root shell, using the vendor env tool:

```sh
armbenv -s telnetctrl 1
armbenv -s xmuart 0
```

or from the U-Boot prompt:

```
setenv telnetctrl 1
saveenv
```

The environment lives in its own flash area and is **not** rewritten by a normal firmware upgrade, so this
is the most upgrade-proof way to keep telnet available. (`telnet_opener.py` itself uses
`armbenv -s xmuart 0; armbenv -s telnetctrl 1` for exactly this purpose.)

### 2. `/mnt/mtd` configuration partition — usually kept

The writable JFFS2 settings partition (`/mnt/mtd`) normally survives firmware upgrades, unlike the rootfs.
A startup hook there (e.g. a script the vendor init already runs) can relaunch `telnetd`, but this depends
on the firmware's init scripts and can be wiped by a "full" upgrade.

### 3. Rootfs modification — not persistent

Editing `/etc/init.d/*` works only until the next upgrade, which replaces the read-only rootfs. Do not rely
on it.

### 4. The upgrade package itself

If you control the upgrade file, the vendor upgrade mechanism can carry commands (as the rejected attempt
above shows). A future signed/official package with a `Shell` command would run after the upgrade — but
that is exactly what this firmware now refuses for unsigned descriptors.

## Practical recommendation

- For **video**: no shell needed, stock RTSP/ONVIF already work.
- If you want a **persistent shell**, the realistic path is UART (or SPI), then set `telnetctrl=1` in the
  U-Boot environment so it survives upgrades.
- Keep a full flash dump before any of this.
