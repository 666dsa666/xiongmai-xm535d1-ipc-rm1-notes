# Production firmware: authenticated SSH root (V5.01)

This page documents the **production image** built for the spare `XM535D1` camera after
the lab work: the camera boots into a normal vendor system, exposes **no unauthenticated
root shell**, and provides **SSH key-only root access on TCP 2222**. Cloud/PMS/NAT/online
upgrade/NTP are disabled, the vendor debug service stays off, and the web/ONVIF/RTSP
surfaces require the admin password.

> Status: **validated on real hardware** (2026-11-19) on a spare camera, and in QEMU on
> the exact V5.01 image. The first camera (`192.168.0.153`) was left stock.
> Base firmware: `V5.01.R02.000A07F3.10010.346732.0000000`.
> No SPI dump was taken before this deployment; the official package remains the
> recovery path until a dump is available.

## Deliverable

| Item | Value |
|---|---|
| Package | `v501_prod_ssh.bin` |
| SHA-256 | `07d4d356d1579b6931807777275b3ed0f4eb91b6ef80c260ba3b1f9f87ee5229` |
| Base | official V5.01 `_all.bin` — only `user-x.cramfs.img` differs |
| Root access | SSH key-only, `root@<ip>:2222` |
| Host key fingerprint | `SHA1:b1:59:69:ec:97:4e:09:db:d7:ec:fd:ee:68:c7:ee:04:8c:77:9b:80` |
| Client key fingerprint example | `SHA256:X6+YIP0PYU2IsM/Kc/iDKUakBsH3pSk0h9/GGfPBSMg` |

The package is built locally from your own official package; the private host key and the
client private key are **not** published.

## Design

The official package is kept byte-identical except for the `user` partition (mounted at
`/usr`). The custom `/usr` contains:

- **`/usr/bin/dropbear`** — dropbear 2024.86, static ARM, stripped, built with
  `--disable-zlib --disable-password-auth` (**key-only**, no SSH passwords).
- **`/usr/share/ssh/dropbear_host_key`** — ed25519 host key (mode 600), baked into the
  image. The fingerprint is printed above; generate a new one for another camera.
- **`/usr/share/ssh/authorized_keys`** — the client public key.
- **`/usr/share/ssh/passwd`** — copy of `/etc/passwd` with root home changed to
  `/mnt/mtd`; the boot hook bind-mounts it over `/etc/passwd` so dropbear looks for
  `/mnt/mtd/.ssh/authorized_keys` (dropbear only supports `~/.ssh/authorized_keys`).
- **`/usr/bin/quick_venc.sh`** — boot hook run by `rcS`:
  - creates `/mnt/mtd/Log/9530Disable` (vendor debug off);
  - copies the authorized key to `/mnt/mtd/.ssh/` with correct modes;
  - bind-mounts the modified `passwd`;
  - starts `dropbear -r … -p 2222 -P /tmp/dropbear.pid -E`.
- vendor `/usr/share/music` (voice prompts) removed to fit the 4,544 KiB `user`
  partition; the squashed payload is 4,468,736 bytes (limit 4,652,992).

No `shd`, no 2323, no vendor debug, no unauthenticated management service.

## Hardening applied after the flash

Applied over DVRIP and persisted in `/mnt/mtd`:

- strong random admin password (web/DVRIP/RTSP);
- all accounts except `admin` removed;
- `NetWork.PMS.Enable=false`;
- `NetWork.Nat.NatEnable=false`;
- `NetWork.OnlineUpgrade.Enable/AutoCheck/AutoUpgradeImp=false`;
- `NetWork.DisableXmServerConn` = all true;
- `NetWork.OnvifPwdCheckout.Enable=true`;
- `NetWork.NetNTP.Enable=false`;
- `Ability.TelnetDebugMode.Open=false`;
- `/mnt/mtd/Log/9530Disable` present.

## Build

