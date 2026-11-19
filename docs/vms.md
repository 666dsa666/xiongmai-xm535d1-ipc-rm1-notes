# VMS PC + XM535D1 — account trap and working setup

Tested with **VMS 2.0.28.1** against a **V5.07.X02** XM535D1 (`192.168.0.161`).

## Working device setup

Add/edit the device as:

| Field | Value |
|---|---|
| Type | **Adresse IP** |
| IP | camera IP (e.g. `192.168.0.161`) |
| Port | `34567` |
| User | **`admin`** |
| Password | the camera admin password |

Do **not** leave VMS on the `jfxe` account.

## The cloud service-account trap (error 607)

Cloud pairing creates a **second admin service account**. Its login is **per device**:
`jfxe` on the tested `.161`, **`twhn`** on `.153` — do not hardcode `jfxe`. On V5.07 it cannot be
deleted (`DelUser` → `Ret 101`), but it can be downgraded to group `user` and given a strong
random password.

VMS may use this service account for part of its configuration/GetConfig path. If VMS is
configured with it while that account has been neutralised, the camera still connects and
live/storage work, but VMS shows:

- `Version du système — Obtenir la configuration — Erreur inconnue-607`
- same 607 on the stream/encoder page
- sometimes a misleading "Pas d'alimentation"

Fix: in VMS **Gestion des appareils → edit the device connection → User = `admin`**, with
the admin password.

## Isolated causes (all tested on hardware, with reboot)

| Change on stock V5.07 | VMS version/config page |
|---|---|
| stock, admin empty | works |
| `Nat.NatEnable=false` | works |
| `DisableXmServerConn` all true | works |
| PMS + OnlineUpgrade + NTP off | works |
| strong admin password | works |
| production custom firmware (root/SSH) | works |
| `OnvifPwdCheckout=true` | works |
| **cloud-created service account downgraded to `user`** | **607** |

So the blocking factor is **the VMS account selection**, not the cloud cut, not the custom
firmware and not the admin password.

## Recommended final configuration

- `admin`: strong password, group `admin`.
- cloud-created service account (`jfxe` on `.161`, `twhn` on `.153`; login varies): group `user`, strong random password (neutralised).
- VMS device connection: **admin** + admin password.
- Cloud cut and hardening can stay enabled.

If the camera is re-paired through the cloud, the service account may be recreated/reset; re-check its login/group/password and the VMS account afterwards. To identify it, use DVRIP `getUsers` and look for the second admin account created at pairing.

## Web UI vs VMS

The camera's built-in web UI is only a login shell for the Windows **VideoPlayTool** ActiveX
plugin (menus Preview/Playback/Alarm/Remote Setting, all delegated to the plugin). It is not
needed for VMS or for local RTSP/ONVIF/DVRIP use.
