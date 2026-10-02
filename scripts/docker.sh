#!/usr/bin/env bash
set -euo pipefail
# Docker Desktop keeps its CLI and credential helper together on macOS.
if [[ -d /Applications/Docker.app/Contents/Resources/bin ]]; then
  export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
fi
exec docker "$@"
