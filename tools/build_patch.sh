#!/bin/bash
# sofia-http-patch: build the V5.07 "no TCP/80" /usr payload, test flash image
# and upgrade package, starting from the validated V5.07 production-SSH package.
#
#   base /usr  = prod/tree from v507-upgrade (the tree baked into v507_prod_ssh.bin)
#   change     = + /usr/lib/block80.so      (freestanding LD_PRELOAD bind shim)
#                + /usr/bin/app.sh exports LD_PRELOAD before starting Sofia
#   squashfs   = vendor params (xz, arm bcj, 512K blocks), padded 0x46FFC0
#   test image = xm535d1_v507_shell.img (harness romfs/ttyAMA1 shell) with the
#                user partition replaced by our payload
#   package    = copy of upg/v507_prod_ssh.bin with user-x wrapped
#
# Builds the package; the script itself flashes nothing. The two *_shell.img
# outputs are QEMU test images only. The resulting package was flashed
# separately (see docs/production.md).
#
# Variables / inputs (all under PROJ, the workspace that holds this repository
# checkout plus the build trees; override with the PROJ environment variable):
#   PROJ/src/build_block80.sh, PROJ/src/block80.c, PROJ/tools/xm_mkzip.py
#   PROD_TREE  PROJ/v507-upgrade/prod/tree      (written by tools/prod_build.sh)
#   PROJ/v507-upgrade/prod/user_v507_prod_padded.bin (control image, step 4b)
#   SHELL_IMG  PROJ/xm_fw/xm535d1_v507_shell.img (QEMU harness image, not published)
#   PROD_PKG   PROJ/upg/v507_prod_ssh.bin       (V5.07 production package)
#   W          scratch build directory; TASK = output directory (pkg/, evidence/)
set -e
PROJ="${PROJ:-/path/to/workspace}"
TASK="$PROJ/sofia-http-patch"
W="$PROJ/sofia_http"
BUILD="$W/build"
PROD_TREE="$PROJ/v507-upgrade/prod/tree"
SHELL_IMG="$PROJ/xm_fw/xm535d1_v507_shell.img"
PROD_PKG="$PROJ/upg/v507_prod_ssh.bin"
LIM=4652992   # 0x46FFC0 = user partition payload limit

mkdir -p "$BUILD" "$TASK/pkg" "$TASK/evidence"

echo "=== 1. block80.so ==="
OUT="$BUILD/block80.so" bash "$PROJ/src/build_block80.sh" >"$TASK/evidence/build_block80.log" 2>&1
cat "$TASK/evidence/build_block80.log"

echo "=== 2. copy prod /usr tree and inject the shim ==="
rm -rf "$BUILD/tree"
cp -a "$PROD_TREE" "$BUILD/tree"
mkdir -p "$BUILD/tree/lib"
cp "$BUILD/block80.so" "$BUILD/tree/lib/block80.so"
chmod 755 "$BUILD/tree/lib/block80.so"

cat > "$BUILD/tree/bin/app.sh" <<'SH'
#!/bin/sh
# sofia-http-patch (QEMU-validated): block Sofia's HTTP/web server from
# binding TCP port 80 via the freestanding LD_PRELOAD shim. Every other
# bind() is passed straight to the kernel, so RTSP/ONVIF/DVRIP are untouched.
LD_PRELOAD=/usr/lib/block80.so
export LD_PRELOAD
/usr/bin/Sofia
touch /mnt/mtd/Config/maintain
echo 1 > /mnt/mtd/Config/RebootAbnormal
cp /var/sofia.log  /mnt/mtd/sofia.log
dmesg > /var/halted.log
date >> /var/halted.log
cat /proc/umap/* >> /var/halted.log
cat /proc/meminfo >> /var/halted.log
tail -c 20480 /var/halted.log > /mnt/mtd/halted.log
SH
chmod 755 "$BUILD/tree/bin/app.sh"
echo "tree files: $(find "$BUILD/tree" -type f | wc -l)"

echo "=== 3. squashfs + pad to 0x46FFC0 ==="
rm -f "$BUILD/user_block80.sq" "$BUILD/user_block80_padded.bin"
mksquashfs "$BUILD/tree" "$BUILD/user_block80.sq" \
  -comp xz -Xbcj arm -b 524288 -noappend -all-root \
  >"$TASK/evidence/mksquashfs.log" 2>&1
SZ=$(stat -c%s "$BUILD/user_block80.sq")
echo "user_block80.sq = $SZ bytes (limit $LIM = $((LIM)))"
if [ "$SZ" -gt "$LIM" ]; then echo "TOO BIG"; exit 1; fi
python3 - "$BUILD/user_block80.sq" "$BUILD/user_block80_padded.bin" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
d = open(src, "rb").read()
d += b"\xff" * (0x46FFC0 - len(d))
open(dst, "wb").write(d)
print("padded", len(d))
PY

echo "=== 4. test flash image (shell harness + patched user) ==="
python3 - "$SHELL_IMG" "$BUILD/user_block80_padded.bin" "$BUILD/xm535d1_v507_block80_shell.img" <<'PY'
import hashlib, sys
src, user, out = sys.argv[1], sys.argv[2], sys.argv[3]
img = bytearray(open(src, "rb").read())
u = open(user, "rb").read()
assert len(u) == 0x46FFC0, len(u)
img[0x300000:0x300000 + 0x46FFC0] = u
open(out, "wb").write(img)
print("wrote", out, len(img), hashlib.sha256(img).hexdigest())
PY

echo "=== 4b. control flash image (shell harness + UNPATCHED prod user) ==="
python3 - "$SHELL_IMG" "$PROJ/v507-upgrade/prod/user_v507_prod_padded.bin" \
        "$BUILD/xm535d1_v507_prod_control_shell.img" <<'PY'
import hashlib, sys
src, user, out = sys.argv[1], sys.argv[2], sys.argv[3]
img = bytearray(open(src, "rb").read())
u = open(user, "rb").read()
assert len(u) == 0x46FFC0, len(u)
img[0x300000:0x300000 + 0x46FFC0] = u
open(out, "wb").write(img)
print("wrote", out, len(img), hashlib.sha256(img).hexdigest())
PY

echo "=== 5. upgrade package (prod_ssh package + wrapped user-x) ==="
python3 "$PROJ/tools/xm_mkzip.py" \
  --src "$PROD_PKG" \
  --out "$BUILD/v507_prod_ssh_block80.bin" \
  --wrap "user-x.cramfs.img=$BUILD/user_block80_padded.bin" \
  >"$TASK/evidence/mkzip.log" 2>&1
tail -5 "$TASK/evidence/mkzip.log"

echo "=== 6. copy deliverables + hashes ==="
cp "$BUILD/block80.so"                     "$TASK/pkg/"
cp "$BUILD/user_block80.sq"                "$TASK/pkg/"
cp "$BUILD/user_block80_padded.bin"        "$TASK/pkg/"
cp "$BUILD/v507_prod_ssh_block80.bin"      "$TASK/pkg/"
cp "$BUILD/xm535d1_v507_block80_shell.img" "$TASK/pkg/"
cp "$BUILD/xm535d1_v507_prod_control_shell.img" "$TASK/pkg/"
sha256sum "$TASK/pkg/"* | tee "$TASK/pkg/SHA256SUMS.txt"
