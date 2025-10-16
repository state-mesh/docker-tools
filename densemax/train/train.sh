#!/bin/bash

set -e

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/axolotl_solved.yaml

echo "Downloading model ${BASE_MODEL}"
lakectl fs download -r lakefs://$BASE_MODEL/ $WORK_DIR/model

echo "Preparing config file"
envsubst < $WORK_DIR/axolotl.yaml > $CONFIG

echo "DeepSpeed is enabled. Fetching configs"
axolotl fetch deepspeed_configs

echo "Downloading dataset ${DATASET}"
lakectl fs download -r lakefs://$DATASET/ $WORK_DIR/dataset

echo "Preprocessing dataset"
axolotl preprocess $CONFIG

echo "Training base model: ${BASE_MODEL}"
axolotl train $CONFIG

echo "Merging LoRA into the base model"
axolotl merge-lora $CONFIG --lora-model-dir=$WORK_DIR/outputs/$BASE_MODEL

if [[ "${TORCHAO}" == "true" ]]; then
  echo "Running quantization using Axolotl torchAO (Inference not working on Ampere GPU)"
  axolotl quantize $CONFIG --base-model=$WORK_DIR/outputs/$BASE_MODEL/merged/
else
  echo "Running quantization using LLMCompressor"
  exec stdbuf -oL -eL conda run -n quant --no-capture-output quant
fi

echo "Uploading final model to a new branch"
lakectl branch create lakefs://$BASE_MODEL-$BRANCH -s lakefs://$BASE_MODEL
lakectl fs upload -rs $WORK_DIR/outputs/$BASE_MODEL/quantized/ lakefs://$BASE_MODEL-$BRANCH/