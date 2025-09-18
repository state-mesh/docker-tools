#!/bin/bash

set -e

CONFIG=$WORK_DIR/axolotl_solved.yaml

echo "Preparing config file"
envsubst < $WORK_DIR/axolotl.yaml > $CONFIG

echo "Training base model: ${BASE_MODEL}"
axolotl train $CONFIG

echo "Merging LoRA into the base model"
axolotl merge-lora $CONFIG --lora-model-dir=$WORK_DIR/outputs/$BASE_MODEL

if [[ "${TORCHAO}" == "true" ]]; then
  echo "Running quantization using Axolotl torchAO (Inference not working on Ampere GPU)"
  axolotl quantize $CONFIG --base-model=$WORK_DIR/outputs/$BASE_MODEL/merged/
else
  echo "Running quantization using LLMCompressor"
  python /scripts/quantization.py
fi