```bash
# cross toolchain + dropbear source
arm-linux-gnueabihf-gcc --version
# build dropbear (static, key-only)
./configure --host=arm-linux-gnueabihf --disable-zlib \
  --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
  --disable-pututline --disable-pututxline CFLAGS="-Os" LDFLAGS="-static"
# add "#define DROPBEAR_SVR_PASSWORD_AUTH 0" to localoptions.h, then:
make PROGRAMS="dropbear dropbearkey"
arm-linux-gnueabihf-strip dropbear

# host key (server) and client key
dropbearkey -t ed25519 -f dropbear_host_key
ssh-keygen -t ed25519 -f id_ed25519_client -C "camera-prod"

# user tree
#   vendor /usr (unsquashfs) + dropbear + share/ssh/{host_key,authorized_keys,passwd}
#   + bin/quick_venc.sh; remove share/music
mksquashfs user_prod custom_prod.sq -comp xz -Xbcj arm -b 131072 -noappend -all-root
truncate -s 4652992 custom_prod_padded.sq
python3 agent_camfw2_mkzip.py --src v501_official.bin --out v501_prod_ssh.bin \
  --wrap user-x.cramfs.img=custom_prod_padded.sq
```

The exact scripts used are in the analysis workspace
(`stack/build/build_prod_ssh.sh`, `stack/tools/agent_camfw2_*`,
`stack/tools/cam2_upload_any.py`, `cam2_prod_harden.py`, `cam2_prod_verify.py`).

## Deployment

> Same cautions as [upgrade-root.md](upgrade-root.md): spare camera, isolated LAN, and
> ideally a verified SPI dump first. The package is V5.01-only.

1. Confirm the camera is on V5.01 and export its config (`ConfigExport`) / note its
   credentials. Admin `admin` + empty is the factory state.
2. Upload `v501_prod_ssh.bin` over DVRIP `OPSystemUpgrade` (or web UI). Expect progress
   up to `Ret 100`, then **`Ret 515`**, then an automatic reboot.
3. Test SSH:
   ```bash
   ssh -i id_ed25519_client -p 2222 -o StrictHostKeyChecking=accept-new \
       root@<camera-ip> 'cat /proc/self/status; netstat -lntp'
   ```
   Expect `Uid: 0 0 0 0`, dropbear on 2222, no 2323/12901/9530.
4. Apply the hardening config over DVRIP (change admin password first, then the NetWork
   fields above; remove extra accounts last) and reboot.
5. Verify the table below; then the camera is production.

## Verification (real hardware, after reboot)

| Check | Result |
|---|---|
| SSH 2222 | open, key-only, root (Uid 0) |
| 2323 / 12901 / 9530 / 23 | closed |
| RTSP with empty password | 401 |
| RTSP with new password/hash | 200 |
| ONVIF `GetProfiles` without auth | 401 NotAuthorized |
| `/webcapture.jpg` without auth | 401 |
| legacy HTTP bridge, wrong password | `Ret 203 Pwd error` |
| DVRIP admin/new password | OK |
| users | `admin` only |
| PMS / NAT / OnlineUpgrade / NTP | off |
| `DisableXmServerConn` | all true |
| `OnvifPwdCheckout` | true |

QEMU (same V5.01 image): SSH key login, one-shot marker, full reboot → SSH again, no
2323. On the real camera the package was applied, hardened, rebooted and **re-applied a
final time**; SSH survived each reboot.

## Recovery

- Re-upload the **official V5.01 package** (`v501_official.bin`, sha
  `34e75c27…`) over DVRIP/web: restores the vendor `user` partition and removes SSH/root.
  The hardened `/mnt/mtd` config is preserved, so the admin password remains valid.
- If SSH access is lost: restore the official package (network admin/web), rebuild a
  package with a fresh host key and client key if needed.
- Preferably take a **full 8 MiB SPI dump ×2** as soon as the clip is available; it is
  the only recovery if the network/boot fails.
- A web-UI factory reset restores vendor config; re-apply hardening afterwards.

## Residual risks

- Port **2222 is root SSH on the LAN** — firewall it to the management host; never
  forward it.
- The client private key is the root credential: protect it; do not commit it.
- The baked host key is shared if the same package is deployed to several cameras;
  generate a per-camera host key.
- No SPI dump yet; recovery currently depends on DVRIP/web.
- Voice prompts were removed from `/usr`; restore the official package if needed.
- The HTTP bridge code remains (password-gated); do not expose port 80.
- Not tested on V5.04/V5.07; this package targets V5.01.

## Related

- [upgrade-root.md](upgrade-root.md) — unsigned-upgrade root mechanism and lab package
- [hardening.md](hardening.md) — hardening steps (this production image applies them)
- [security.md](security.md) — exposure model
- [backup.md](backup.md) — SPI dump
