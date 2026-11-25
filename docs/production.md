# Production image: authenticated SSH root

Custom firmware package that keeps the vendor system intact, adds key-only root SSH on
TCP 2222, closes port 80 and runs no unauthenticated root service. Covers variants, image
content, build, install with pre/post-flash checklists, recovery and residual risks.

## Variants

| | V5.01 | V5.07 | V5.07 block80 (current) |
|---|---|---|---|
| Package | `v501_prod_ssh.bin` | `v507_prod_ssh.bin` (7,452,850 B) | `v507_prod_ssh_block80.bin` |
| Base | official `V5.01.R02.000A07F3.10010.346732.0000000` `_all.bin` | official `V5.07.X02.000A07F3.10010.346732.0000000` `_all.bin` (build 2025-09-06) | same as V5.07 |
| Changed part | `user-x.cramfs.img` only | `user-x.cramfs.img` only | `user-x.cramfs.img` only |
| `user` squashfs size | 4,468,736 B | 4,456,448 B | 4,460,544 B |
| Port 80 | open (password-gated) | open (password-gated) | **closed** by the `block80.so` `LD_PRELOAD` bind shim |
| NTP in the build's hardening | off | off (initial tests) | **on**, public servers (see [hardening.md](hardening.md#time-and-ntp)) |
| Status | **HW** (one camera, later moved to V5.07), **QEMU** | **HW** (cam2, then all three), **QEMU** (from stock V5.07 and from rooted V5.01) | **HW** on cam1, cam2, cam3 |

All three cameras run the V5.07 block80 variant. The V5.01 package is historical; it only
installs over V5.01. Each variant has its own host key and client key.

The shim refuses `Sofia`'s bind on TCP 80; the `Sofia` binary is unchanged.
`NetWork.NetCommon.HttpPort` is cosmetic (the server stays on 80) and the camera has no
`iptables`/`nft`, so a preload hook is the on-device way to close 80 (**HW**).

## Why the vendor upgrader accepts it

The `Mx8Q` signature and CRC checks are compiled in but not enforced on V5.01 nor V5.07.
On V5.07 the CRC/Mx8Q flags are 0, `VerifyMx8QSign` is never reached, and the only check is
the uImage header CRC (`tryDoDataCheck`), which passes because the payloads are re-wrapped
(**STATIC**, **HW**: `Ret 515`). Mechanism and variants: [root.md](root.md).

## Image content

The `user` partition (mounted at `/usr`) is the vendor `/usr` tree of the matching version,
plus:

| Path on camera | Content |
|---|---|
| `/usr/bin/dropbear` | dropbear 2024.86, static ARM, stripped, password auth compiled out (699,120 B) |
| `/usr/share/ssh/dropbear_host_key` | ed25519 host key, mode 600, baked per build |
| `/usr/share/ssh/authorized_keys` | client public key(s) |
| `/usr/share/ssh/passwd` | copy of `/etc/passwd` with root home `/mnt/mtd`; bind-mounted over `/etc/passwd` so dropbear reads `/mnt/mtd/.ssh/authorized_keys` (dropbear only supports `~/.ssh/authorized_keys`) |
| `/usr/bin/quick_venc.sh` | boot hook run by `rcS` (see below) |
| `/usr/lib/block80.so` | port-80 bind shim, block80 variant only ([`src/block80.c`](../src/block80.c)) |
| `/usr/bin/app.sh` | vendor launcher with `LD_PRELOAD=/usr/lib/block80.so` exported before `Sofia` starts (block80 variant only) |

Boot hook ([`src/quick_venc.sh`](../src/quick_venc.sh), same file as found on the cameras, **HW**) actions:

1. create `/mnt/mtd/Log/9530Disable` (vendor debug service off, see [debug-services.md](debug-services.md));
2. copy the authorized key to `/mnt/mtd/.ssh/` with correct modes;
3. bind-mount the modified `passwd`;
4. start `dropbear -r … -p 2222 -P /tmp/dropbear.pid -E`.

`/usr/share/music` (voice prompts) is removed to fit the 4,544 KiB `user` partition
(payload limit 4,652,992 B). Free space: 4,652,992 − 4,456,448 = 196,544 B (about 192 KiB)
for the V5.07 image, 192,448 B (about 188 KiB) for the block80 image. U-Boot, env, kernel, romfs,
custom and `InstallDesc` stay byte-identical to the official package.

No 2323 shell, no `shd`, no vendor debug, no unauthenticated management service.

## Build

The private host key, client key and admin password are not published. Package format:
[firmware.md](firmware.md). The scripts below are the ones that produced the installed
packages, with private workspace paths replaced by `PROJ`-based paths (set `PROJ` in the
environment; it defaults to the placeholder `/path/to/workspace`), the comments completed and
one unused variable removed. In this published form they are
**UNTESTED**.

