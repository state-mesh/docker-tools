#!/bin/bash

set -e
export PYTHONUNBUFFERED=1

cd /opt/densemax/sky
source .venv/bin/activate

echo "Preparing sky config file"
CONFIG=$WORK_DIR/config.yaml
echo "$SKY_CONFIG" > $CONFIG

SOURCE_REPO="${BASE_MODEL%%/*}"
[[ "${LORA:-false}" == "true" ]] && [[ "${MERGE_LORA:-false}" != "true" ]] && LORA_ADAPTER=true || LORA_ADAPTER=false
IFS=',' read -ra DATASETS <<< "$DATASET"

# infra: k8s (local k8s cluster)
if [ -n "$KUBE_CONFIG" ]; then
  mkdir -p ~/.kube
  echo "$KUBE_CONFIG" > ~/.kube/config
fi
# infra: runpod
if [ -n "$RUNPOD_API_KEY" ]; then
  mkdir -p ~/.runpod/
  printf "[default]\napi_key = \"%s\"\n" "$RUNPOD_API_KEY" > ~/.runpod/config.toml
fi

echo "Downloading model ${BASE_MODEL}"
lakectl fs download -r lakefs://$BASE_MODEL/ $WORK_DIR/model

for ds in "${DATASETS[@]}"; do
  ds_b64="$(printf '%s' "$ds" | base64 -w 0 | tr '+/' '-_' | tr -d '=')"
  target_dir="$WORK_DIR/dataset_${ds_b64}"

  echo "Downloading dataset ${ds} -> ${target_dir}"
  mkdir -p "$target_dir"

  lakectl fs download -r "lakefs://${ds}/" "$target_dir"
done

sky launch -yc -d $JOB_ID-cluster $CONFIG
sky logs --autostop --follow --tail 1000 $JOB_ID-cluster

tail -f > /dev/null
rsync -Pavz /opt/work/outputs /opt/work/outputs/

echo "Preparing lakefs branch"
lakectl branch create lakefs://$SOURCE_REPO/$BRANCH -s lakefs://$BASE_MODEL

if [[ "$LORA_ADAPTER" == "true" ]]; then
  echo "Uploading LoRA adapter"
  if [[ "$USE_AXOLOTL_TRAINING_LIBRARY" == "true"]]; then
    lakectl fs upload -rs $WORK_DIR/outputs/lora/ lakefs://$SOURCE_REPO/$BRANCH/
  else
    lakectl fs upload -rs $WORK_DIR/outputs/ lakefs://$SOURCE_REPO/$BRANCH/
  fi
else
  if [[ "$USE_AXOLOTL_TRAINING_LIBRARY" == "true"]]; then
      if [[ "${MERGE_LORA:-false}" == "true" ]]; then
        echo "Merging LoRA into the base model"
        .venv/bin/axolotl merge-lora $CONFIG --lora-model-dir=$WORK_DIR/outputs/lora/ \
                          --output-dir=$WORK_DIR/outputs/
        echo "Uploading merged model"
        lakectl fs upload -rs $WORK_DIR/outputs/merged/ lakefs://$SOURCE_REPO/$BRANCH/
      else
        echo "Uploading fully trained model"
        lakectl fs upload -rs $WORK_DIR/outputs/ lakefs://$SOURCE_REPO/$BRANCH/
      fi
  else
      rm -rf $WORK_DIR/outputs/adapter_config.json
      rm -rf $WORK_DIR/outputs/adapter_model.safetensors
      echo "Uploading merged/full model"
      lakectl fs upload -rs $WORK_DIR/outputs/ lakefs://$SOURCE_REPO/$BRANCH/
  fi
fi

echo "Commiting lakefs branch"
lakectl commit lakefs://$SOURCE_REPO/$BRANCH --message "Fine-tuning of $BASE_MODEL" \
--meta lora_adapter="$LORA_ADAPTER" --meta source_model="$BASE_MODEL"