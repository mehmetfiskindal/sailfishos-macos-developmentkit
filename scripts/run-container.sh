#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
exec bash "$root/scripts/docker.sh" run --rm --platform linux/arm64 \
  --mount "type=bind,source=$root,target=/work" \
  --mount type=volume,source=sailfish-5.1.0.11-aarch64-probe,target=/opt/sailfish \
  --workdir /work sailfish-arm64-probe:local "$@"
