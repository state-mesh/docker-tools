#!/bin/bash

set -eo pipefail

cd /opt/densemax/sky
source .venv/bin/activate

CLUSTER="${JOB_ID}-cluster"
echo "Shutting down cluster"
sky down -y $CLUSTER
