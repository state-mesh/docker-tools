#!/usr/bin/env bash

set -Eeuo pipefail

env="$1"; shift

echo "Starting job $*"
exec stdbuf -oL -eL "$@"
