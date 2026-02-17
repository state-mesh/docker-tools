#!/bin/bash

set -e
mkdir -p /opt/aim
cd /opt/densemax/train

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/config_solved.yaml

echo "Preparing config file"
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "Training base model: ${BASE_MODEL}"
.venv/bin/surogate sft $CONFIG