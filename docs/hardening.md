# Hardening a rooted XM535D1 (V5.01)

This is the recipe applied to a spare camera after rooting it through the
[unsigned-upgrade path](upgrade-root.md). It turns a stock camera (blank admin password,
unauthenticated ONVIF/RTSP/snapshot, cloud enabled) into a **local-only, authenticated**
device while keeping the root shell available for maintenance.

Validated on `V5.01.R02.000A07F3.10010.346732.0000000` (2026-11-19). The same DVRIP config
names exist on V5.07 but the hardening wasn't re-tested on a physical V5.07 unit.

> This page assumes you already have root and a verified SPI dump. Keep the dump and the
> official package for recovery.
>
> For the final production variant with authenticated SSH (key-only, no 2323) and the
> hardening below already applied, see [production-firmware.md](production-firmware.md).

## 1. Admin password

The factory state has an **empty** admin password, which is also why the legacy HTTP
bridge accepts `admin` + any password. DVRIP msg **1488** changes it; the fields are the
*stored* hashes, not plaintext:

```python
from dvrip import DVRIPCam
cam = DVRIPCam(ip, user="admin", password="")   # factory empty password
cam.login()
old_stored = "tlJwpbo6"                         # sofia_hash("")
new_stored = cam.sofia_hash(new_plaintext)
cam.send(1488, {
    "EncryptType": "MD5",
    "NewPassWord": new_stored,
    "PassWord": old_stored,
    "SessionID": "0x%08X" % cam.session,
    "UserName": "admin",
})
```

After the change, verify:

- DVRIP login with the new plaintext: OK; with empty/old: fail;
- RTSP `user=admin_password=<new stored hash>` or `<new plaintext>`: `200 OK`;
  empty password: `401`;
- `/webcapture.jpg` without credentials: `401`;
- ONVIF `GetProfiles` without auth: `401 NotAuthorized`.

## 2. Remove extra accounts

The stock config can contain an extra admin account (e.g. `twhn`, or a user-created one)
in `System.ExUserMap` and the normal user list. Audit with `cam.getUsers()` and remove
anything you did not create:

```python
cam.delUser(name)   # DVRIP msg 1486
```

Keep at least the `admin` account. Re-check `getUsers()` afterwards.

## 3. Local-only network / cloud cut

Read the full `NetWork` object, change the fields below, then write the **whole object**
back (`set_info("NetWork", nw)` → `Ret 100`) and re-read it:

| field | value |
|---|---|
| `NetWork.PMS.Enable` | `false` |
| `NetWork.Nat.NatEnable` | `false` |
| `NetWork.OnlineUpgrade.Enable` | `false` |
| `NetWork.OnlineUpgrade.AutoCheck` | `false` |
| `NetWork.OnlineUpgrade.AutoUpgradeImp` | `false` |
| `NetWork.DisableXmServerConn` | `{"DisableAll":true,"DisableDSS":true,"DisableNAT":true,"DisableRPS":true}` |
| `NetWork.OnvifPwdCheckout.Enable` | `true` |
| `NetWork.NetNTP.Enable` | `false` (or point it at a LAN NTP server) |

Then set `Ability.TelnetDebugMode.Open=false` and reboot. A router-level WAN block is
still recommended as defence in depth (see [cloud-cut.md](cloud-cut.md)).

## 4. Vendor debug service

With root, create the boot marker used by `/usr/bin/debug`:

```sh
touch /mnt/mtd/Log/9530Disable
killall debug 2>/dev/null
```

This keeps 12901 (and 9530) closed across reboots. Verify after reboot:
`netstat -lntp` should show no 12901/9530 listener; the external scan should show
12901/9530/23 closed.

## 5. Root shell / firewall

The rooted camera still listens on **TCP 2323** (unauthenticated root shell from
[upgrade-root.md](upgrade-root.md)). Firewall it to a single management host or keep it on
an isolated VLAN; never port-forward it. If you no longer need it, restore the official
`user` partition.

Also block 12901, 23, 9530 and — if you do not need the cloud/P2P — 34567 outbound at the
router.

## 6. Before / after (validated on hardware)

| Check | Before | After |
|---|---|---|
| admin password | empty | strong, old refused |
| users | admin + extra admin | admin only |
| RTSP with empty password | 200 | 401 |
| RTSP with new password | — | 200 |
| ONVIF `GetProfiles` unauth | 200 | 401 / NotAuthorized |
| `/webcapture.jpg` unauth | 200 | 401 |
| legacy HTTP bridge, wrong password | `Ret 100` (bypass) | `Ret 203 Pwd error` |
| PMS / NAT / online upgrade / NTP | on | off |
| 12901 / 9530 / 23 | closed on this unit | closed |
| root shell 2323 | — | Uid 0 (still available for maintenance) |

## Residual issues

- Port **2323** is a root shell without authentication; it is a deliberate maintenance
  backdoor, not a production service.
- The HTTP legacy bridge still exists; it is only gated by the now non-empty admin
  password. Do not expose port 80.
- A factory reset restores the vendor defaults; re-apply and re-verify.
- Rotate any Wi-Fi PSK / reused password that was exposed by `ConfigExport` before the
  admin password was set (see [security.md](security.md)).
