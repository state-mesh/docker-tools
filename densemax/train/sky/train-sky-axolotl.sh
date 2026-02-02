#!/bin/bash

set -e

mkdir -p /opt/work
cp ~/sky_workdir/* $WORK_DIR/

cd /opt/densemax/train-axolotl

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/axolotl_solved.yaml

echo "Preparing config file"
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "Training base model: ${BASE_MODEL}"
.venv/bin/axolotl train $CONFIG --num-processes 1

