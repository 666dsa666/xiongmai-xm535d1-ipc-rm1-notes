#!/bin/bash
# v507-upgrade: build the V5.07 "production SSH" user partition + package.
#
# Base: official V5.07 /usr squashfs. Changes (same model as v501_prod_ssh.bin):
#   + /usr/bin/dropbear                  static ARM dropbear (key-only build)
#   + /usr/share/ssh/dropbear_host_key   NEW ed25519 host key (dropbearkey)
#   + /usr/share/ssh/authorized_keys     NEW client ed25519 pubkey
#   + /usr/share/ssh/passwd              /etc/passwd with root home /mnt/mtd
#   + /usr/bin/quick_venc.sh             boot hook run by rcS: 9530Disable,
#                                        authorized_keys -> /mnt/mtd/.ssh,
#                                        bind passwd, dropbear -p 2222 key-only
#   - /usr/share/music                   vendor voice prompts (space)
#
# Variables / inputs (ROOT = PROJ, the workspace holding this repository
# checkout; override with the PROJ environment variable):
#   W/work_user/tree          official V5.07 /usr, unpacked beforehand
#                             (user-x.cramfs.img minus 64-byte header, unsquashfs)
#   ROOT/upg/v501_prod_ssh.bin  source of the static dropbear binary; not needed
#                             if PROD/dropbear_bin already exists
#   PROD = W/prod             keys, tree and padded user image are written here
# Output: PROD/user_v507_prod_padded.bin. The package itself is made with
# tools/xm_mkzip.py --wrap (see docs/production.md).
set -e
ROOT="${PROJ:-/path/to/workspace}"
W=$ROOT/v507-upgrade
PROD=$W/prod
mkdir -p "$PROD"
cd "$W"

# --- 1. keys (new for this V5.07 variant; never reuse v501_prod_ssh keys)
#     idempotent: keep existing keys so packages stay reproducible
if [ ! -f "$PROD/id_ed25519_v507" ]; then
  ssh-keygen -q -t ed25519 -N "" -C "v507-production" \
    -f "$PROD/id_ed25519_v507"
fi
if [ ! -f "$PROD/dropbear_host_key_v507" ]; then
  dropbearkey -t ed25519 -f "$PROD/dropbear_host_key_v507" >/dev/null
fi
chmod 600 "$PROD/id_ed25519_v507" "$PROD/dropbear_host_key_v507"
echo "client fingerprint:"; ssh-keygen -lf "$PROD/id_ed25519_v507.pub"
echo "host   fingerprint:"; dropbearkey -y -f "$PROD/dropbear_host_key_v507" \
  | head -3
ls -l "$PROD"/id_ed25519_v507* "$PROD"/dropbear_host_key_v507

# --- 1b. dropbear binary from the validated v501_prod_ssh payload (static ARM)
if [ ! -x "$PROD/dropbear_bin" ]; then
  python3 - "$ROOT/upg/v501_prod_ssh.bin" "$PROD/v501_prod_user.sq" <<'PY'
import sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
d = z.read("user-x.cramfs.img")[64:]
open(dst, "wb").write(d)
print("v501 prod user squashfs", len(d))
PY
  rm -rf "$PROD/v501_tree"
  unsquashfs -d "$PROD/v501_tree" "$PROD/v501_prod_user.sq" \
    > "$PROD/logs_unsquashfs_v501prod.txt" 2>&1
  cp "$PROD/v501_tree/bin/dropbear" "$PROD/dropbear_bin"
fi
ls -l "$PROD/dropbear_bin"


# --- 2. V5.07 production /usr tree
rm -rf "$PROD/tree"
cp -r "$W/work_user/tree" "$PROD/tree"          # official V5.07 /usr
rm -rf "$PROD/tree/share/music"            # voice prompts (space)
cp "$PROD/dropbear_bin" "$PROD/tree/bin/dropbear"
mkdir -p "$PROD/tree/share/ssh"
cp "$PROD/dropbear_host_key_v507" "$PROD/tree/share/ssh/dropbear_host_key"
cp "$PROD/id_ed25519_v507.pub" "$PROD/tree/share/ssh/authorized_keys"
printf 'root:$1$RYIwEiRA$d5iRRVQ5ZeRTrJwGjRy.B0:0:0:root:/mnt/mtd:/bin/sh\n' \
  > "$PROD/tree/share/ssh/passwd"
cat > "$PROD/tree/bin/quick_venc.sh" <<'SH'
#!/bin/sh
# v507-production boot hook (run by vendor rcS)
touch /mnt/mtd/Log/9530Disable
mkdir -p /mnt/mtd/.ssh
cp -f /usr/share/ssh/authorized_keys /mnt/mtd/.ssh/authorized_keys
chmod 700 /mnt/mtd/.ssh
chmod 600 /mnt/mtd/.ssh/authorized_keys
# root home -> /mnt/mtd so dropbear finds ~/.ssh/authorized_keys
mount --bind /usr/share/ssh/passwd /etc/passwd
/usr/bin/dropbear -r /usr/share/ssh/dropbear_host_key -p 2222 -P /tmp/dropbear.pid -E >/dev/null 2>&1 &
exit 0
SH
chmod 755 "$PROD/tree/bin/quick_venc.sh"
chmod 755 "$PROD/tree/bin/dropbear"
chmod 600 "$PROD/tree/share/ssh/dropbear_host_key"
chmod 644 "$PROD/tree/share/ssh/authorized_keys" "$PROD/tree/share/ssh/passwd"
find "$PROD/tree" -type f | wc -l

# --- 3. squashfs (vendor uses xz, arm bcj filter, 512 KiB blocks)
rm -f "$PROD/user_v507_prod.sq"
mksquashfs "$PROD/tree" "$PROD/user_v507_prod.sq" \
  -comp xz -Xbcj arm -b 524288 -noappend -all-root \
  > "$PROD/logs_mksquashfs.txt" 2>&1
SZ=$(stat -c%s "$PROD/user_v507_prod.sq")
LIM=0x46FFC0
echo "user_v507_prod.sq = $SZ bytes (limit $((LIM)))"
if [ "$SZ" -gt "$LIM" ]; then echo "TOO BIG"; exit 1; fi
python3 - "$PROD/user_v507_prod.sq" "$PROD/user_v507_prod_padded.bin" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
d = open(src, "rb").read()
d += b"\xff" * (0x46FFC0 - len(d))
open(dst, "wb").write(d)
print("padded", len(d))
PY
