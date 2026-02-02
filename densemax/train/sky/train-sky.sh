#!/bin/bash

set -e

cd /opt/densemax/train
cp ~/sky_workdir/* $WORK_DIR/

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/config_solved.yaml

echo "Preparing config file"
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "Training base model: ${BASE_MODEL}"
uv run surogate sft $CONFIG