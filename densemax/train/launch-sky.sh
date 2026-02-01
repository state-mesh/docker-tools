#!/bin/bash

set -e
export PYTHONUNBUFFERED=1

cd /opt/densemax/sky

echo "Preparing sky config file"
CONFIG=$WORK_DIR/config.yaml
echo "$SKY_CONFIG" > $CONFIG

SOURCE_REPO="${BASE_MODEL%%/*}"
[[ "${LORA:-false}" == "true" ]] && [[ "${MERGE_LORA:-false}" != "true" ]] && LORA_ADAPTER=true || LORA_ADAPTER=false
IFS=',' read -ra DATASETS <<< "$DATASET"

sky api login

# Cloud / k8s login forEach infra:

sky show-gpus

#echo "Downloading model ${BASE_MODEL}"
#lakectl fs download -r lakefs://$BASE_MODEL/ $WORK_DIR/model
#
#for ds in "${DATASETS[@]}"; do
#  ds_b64="$(printf '%s' "$ds" | base64 -w 0 | tr '+/' '-_' | tr -d '=')"
#  target_dir="$WORK_DIR/dataset_${ds_b64}"
#
#  echo "Downloading dataset ${ds} -> ${target_dir}"
#  mkdir -p "$target_dir"
#
#  lakectl fs download -r "lakefs://${ds}/" "$target_dir"
#done

sky launch -c $JOB_ID-cluster $CONFIG

tail -f > /dev/null
#RSYNC ???

#echo "Preparing lakefs branch"
#lakectl branch create lakefs://$SOURCE_REPO/$BRANCH -s lakefs://$BASE_MODEL
#



#if [[ "$LORA_ADAPTER" == "true" ]]; then
#  echo "Uploading LoRA adapter"
#else
#  rm -rf $WORK_DIR/outputs/adapter_config.json
#  rm -rf $WORK_DIR/outputs/adapter_model.safetensors
#  echo "Uploading merged/full model"
#fi
#lakectl fs upload -rs $WORK_DIR/outputs/ lakefs://$SOURCE_REPO/$BRANCH/
#
# VS #
#if [[ "$LORA_ADAPTER" == "true" ]]; then
#  echo "Uploading LoRA adapter"
#  lakectl fs upload -rs $WORK_DIR/outputs/lora/ lakefs://$SOURCE_REPO/$BRANCH/
#else
#  if [[ "${MERGE_LORA:-false}" == "true" ]]; then
#    echo "Merging LoRA into the base model"
#    .venv/bin/axolotl merge-lora $CONFIG --lora-model-dir=$WORK_DIR/outputs/lora/ \
#                      --output-dir=$WORK_DIR/outputs/
#    echo "Uploading merged model"
#    lakectl fs upload -rs $WORK_DIR/outputs/merged/ lakefs://$SOURCE_REPO/$BRANCH/
#  else
#    echo "Uploading fully trained model"
#    lakectl fs upload -rs $WORK_DIR/outputs/ lakefs://$SOURCE_REPO/$BRANCH/
#  fi
#fi


#echo "Commiting lakefs branch"
#lakectl commit lakefs://$SOURCE_REPO/$BRANCH --message "Fine-tuning of $BASE_MODEL" \
#--meta lora_adapter="$LORA_ADAPTER" --meta source_model="$BASE_MODEL"