#!/bin/bash

set -e
mkdir -p /opt/aim
cd /opt/densemax/train

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/config_solved.yaml

# Write exit code to sentinel file on any exit so the orchestrator
# can detect job completion without relying on SkyPilot job tracking.
trap 'echo "$?" > /tmp/train_exit_code' EXIT

echo "Preparing config file"
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "Training base model: ${BASE_MODEL}"
uv run surogate sft $CONFIG
