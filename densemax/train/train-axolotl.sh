#!/bin/bash

set -e

cd /opt/densemax/train

export PYTHONUNBUFFERED=1
CONFIG=$WORK_DIR/axolotl_solved.yaml
SOURCE_REPO="${BASE_MODEL%%/*}"
IFS=',' read -ra DATASETS <<< "$DATASET"
[[ "${MERGE_LORA:-false}" != "true" ]] && LORA_ADAPTER=true || LORA_ADAPTER=false

echo "Preparing config file"
echo "$AXOLOTL_CONFIG" > $CONFIG

echo "Downloading model ${BASE_MODEL}"
lakectl fs download -r lakefs://$BASE_MODEL/ $WORK_DIR/model

for ds in "${DATASETS[@]}"; do
  ds_b64="$(printf '%s' "$ds" | base64 -w 0 | tr '+/' '-_' | tr -d '=')"
  target_dir="$WORK_DIR/dataset_${ds_b64}"

  echo "Downloading dataset ${ds} -> ${target_dir}"
  mkdir -p "$target_dir"

  lakectl fs download -r "lakefs://${ds}/" "$target_dir"
done

echo "Training base model: ${BASE_MODEL}"
uv run axolotl train $CONFIG --num-processes 1

echo "Preparing lakefs branch"
lakectl branch create lakefs://$SOURCE_REPO/$BRANCH -s lakefs://$BASE_MODEL

if [[ "$LORA_ADAPTER" == "true" ]]; then
  echo "Uploading LoRA adapter"
  lakectl fs upload -rs $WORK_DIR/outputs/lora/ lakefs://$SOURCE_REPO/$BRANCH/
else
  echo "Merging LoRA into the base model"
  uv run axolotl merge-lora $CONFIG --lora-model-dir=$WORK_DIR/outputs/merged/ \
            --output-dir=$WORK_DIR/outputs/
  echo "Uploading merged model"
  lakectl fs upload -rs $WORK_DIR/outputs/merged/ lakefs://$SOURCE_REPO/$BRANCH/
fi

echo "Commiting lakefs branch"
lakectl commit lakefs://$SOURCE_REPO/$BRANCH --message "Fine-tuning of $BASE_MODEL" \
--meta lora_adapter="$LORA_ADAPTER" --meta source_model="$BASE_MODEL"

# No need for cleanup before or after because each RayJob has a PVC that follows job's lifecycle

