#!/usr/bin/env bash

set -Eeuo pipefail

env="$1"; shift

echo "Starting job $* on uv env $env"
cd /opt/densemax/${env}
source .venv/bin/activate
exec stdbuf -oL -eL "$@"
