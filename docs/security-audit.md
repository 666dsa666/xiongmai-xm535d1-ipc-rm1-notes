# Security audit — active components (V5.07, 2026-11-20)

Read-only audit of `.161` after the port-80 closure. Full local report:
`stack/analysis/access/cve-audit/REPORT.md` and `lan-surface/REPORT.md`.

## Active components

| Component | Version / note |
|---|---|
| Kernel | Linux **3.10.103+ #84** (build 2025-08-06), EOL |
| libc | **uClibc-ng 1.0.26** / NPTL (Buildroot 2017.11) |
| BusyBox | **1.33.1** (custom `timetest` = telnetd applet) |
| Sofia | V5.07.X02… (build 2025-09-06), ONVIF `hsoap/2.8`, `S.ONVIF 21.06` |
| libdvr / libXMcrypto | vendor |
| wpa_supplicant | **2.10** (station) |
| hostapd | 2.10_ATBM (shipped, **not running**) |
| dropbear | **2024.86**, static, publickey-only |
| block80 | project LD_PRELOAD bind shim, blocks :80 |
| OpenSSL | absent; no TLS listener |

All vendor binaries were SHA-256-identical to the official V5.07 package.

## Live reachable surface

`554` RTSP, `8899` ONVIF, `34567` DVRIP, `2222` SSH, UDP `3702` WS-Discovery,
DHCP client. Everything else RST-closed (80/443/2323/8443/9530/12901/23000/50119/23).

## Real residual risks (LAN)

1. **Hardening is not baked in (top risk).** ONVIF auth depends on `/mnt/mtd`
   `OnvifPwdCheckout=true`. A factory reset restores `false` and the
   CVE-2025-65856-class **unauthenticated ONVIF read surface** (observed on stock V5.01).
   A re-flash also removes dropbear and the block80 shim. Re-harden and re-verify after
   every reset/upgrade.
2. **SSH 2222 root, key-only** — the private key is the root credential. Key custody and
   network ACL are the controls.
3. **Cleartext + pass-the-hash** — RTSP/DVRIP/ONVIF are cleartext; the 8-char Sofia hash can
   be used as an RTSP password. Rotate the exposed Wi-Fi PSK; protect config/backups.
4. **BusyBox udhcpc CVE-2026-88833** (AV:A DoS) — udhcpc runs on `eth3`; use DHCP snooping or
   a static IP.
5. **Latent** — uClibc-ng CVE-2021-27419 (affected 1.0.26, no standalone exploit path shown);
   EOL kernel (local/DoS, unknown patch level); post-auth CVE-2022-45045-class admin→root
   (not demonstrated).

## Verified closed / not applicable

- **CVE-2024-3765 DVRIP bypass: patched** (live PoC returns Ret 105).
- **CVE-2025-65857** (wphd/2MNswbQ5): absent from this firmware.
- **CVE-2026-34005** (authenticated HostName RCE): dead code/no caller on this build.
- **CVE-2026-79393**: older XM530 line; not demonstrated here.
- Cloud/P2P, 9530, 12901, HTTP/uc-httpd CVEs: closed or cloud-cut.
- wpa/hostapd CVEs: local/AP-mode/PSK N/A; dropbear CVEs: post-auth/client-only.

## Verdict

**No urgent further authentication hardening.** No unauthenticated RCE, credential or video
path was found. What is warranted is operational:

1. **VLAN/ACL isolation** of `2222/34567/8899/554` (and UDP 3702) to required clients only;
   block camera egress except NTP if needed.
2. **Post-reset / post-upgrade checklist**: admin password, `OnvifPwdCheckout=true`, cloud cut,
   `jfxe` group user/random, dropbear key-only, block80 shim, verify 80 closed.
3. **Rotate the Wi-Fi PSK** exposed by `ConfigExport`; SSH-key hygiene.
4. **DHCP snooping / static IP** for the udhcpc DoS class.
5. Optional: close `8899` and `554` with the same bind-shim method if VMS/HA does not need them;
   rebuild dropbear ≥ 2025.88 long-term.

The camera's local-only hardening is effective; the main risk is **losing it on a reset or
upgrade**, not a currently exploitable LAN path.
