# Official firmware V5.07.X02 — package and contents

Vendor download page:
<https://download.xm030.cn/d/MDAwMDE3NTJ=>

| field | value |
|---|---|
| Title | `000A07F3.1IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.OnvifS_V5.00.R02` |
| Version name | `IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.dss.OnvifS_V5.07.X02` (2025-09-06) |
| Published | 2025-09-18 |
| Archive | `000A07F3.1IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.OnvifS_V5.00.R02.zip` |
| Direct URL | <https://obs-xm-customer.obs.cn-east-2.myhuaweicloud.com/000A07F3.1IPC_XM535D1_X6E-WEQ_WIFIATBM6012BX_TB.at6012bx.Nat.OnvifS_V5.00.R02.zip> |
| Archive size | 7,561,447 bytes |
| Archive SHA-256 | `f9ed99f370953ef59e41a7e7656a2594854adf806b57029de3d883c7dd67a5e2` |

> The vendor page explicitly warns: the ZIP is **not** the upgrade file; unzip it and
> use the `.bin` inside (which is itself a ZIP-like container of uImages).

## InstallDesc (upgrade manifest)

The package contains `InstallDesc` with:

```
Hardware        = XM535_X6E-WEQ_8M
DevID           = 000A07F31001000003200000
WifiDriverType  = atbm6012b
CompatibleVersion = 3
Vendor          = General
CRC             = 395905494066
Mx8Q            = mK6dK2cGbICnsCr+y6AaekSbV80iEhoC8YWBZSYvTjnjAY/mQr4z4gRWzikGkgS6…
UpgradeCommand  = Burn u-boot.bin.img, u-boot.env.img, custom-x.cramfs.img,
                  uImage.img, romfs-x.cramfs.img, user-x.cramfs.img
```

The **`Mx8Q` signature** is what blocks the classic unsigned "fake upgrade + `Shell`
script" telnet-opener: this 2024/2025 generation verifies the upgrade package
(`VerifyMx8QSign` in `Sofia`). Do not expect the 2018 telnet-opener tricks to work.

## Partitions in the package

Each file is a U-Boot legacy uImage (64-byte header + payload):

| File | Payload |
|---|---|
| `u-boot.bin.img` | U-Boot |
| `u-boot.env.img` | U-Boot environment |
| `custom-x.cramfs.img` | CRAMFS v2 — `/mnt/custom` (vendor customisation, strings, JSON configs) |
| `uImage.img` | Linux kernel |
| `romfs-x.cramfs.img` | CRAMFS v2 — read-only rootfs (busybox, init scripts) |
| `user-x.cramfs.img` | **SquashFS 4.0 (xz)** — application + web UI (despite the name) |

Extraction notes:

- strip 64 bytes: `dd if=romfs-x.cramfs.img bs=64 skip=1 of=romfs.cramfs`;
- mount CRAMFS read-only with `fusecram romfs.cramfs /mnt/romfs`;
- extract the squashfs with `unsquashfs -d user_sq user.cramfs`;
- kernel/U-Boot are gzip payloads (the file utility reports the compression).

## What the image reveals

### Cloud/P2P is built into the stock firmware

`custom/CustomConfig/NetWork.custom`:

```json
"PMS": { "Enable": true, "ServName": "push.umeye.cn", "Port": 80, "BoxID": "" },
"NetNTP": { "Enable": true, "Server": { "Name": "time.windows.com", "Port": 123 } }
```

`PMS` is the **Xiongmai push/cloud service** (alarms, notifications, app wake-up).
`Sofia` (from `user_sq/bin/Sofia`) additionally contains:

- `CCloudAgentManager` (RPS/cloud agent, HTTP `GetRpsconfig`),
- `CCloudAlarmCli` (PMS alarm push, AI/cloud storage abilities),
- `DssVideoHelper` / `DssAudioHelper` / `CDssPushHelper`,
- `CXmCloudUpgrade` / `OnCloudUpgrade` (cloud-triggered firmware),
- `/mnt/mtd/Config/CloudDNS.conf`, `CloudAvailDNS.conf`, `cloudExAbility`,
  `cloudupgradeimp.flag`,
- `/mnt/mtd/Log/TUTKID` (ThroughTek/Kalay P2P device id),
- `Ability.TelnetDebugMode`, `/mnt/mtd/Log/9530Disable`.

So "cloud" is not a single switch in this firmware: it is PMS push + cloud agent/RPS +
P2P (TUTK) + cloud upgrade/cloud storage helpers. The reliable way to stop it is to cut
its network path (see [cloud-cut.md](cloud-cut.md)).

### Runtime configuration available over DVRIP

On a stock unit, the DVRIP (port 34567) account `admin` with a blank password can read
and write several config blocks. Confirmed readable/writable on the tested unit:

| Config name | Content |
|---|---|
| `NetWork.PMS` | `Enable`, `ServName=push.umeye.cn`, `Port`, `PushInterval` — **writable** |
| `NetWork.NetDHCP` | DHCP enable per interface |
| `NetWork.NetDNS` | primary/spare DNS |
| `NetWork.NetCommon` | IP/mask/gateway/ports (gateway appears DHCP-managed while DHCP is on) |

`NetWork.NetP2P`, `NetWork.P2P`, `NetWork.TUTK`, `NetWork.RPS`, `NetWork.Cloud` all
return `Ret 607` (unknown config) on this build — P2P is managed internally by
`Sofia`/cloud agent, not exposed as a simple config key.

IP addresses in these configs are stored as **byte-swapped hex**, e.g.:

| Address | Stored as |
|---|---|
| 192.168.0.1 | `0x0101A8C0` |
| 192.168.0.153 | `0x9900A8C0` |
| 192.168.0.254 | `0xFE00A8C0` |
| 255.255.255.0 | `0x00FFFFFF` |

## Version history (community thread)

[ipcamtalk: XM535 X6E WEQ Firmware](https://ipcamtalk.com/threads/xm535-x6e-weq-firmware.81071/)
lists `V5.00.R02.000A07F3…` (2024-04-18), `V5.01.R02…` (the build on this unit),
`V5.04`, `V5.05` and `V5.07.X02`. V5.05 is reported to break SD recording
("Recording partition error"); newer is not automatically better.

## Safety

- Upgrades are **signed and one-way**; there is no documented recovery button or SD
  recovery mode on this board.
- Keep a full 16 MB SPI dump (CH341A) if you plan to modify anything.
- Do not flash OpenIPC `xm535d1_lite` expecting video: the V200 media pipeline has no
  video backend ("No majestic yet").
- This repository does **not** redistribute the vendor firmware; use the vendor URL.
