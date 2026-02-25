#!/bin/bash

set -e
mkdir -p /opt/aim
mkdir -p /opt/work/outputs

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/config_solved.yaml

# Write exit code to sentinel file on any exit so the orchestrator
# can detect job completion without relying on SkyPilot job tracking.
METRICS_PID=""
trap 'rc=$?; kill "$METRICS_PID" > /dev/null 2>&1 || true; wait "$METRICS_PID" > /dev/null 2>&1 || true; echo "$rc" > /tmp/train_exit_code; exit "$rc"' EXIT

echo "Preparing config file"
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "Training base model: ${BASE_MODEL}"

# Start background metrics reporter (outputs TRAINING_METRICS lines to stdout)
python /usr/bin/metrics_reporter.py &
METRICS_PID=$!

surogate sft $CONFIG
