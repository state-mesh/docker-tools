#!/usr/bin/env bash

set -Eeuo pipefail

env="$1"; shift

echo "Starting job $* on conda env $env"
exec stdbuf -oL -eL conda run -n "$env" --no-capture-output "$@"