`PROJ` is a workspace directory that contains this repository checkout (`src/`, `tools/`) next
to the build trees. All commands below run from `$PROJ`.

| File | Role |
|---|---|
| [`tools/build_prod_ssh.sh`](../tools/build_prod_ssh.sh) | V5.01 (historical): production `/usr` tree, squashfs (`-b 131072`, zero padding to 4,652,992 B), `v501_prod_ssh.bin` |
| [`tools/prod_build.sh`](../tools/prod_build.sh) | V5.07: keys, production `/usr` tree from the official V5.07 `/usr`, squashfs (`-b 524288`, `0xFF` padding to `0x46FFC0`). Does not build the package (see commands below) |
| [`tools/build_patch.sh`](../tools/build_patch.sh) | V5.07 block80: adds `block80.so` and the modified `app.sh` to the V5.07 production tree, squashfs, `v507_prod_ssh_block80.bin`; also writes two QEMU test flash images. Flashes nothing itself |
| [`tools/xm_mkzip.py`](../tools/xm_mkzip.py) | copies an official package and re-wraps one member (`--wrap NAME=PAYLOAD`: keeps the 64-byte uImage header, updates size and both CRCs); `InstallDesc` stays byte-identical unless a field option is used |
| [`src/build_block80.sh`](../src/build_block80.sh) | builds the freestanding ARM `block80.so` (`-nostdlib`, soft-float, `--hash-style=sysv`); `CC` and `OUT` are environment variables |
| [`src/block80.c`](../src/block80.c) | shim: `bind(AF_INET, port 80)` returns `-1`/`EACCES`, other binds pass through; optional `BLOCK80_REDIRECT_PORT`; marker line in `/var/block80.log` |

Inputs per script (paths relative to `$PROJ`):

| Script | Variable | Path | Content / origin |
|---|---|---|---|
| `build_prod_ssh.sh` | `OUT` | `upg/` | reads `v501_official.bin` (official V5.01 `.bin`), writes `v501_prod_ssh.bin` |
| | `WORK` | `camfw2/` | scratch; must hold `user_custom/` (unpacked V5.01 `/usr`), `dropbear-2024.86/dropbear`, `dropbear_host_key` |
| | — | `id_ed25519_client.pub` | V5.01 client public key |
| `prod_build.sh` | `ROOT` | `.` (`$PROJ`) | |
| | `W` | `v507-upgrade/` | must hold `work_user/tree/` = official V5.07 `/usr` (see below) |
| | `PROD` | `v507-upgrade/prod/` | output: `id_ed25519_v507{,.pub}`, `dropbear_host_key_v507`, `tree/`, `user_v507_prod_padded.bin` |
| | — | `upg/v501_prod_ssh.bin` | source of the static `dropbear`; skipped when `PROD/dropbear_bin` exists |
| `build_patch.sh` | `PROD_TREE` | `v507-upgrade/prod/tree/` | output of `prod_build.sh` |
| | `PROD_PKG` | `upg/v507_prod_ssh.bin` | V5.07 production package (built below) |
| | `SHELL_IMG` | `xm_fw/xm535d1_v507_shell.img` | QEMU harness flash image, not published ([emulation.md](emulation.md)) |
| | `W`, `TASK` | `sofia_http/`, `sofia-http-patch/` | scratch build directory; output `sofia-http-patch/pkg/` and `evidence/` |
| | — | `src/build_block80.sh`, `tools/xm_mkzip.py` | repository files |
| | — | `v507-upgrade/prod/user_v507_prod_padded.bin` | output of `prod_build.sh`; input of the control test image (step 4b) |

Prerequisites for `prod_build.sh`:

1. Unpack the official V5.07 `/usr` to `v507-upgrade/work_user/tree`:
   ```bash
   mkdir -p v507-upgrade/work_user
   unzip -p upg/v507_official.bin user-x.cramfs.img > /tmp/user-x.cramfs.img
   dd if=/tmp/user-x.cramfs.img bs=64 skip=1 of=v507-upgrade/work_user/user_v507_official.sq
   unsquashfs -d v507-upgrade/work_user/tree v507-upgrade/work_user/user_v507_official.sq
   ```
2. Without `upg/v501_prod_ssh.bin` (not published), build dropbear (below) and copy it to
   `v507-upgrade/prod/dropbear_bin` (mode 755) before running the script.
