#!/bin/bash

set -e

cd /opt/densemax/train

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/axolotl_solved.yaml
SOURCE_REPO="${BASE_MODEL%%/*}"
[[ "${MERGE_LORA:-false}" != "true" ]] && LORA_ADAPTER=true || LORA_ADAPTER=false

echo "Downloading model ${BASE_MODEL}"
lakectl fs download -r lakefs://$BASE_MODEL/ $WORK_DIR/model

echo "Preparing config file"
#uv run envsubst < $WORK_DIR/axolotl.yaml > $CONFIG # Deprecated ConfigMap
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "DeepSpeed is enabled. Fetching configs"
uv run axolotl fetch deepspeed_configs

echo "Downloading dataset ${DATASET}"
lakectl fs download -r lakefs://$DATASET/ $WORK_DIR/dataset

echo "Preprocessing dataset"
uv run axolotl preprocess $CONFIG

echo "Training base model: ${BASE_MODEL}"
uv run axolotl train $CONFIG --num-processes 1

echo "Preparing lakefs branch"
lakectl branch create lakefs://$SOURCE_REPO/$BRANCH -s lakefs://$BASE_MODEL

if [[ "$LORA_ADAPTER" == "true" ]]; then
  echo "Uploading LoRA adapter"
  lakectl fs upload -rs $WORK_DIR/outputs/lora/ lakefs://$SOURCE_REPO/$BRANCH/
else
  echo "Merging LoRA into the base model"
  uv run axolotl merge-lora $CONFIG --lora-model-dir=$WORK_DIR/outputs/lora/ \
            --output-dir=$WORK_DIR/outputs/merged/

  if [[ "$QUANTIZE" == "true" ]]; then
    if [[ "${TORCHAO}" == "true" ]]; then
      echo "Running quantization using Axolotl torchAO (Inference not working on Ampere GPU)"
      uv run axolotl quantize $CONFIG --base-model=$WORK_DIR/outputs/merged/
    else
      echo "Running quantization using LLMCompressor"
      exec stdbuf -oL -eL quant
    fi

    echo "Uploading quantized model"
    lakectl fs upload -rs $WORK_DIR/outputs/quantized/ lakefs://$SOURCE_REPO/$BRANCH/
  else
    echo "Uploading merged model"
    lakectl fs upload -rs $WORK_DIR/outputs/merged/ lakefs://$SOURCE_REPO/$BRANCH/
  fi
fi

echo "Commiting lakefs branch"
lakectl commit lakefs://$SOURCE_REPO/$BRANCH --message "Fine-tuning of $BASE_MODEL" \
--meta lora_adapter="$LORA_ADAPTER" --meta quantized="$QUANTIZE" --meta source_model="$BASE_MODEL"

# No need for cleanup before or after because each RayJob has a PVC that follows job's lifecycle

