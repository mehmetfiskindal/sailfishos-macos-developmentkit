#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -m) == aarch64 ]] || { echo 'ARM64 Linux required' >&2; exit 1; }
sysroot=/opt/sailfish
[[ -f "$sysroot/.gea-probe-extracted" ]] || { echo 'Prepare sysroot first' >&2; exit 1; }
mkdir -p /work/out
gccdir=$(dirname "$(gcc -print-libgcc-file-name)")
cxxversion=$(g++ -dumpversion)
common=(--sysroot="$sysroot" -O2 -fPIE -nostdinc)
c_headers=(-isystem "$gccdir/include" -isystem "$sysroot/usr/include")
gcc "${common[@]}" "${c_headers[@]}" -c samples/hello.c -o out/hello-c.o
# The target archive has libstdc++ runtime but no C++ development headers.
# For this probe use GCC 11's headers explicitly, paired with target C headers.
# This is a tested subset, not the final Sailfish GCC 13 toolchain.
g++ "${common[@]}" -std=c++20 -nostdinc++ \
  -isystem "/usr/include/c++/$cxxversion" \
  -isystem "/usr/include/aarch64-linux-gnu/c++/$cxxversion" \
  -isystem "/usr/include/c++/$cxxversion/backward" \
  "${c_headers[@]}" \
  -c samples/hello.cpp -o out/hello-cpp.o

link() {
  local name=$1
  shift
  g++ --sysroot="$sysroot" -nostdlib -pie \
    -Wl,--dynamic-linker=/lib/ld-linux-aarch64.so.1 \
    -Wl,-rpath-link,"$sysroot/lib64:$sysroot/usr/lib64" \
    -Wl,-Map,"out/$name.map" \
    "$sysroot/usr/lib64/Scrt1.o" "$sysroot/usr/lib64/crti.o" \
    "$gccdir/crtbeginS.o" "out/$name.o" \
    "$@" "$sysroot/usr/lib64/libc.so" "$sysroot/usr/lib64/libm.so" \
    "$sysroot/lib64/libgcc_s.so.1" \
    "$gccdir/crtendS.o" "$sysroot/usr/lib64/crtn.o" -o "out/$name"
}
link hello-c
link hello-cpp "$sysroot/usr/lib64/libstdc++.so.6"

python3 - <<'PY'
from pathlib import Path
import re
for name in ('hello-c', 'hello-cpp'):
    for line in Path(f'out/{name}.map').read_text().splitlines():
        if not line.startswith('LOAD /'):
            continue
        path = line[5:]
        if path.startswith('/opt/sailfish/'):
            continue
        if re.fullmatch(r'/usr/lib/gcc/aarch64-linux-gnu/11/crt(?:begin|end)S\.o', path):
            continue
        raise SystemExit(f'Unexpected host linker input: {path}')
PY

{
  echo "Host: $(uname -m)"
  gcc --version | head -n 1
  echo 'C++ headers and crtbegin/crtend: Ubuntu GCC 11; libc/libstdc++/libgcc_s and libc startup objects: Sailfish target'
  for name in hello-c hello-cpp; do
    echo "=== $name ELF ==="
    readelf -h "out/$name"
    readelf -l "out/$name" | sed -n '/interpreter/p'
    readelf -d "out/$name" | sed -n '/NEEDED/p;/RPATH/p;/RUNPATH/p'
    readelf --version-info "out/$name"
  done
} > out/elf-report.txt

# Execute inside the actual target root: host /lib and /usr are inaccessible.
# No QEMU, bind-mounted host libraries, or target loader library overrides.
mkdir -p "$sysroot/tmp/gea-probe"
cp out/hello-c out/hello-cpp "$sysroot/tmp/gea-probe/"
{
  echo 'Native ARM64 execution inside Sailfish target chroot:'
  chroot "$sysroot" /tmp/gea-probe/hello-c
  chroot "$sysroot" /tmp/gea-probe/hello-cpp
} | tee out/runtime-report.txt
