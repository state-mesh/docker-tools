#!/bin/bash

set -e
mkdir -p /opt/work/outputs

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/config_solved.yaml

# Metrics file path for the surogate metrics SDK
export SUROGATE_METRICS_PATH="/tmp/surogate_metrics.jsonl"
mkdir -p "$(dirname "$SUROGATE_METRICS_PATH")"

# Write exit code to sentinel file on any exit so the orchestrator
# can detect job completion without relying on SkyPilot job tracking.
trap 'rc=$?; echo "$rc" > /tmp/train_exit_code; exit "$rc"' EXIT

echo "Preparing config file"
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "Training base model: ${BASE_MODEL}"

surogate sft $CONFIG
