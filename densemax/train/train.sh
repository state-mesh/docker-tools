#!/bin/bash

set -e

cd /opt/densemax/train

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/axolotl_solved.yaml

echo "Downloading model ${BASE_MODEL}"
rm -rf $WORK_DIR/model/*
lakectl fs download -r lakefs://$BASE_MODEL/ $WORK_DIR/model

echo "Preparing config file"
uv run envsubst < $WORK_DIR/axolotl.yaml > $CONFIG

echo "DeepSpeed is enabled. Fetching configs"
uv run axolotl fetch deepspeed_configs

echo "Downloading dataset ${DATASET}"
lakectl fs download -r lakefs://$DATASET/ $WORK_DIR/dataset

echo "Preprocessing dataset"
uv run axolotl preprocess $CONFIG

echo "Training base model: ${BASE_MODEL}"
uv run axolotl train $CONFIG --num-processes 1

echo "Merging LoRA into the base model"
uv run axolotl merge-lora $CONFIG --lora-model-dir=$WORK_DIR/outputs/$BASE_MODEL

if [[ "${TORCHAO}" == "true" ]]; then
  echo "Running quantization using Axolotl torchAO (Inference not working on Ampere GPU)"
  uv run axolotl quantize $CONFIG --base-model=$WORK_DIR/outputs/$BASE_MODEL/merged/
else
  echo "Running quantization using LLMCompressor"
  exec stdbuf -oL -eL quant
fi

echo "Uploading final model to a new branch"
lakectl branch create lakefs://$BASE_MODEL-$BRANCH -s lakefs://$BASE_MODEL
lakectl fs upload -rs $WORK_DIR/outputs/$BASE_MODEL/quantized/ lakefs://$BASE_MODEL-$BRANCH/
