#!/usr/bin/env bash

set -Eeuo pipefail

echo "Starting vllm controller"
cd /opt/densemax/serve
source .venv/bin/activate
nohup uvicorn vllm-controller:app --host 0.0.0.0 --port 9000 --reload --workers 1 > /var/log/vllm-controller.log 2>&1 &

env="$1"; shift

echo "Starting job $* on uv env $env"
cd /opt/densemax/${env}
source .venv/bin/activate
exec stdbuf -oL -eL "$@"
