#!/bin/bash

set -eo pipefail
export PYTHONUNBUFFERED=1

echo "Starting vllm controller"
cd /opt/densemax/serve
source .venv/bin/activate
echo "TP: ${VLLM_TP}"
nohup uvicorn vllm-controller:app --host 0.0.0.0 --port 9000 --reload --workers 1 > /var/log/vllm-controller.log 2>&1 &

cd /opt/densemax/sky
source .venv/bin/activate

echo "Preparing sky config file"
CONFIG=$WORK_DIR/config.yaml
echo "$SKY_CONFIG" > $CONFIG

CLUSTER="${JOB_ID}-cluster"
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

# Launch training in the sky
export SKYPILOT_DISABLE_USAGE_COLLECTION=1
sky launch -dy -c "$CLUSTER" "$CONFIG"

# Sync AIM metrics periodically
aim_sync() {
  rsync -Pavz --delete "${CLUSTER}:/opt/aim/" "/tmp/aim/" > /dev/null 2>&1 || true
  yes | aim storage --repo /tmp/aim/ reindex > /dev/null 2>&1 || true
  python /usr/bin/aim_copy_runs.py --src "/tmp/aim/" --dst "/opt/aim/" > /dev/null 2>&1 || true
}

mkdir -p /tmp/aim
(
  while true; do
    aim_sync
    sleep 5
  done
) &
AIM_SYNC_PID=$!

# Stream sky logs
sky logs "$CLUSTER" --follow --tail 1000 &
LOG_FOLLOW_PID=$!

JOB_OK=0
while true; do
  # --status: return 0 if succeeded; otherwise non-zero
  if sky logs "$CLUSTER" --status > /dev/null 2>&1; then
    JOB_OK=1
    break
  fi

  rc=$?
  # From docs: 100 failed, 101 not finished, 102 not found, 103 cancelled.
  if [[ "$rc" -eq 100 || "$rc" -eq 102 || "$rc" -eq 103 ]]; then
    JOB_OK=0
    break
  fi

  # rc=101 (not finished)
  sleep 5
done

# Stop background log tail + aim sync
kill "$LOG_FOLLOW_PID" > /dev/null 2>&1 || true
wait "$LOG_FOLLOW_PID" > /dev/null 2>&1 || true

kill "$AIM_SYNC_PID" > /dev/null 2>&1 || true
wait "$AIM_SYNC_PID" > /dev/null 2>&1 || true

if [[ "$JOB_OK" -ne 1 ]]; then
  echo "Job did not succeed (see logs above). Skipping final rsync."
  exit 1
fi

# Final rsync after job success (remote -> local)
mkdir -p $WORK_DIR/outputs
rsync -Pavz "${CLUSTER}:${WORK_DIR}/outputs/" "${WORK_DIR}/outputs/"
aim_sync

echo "Preparing lakefs branch"
lakectl branch create lakefs://$SOURCE_REPO/$BRANCH -s lakefs://$BASE_MODEL

if [[ "$LORA_ADAPTER" == "true" ]]; then
  echo "Uploading LoRA adapter"
  if [[ "$USE_AXOLOTL_TRAINING_LIBRARY" == "true" ]]; then
    lakectl fs upload -rs $WORK_DIR/outputs/lora/ lakefs://$SOURCE_REPO/$BRANCH/
  else
    lakectl fs upload -rs $WORK_DIR/outputs/ lakefs://$SOURCE_REPO/$BRANCH/
  fi
else
  if [[ "$USE_AXOLOTL_TRAINING_LIBRARY" == "true" ]]; then
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

echo "Shutting down cluster"
sky down -y $CLUSTER

# keep job pod for testing (it will be deleted by studio)
tail -f > /dev/null