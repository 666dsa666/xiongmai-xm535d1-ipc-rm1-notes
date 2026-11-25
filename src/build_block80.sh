#!/bin/bash
# Build block80.so - freestanding ARM (soft-float, uClibc-target) LD_PRELOAD shim.
# Output: block80.so (no libc/libgcc/unwind dependencies).
set -e
CC=${CC:-arm-linux-gnueabihf-gcc}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$HERE/build/block80.so}
mkdir -p "$(dirname "$OUT")"

"$CC" -nostdlib -shared -fPIC -marm -mfloat-abi=soft -O2 -fno-builtin \
      -fno-unwind-tables -fno-asynchronous-unwind-tables \
      -fno-stack-protector \
      -Wl,--hash-style=sysv -Wl,-soname,block80.so \
      -o "$OUT" "$HERE/block80.c"

arm-linux-gnueabihf-readelf -d "$OUT" | grep -E 'NEEDED|SONAME|HASH|INIT' || true
arm-linux-gnueabihf-readelf -s "$OUT" | grep -E ' bind$|__errno_location' || true
ls -l "$OUT"
sha256sum "$OUT"
