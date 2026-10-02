#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -m) == aarch64 ]] || { echo 'ARM64 Linux required' >&2; exit 1; }
archive=Sailfish_OS-5.1.0.11-Sailfish_SDK_Target-aarch64.tar.7z
cd /work/downloads
echo "24b40e5e6c1366996dc5a4a69a46e3b3  $archive" | md5sum --check
echo "b0425395468254ebaaead29b477d29e446f8dbe7c1ec1c3ac7d80b82757deadc  $archive" | sha256sum --check
if [[ ! -f /opt/sailfish/.gea-probe-extracted ]]; then
  # Select the tar member (the 7z also contains metadata). Consume padding
  # through EOF so tar does not close the pipe early and SIGPIPE the producer.
  7z x -so "$archive" "${archive%.7z}" | tar --ignore-zeros --numeric-owner -xf - -C /opt/sailfish
  touch /opt/sailfish/.gea-probe-extracted
fi