3. The scripts copy one `.pub` file to `/usr/share/ssh/authorized_keys`. To install a primary
   and a backup key (recommended), the file must contain both before `mksquashfs` runs. With
   `prod_build.sh`, which keeps existing keys on re-runs: run it once, then
   ```bash
   cat v507-upgrade/prod/id_ed25519_v507.pub backup_key.pub > /tmp/keys.pub
   mv /tmp/keys.pub v507-upgrade/prod/id_ed25519_v507.pub
   tools/prod_build.sh
   ```
   The result is `"$PROD/tree/share/ssh/authorized_keys"` = `cat key1.pub key2.pub`. For
   `build_prod_ssh.sh`, put both keys in `id_ed25519_client.pub`.

```bash
# dropbear, static, key-only (run in the dropbear-2024.86 source tree)
./configure --host=arm-linux-gnueabihf --disable-zlib \
  --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
  --disable-pututline --disable-pututxline CFLAGS="-Os" LDFLAGS="-static"
# add "#define DROPBEAR_SVR_PASSWORD_AUTH 0" to localoptions.h, then:
make PROGRAMS="dropbear dropbearkey"
arm-linux-gnueabihf-strip dropbear

# V5.07 package (the original build used an equivalent unpublished wrapper)
cd "$PROJ"
tools/prod_build.sh            # -> v507-upgrade/prod/user_v507_prod_padded.bin
python3 tools/xm_mkzip.py --src upg/v507_official.bin --out upg/v507_prod_ssh.bin \
  --wrap user-x.cramfs.img=v507-upgrade/prod/user_v507_prod_padded.bin

# block80 package (built from upg/v507_prod_ssh.bin)
tools/build_patch.sh           # -> sofia-http-patch/pkg/v507_prod_ssh_block80.bin
```

