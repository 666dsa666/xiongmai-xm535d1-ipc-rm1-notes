#!/bin/bash
# V5.01 production-SSH package (historical; see docs/production.md).
#
# Variables / inputs (override PROJ with the environment variable):
#   PROJ                      workspace holding this repository checkout
#   OUT = PROJ/upg            reads v501_official.bin, writes v501_prod_ssh.bin
#   WORK = PROJ/camfw2        scratch tree; must contain:
#     user_custom/            unpacked V5.01 /usr (lab tree)
#     dropbear-2024.86/dropbear   static ARM dropbear build
#     dropbear_host_key       dropbear host key (dropbearkey)
#   PROJ/id_ed25519_client.pub    client public key -> authorized_keys
#   PROJ/tools/xm_mkzip.py
set -e
PROJ="${PROJ:-/path/to/workspace}"
OUT="$PROJ/upg"
WORK="$PROJ/camfw2"
PROD="$WORK/user_prod"
cd "$WORK"

echo "=== prepare tree ==="
rm -rf "$PROD"
cp -a "$WORK/user_custom" "$PROD"
rm -rf "$PROD/share/music"
mkdir -p "$PROD/share/ssh"

cp "$WORK/dropbear-2024.86/dropbear" "$PROD/bin/dropbear"
chmod 755 "$PROD/bin/dropbear"
cp "$WORK/dropbear_host_key" "$PROD/share/ssh/dropbear_host_key"
chmod 600 "$PROD/share/ssh/dropbear_host_key"
cp "$PROJ/id_ed25519_client.pub" "$PROD/share/ssh/authorized_keys"
chmod 644 "$PROD/share/ssh/authorized_keys"

cat > "$PROD/share/ssh/passwd" <<'EOF'
root:$1$RYIwEiRA$d5iRRVQ5ZeRTrJwGjRy.B0:0:0:root:/mnt/mtd:/bin/sh
EOF
chmod 644 "$PROD/share/ssh/passwd"

cat > "$PROD/bin/quick_venc.sh" <<'EOF'
#!/bin/sh
# production boot hook
touch /mnt/mtd/Log/9530Disable
mkdir -p /mnt/mtd/.ssh
cp -f /usr/share/ssh/authorized_keys /mnt/mtd/.ssh/authorized_keys
chmod 700 /mnt/mtd/.ssh
chmod 600 /mnt/mtd/.ssh/authorized_keys
# root home -> /mnt/mtd so dropbear finds ~/.ssh/authorized_keys
mount --bind /usr/share/ssh/passwd /etc/passwd
/usr/bin/dropbear -r /usr/share/ssh/dropbear_host_key -p 2222 -P /tmp/dropbear.pid -E >/dev/null 2>&1 &
exit 0
EOF
chmod 755 "$PROD/bin/quick_venc.sh"

echo "=== sizes ==="
du -sh "$PROD"
ls -l "$PROD/bin/dropbear" "$PROD/share/ssh/"*

echo "=== mksquashfs ==="
rm -f "$WORK/custom_prod.sq" "$WORK/custom_prod_padded.sq"
mksquashfs "$PROD" "$WORK/custom_prod.sq" -comp xz -Xbcj arm -b 131072 -noappend -all-root >/dev/null
ls -l "$WORK/custom_prod.sq"
cp "$WORK/custom_prod.sq" "$WORK/custom_prod_padded.sq"
truncate -s 4652992 "$WORK/custom_prod_padded.sq"
ls -l "$WORK/custom_prod_padded.sq"

echo "=== wrap package ==="
python3 "$PROJ/tools/xm_mkzip.py" \
  --src "$OUT/v501_official.bin" \
  --out "$OUT/v501_prod_ssh.bin" \
  --wrap "user-x.cramfs.img=$WORK/custom_prod_padded.sq"
ls -l "$OUT/v501_prod_ssh.bin"
sha256sum "$OUT/v501_prod_ssh.bin"
echo "=== done ==="
