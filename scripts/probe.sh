#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
archive=Sailfish_OS-5.1.0.11-Sailfish_SDK_Target-aarch64.tar.7z
mkdir -p downloads out
if [[ ! -f "downloads/$archive" ]]; then
  curl -fL --retry 3 "https://releases.sailfishos.org/sdk/targets/$archive" \
    -o "downloads/$archive.part"
  mv "downloads/$archive.part" "downloads/$archive"
fi
bash scripts/docker.sh build --platform linux/arm64 -t sailfish-arm64-probe:local .
bash scripts/run-container.sh bash scripts/prepare-sysroot.sh
bash scripts/run-container.sh bash scripts/build-probes.sh
bash scripts/docker.sh image inspect sailfish-arm64-probe:local \
  --format '{{.Id}} {{.Os}}/{{.Architecture}}' > out/image.txt
bash scripts/run-container.sh dpkg-query -W gcc-11 g++-11 binutils libc6-dev \
  > out/host-packages.txt