`upg/v507_official.bin` is the official V5.07 `_all.bin` extracted from the vendor ZIP
([firmware.md](firmware.md#official-builds)).

Script notes:

- `build_patch.sh` runs under `set -e` and needs `SHELL_IMG` for its test-image steps; without
  it the script stops before the package step.
- `build_prod_ssh.sh` copies a lab `/usr` tree (`user_custom`): the V5.01 production tree still
  contains the `shd` binary, which nothing starts (the boot hook is replaced).
- The `passwd` line written by both builders reuses the vendor root hash from the `romfs`
  `/etc/passwd`; only the home directory changes. Password login is compiled out of dropbear.
- `build_patch.sh` writes `app.sh` from a heredoc. Compared with the official V5.07
  `/usr/bin/app.sh`, the only differences are three added comment lines and the two lines
  `LD_PRELOAD=/usr/lib/block80.so` / `export LD_PRELOAD` before `/usr/bin/Sofia`; all other
  lines are identical (**STATIC**, compared against the unpacked official V5.07 `/usr`). The
  heredoc comment still says "QEMU-validated" (written before the hardware flash); it is kept
  verbatim so that the build reproduces the deployed `app.sh`.

Keep a second backup public key in `authorized_keys` (prerequisite 3 above; see
[recovery.md](recovery.md#ssh-key-loss)).

## Pre-flash checklist

| Check | Detail |
|---|---|
| Hashes | production package, official package, recovery image, SPI dump |
| Rollback | verified SPI dump ×2 if possible; without one, the risk must be accepted explicitly and only the official package / identity-less recovery image remain (see [recovery.md](recovery.md)) |
| Config snapshot | `getUsers`, `NetWork`, `General`, `System`, `AVEnc`, `Ability`, `Storage`, `Record`, `Ptz`, `Camera` saved locally; or `ConfigExport` |
| Credentials | admin password known (factory: `admin` + empty) |
| Network | stable link, 0 % loss; Ethernet preferred for the upload |
| Power | no power cut during the DVRIP upload |
| VMS | admin credential known; old IP noted (it may change with DHCP) |
| Storage | 64 GB known-good microSD; 128 GB failed WFS init (see [quirks.md](quirks.md)) |

Hard rules: no destructive boot-media/recovery/`ConfigImport` tests on a camera without its
own dump; never clone one camera's SPI dump onto another (identity/calibration).

## Install

1. Upload the package over DVRIP `OPSystemUpgrade` (32 KiB blocks) or the web UI. Expect
   `Ret 100` frames with progress, then **`Ret 515`**, then an automatic reboot.
   [`tools/dvrip_upgrade.py`](../tools/dvrip_upgrade.py) wraps the `upgrade()` call of the
   `dvrip` module of [`python-dvr`](https://github.com/NeiroNx/python-dvr) (install it from
   that repository, or put its `dvrip.py` on `PYTHONPATH`); it was used for the block80 flash
   (**HW**). Arguments, in order: package, admin password (`''` for a factory camera), camera
   IP (default `192.168.1.10`, the vendor factory fallback). The user is always `admin`. The
   script exits 2 only on a failed login; an upload exception still exits 0, so check the
   printed `Ret` frames:
   ```bash
   python3 tools/dvrip_upgrade.py sofia-http-patch/pkg/v507_prod_ssh_block80.bin '<admin-password>' <camera-ip>
   ```
2. Test SSH:
   ```bash
   ssh -i v507-upgrade/prod/id_ed25519_v507 -p 2222 -o StrictHostKeyChecking=accept-new \
       root@<camera-ip> 'cat /proc/self/status; netstat -lntp'
   ```
   Expect `Uid: 0 0 0 0` and dropbear on 2222.
3. Apply the hardening over DVRIP: admin password first, then the `NetWork` fields, then the
   service account ([hardening.md](hardening.md)).
4. Reboot from the SSH session (`sync; reboot`). Do not cut power right after `set_info`: the JFFS2
   flush is asynchronous and the config can be lost.
5. Configure time via VMS ([hardening.md](hardening.md#time-and-ntp)) and set the VMS device
   connection to `admin` ([hardening.md](hardening.md#vms-setup)).
6. Run the post-flash checklist.

## Post-flash checklist

| Check | Expected |
|---|---|
| Version (DVRIP) | `V5.07.X02.000A07F3.10010.346732.0000000`; serial unchanged |
| SSH 2222 | open, key-only, `Uid: 0 0 0 0`, root home `/mnt/mtd` |
| `/mnt/mtd/Log/9530Disable` | present |
| TCP 80 / 2323 / 12901 / 9530 / 23 | closed |
| Users | `admin` (strong password) + service account in group `user` with a strong random password |
| RTSP with empty password | `401` |
| RTSP with stored hash or plaintext | `200` |
| ONVIF media/device unauthenticated | `401 NotAuthorized` |
| `/webcapture.jpg` unauthenticated (V5.01/V5.07 without block80) | `401` |
| Legacy HTTP bridge, any non-empty password (without block80) | `Ret 203 Pwd error`, also with the correct password ([quirks.md](quirks.md#web-ui)) |
| PMS / NAT / OnlineUpgrade | off |
| `DisableXmServerConn` | all true |
| `OnvifPwdCheckout` / `TelnetDebugMode` | `true` / `false` |
| NTP | on, public servers |
| Time | `localtime=GMT-1` + `timeMin=-60`; new recording file correctly stamped |
| Recording | `SDCheckStatus=0`, new files present |
| VMS | version and stream/encoder pages load with `admin` |
| Persistence | `sync; reboot`, then SSH and all checks above still pass |
| Network | VMS device IP and DHCP reservation updated; post-flash config snapshot archived |

Validation record (**HW**): from stock V5.01 the package gave `Ret 515`, V5.07.X02, SSH root,
hardening persisted, persistence after reboot, then a downgrade with the official V5.01
package (`Ret 515`) removed SSH and kept the hardened config. **QEMU** repeated install from
stock V5.07 and from rooted V5.01, plus a second reboot (SSH up at ~4 s uptime). Listeners on
V5.07 without block80: 2222, 80, 554, 8899, 34567, plus `Sofia` on `127.0.0.1:23000`
(loopback only, not reachable from the LAN) (**QEMU**); with block80: see
[security.md](security.md#production-surface).

## Recovery

- Official package of the same version (`Ret 515`): restores vendor `/usr` and voice prompts,
  removes SSH and the shim; `/mnt/mtd` config and the admin password are kept.
- Downgrade to the official V5.01 package, then re-install a production package.
- Lost SSH key: rebuild with a new key and upload with the admin password.
- Exact restore: SPI dump (cam1 only). Details: [recovery.md](recovery.md).

## Residual risks

- TCP 2222 is root over the LAN: firewall it to the management host, never forward it. The
  client private key is the root credential; there is no password fallback.
- The host key is baked into the build: deploying one build to several cameras shares it.
  Generate one per camera if that matters.
- Hardening lives in `/mnt/mtd`, not in the image: a factory reset restores the vendor
  defaults (including `OnvifPwdCheckout=false`); an official upgrade removes dropbear and
  block80. Re-apply and re-verify after either.
- The legacy HTTP bridge code remains in `Sofia`; it is unreachable with block80 and
  password-gated otherwise.
- Voice prompts are absent; only an official flash restores them.
- A future vendor firmware that enforces CRC/`Mx8Q` will reject this package.
- dropbear 2024.86: known CVEs are post-auth or client-side; rebuild with ≥ 2025.88 long-term.
- Full LAN surface and component audit: [security.md](security.md).
