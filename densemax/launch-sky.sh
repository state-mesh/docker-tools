#!/bin/bash

set -eo pipefail
export PYTHONUNBUFFERED=1

echo "Starting vllm controller"
cd /opt/densemax/serve
source .venv/bin/activate
nohup uvicorn vllm-controller:app --host 0.0.0.0 --port 9000 --reload --workers 1 > /var/log/vllm-controller.log 2>&1 &

cd /opt/densemax/sky
source .venv/bin/activate

echo "Preparing sky config file"
CONFIG=$WORK_DIR/config.yaml
CONFIG_AXOLOTL=$WORK_DIR/config_axolotl.yaml
echo "$SKY_CONFIG" > $CONFIG
echo "$AXOLOTL_CONFIG" > $CONFIG_AXOLOTL

CLUSTER="${JOB_ID}-cluster"
SOURCE_REPO="${BASE_MODEL%%/*}"

# Ensure sky cluster is torn down on any exit (success or failure)
cleanup() {
  local exit_code=$?
  echo "Cleaning up..."

  # Stop background processes
  kill "$LOG_FOLLOW_PID" > /dev/null 2>&1 || true
  wait "$LOG_FOLLOW_PID" > /dev/null 2>&1 || true
  kill "$METRICS_SYNC_PID" > /dev/null 2>&1 || true
  wait "$METRICS_SYNC_PID" > /dev/null 2>&1 || true

  # Always tear down the sky cluster if it was launched
  if [[ -n "${CLUSTER_LAUNCHED:-}" ]]; then
    echo "SKY_STAGE: SHUTTING_DOWN"
    echo "Shutting down cluster"
    cd /opt/densemax/sky
    source .venv/bin/activate
    sky down -y "$CLUSTER" || true
  fi

  exit "$exit_code"
}
trap cleanup EXIT
LOG_FOLLOW_PID=""
METRICS_SYNC_PID=""
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

echo "SKY_STAGE: DOWNLOADING_MODEL"
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
echo "SKY_STAGE: LAUNCHING_CLUSTER"
export SKYPILOT_DISABLE_USAGE_COLLECTION=1
set +e
sky launch -dy -c "$CLUSTER" "$CONFIG"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  echo "SKY_STAGE: FAILED:sky_launch_failed_rc=$rc"
  exit 1
fi
CLUSTER_LAUNCHED=1
echo "SKY_STAGE: CLUSTER_UP"

# Sync training metrics file periodically from remote cluster
REMOTE_METRICS_FILE="/tmp/surogate_metrics.jsonl"
LOCAL_METRICS_FILE="/tmp/surogate_metrics.jsonl"
mkdir -p "$(dirname "$LOCAL_METRICS_FILE")"

metrics_sync() {
  rsync -az "${CLUSTER}:${REMOTE_METRICS_FILE}" "$LOCAL_METRICS_FILE" > /dev/null 2>&1 || true
}

(
  while true; do
    metrics_sync
    sleep 5
  done
) &
METRICS_SYNC_PID=$!

# Stream sky logs in background for visibility
echo "SKY_STAGE: TRAINING_RUNNING"
sky logs "$CLUSTER" --follow --tail 1000 &
LOG_FOLLOW_PID=$!

# Wait for training to complete by polling for the sentinel file written
# by train-sky.sh on exit. This bypasses SkyPilot's job tracking which
# can get stuck when the training process crashes but the pod stays alive.
TRAIN_EXIT_CODE=""
while true; do
  TRAIN_EXIT_CODE=$(ssh "$CLUSTER" "cat /tmp/train_exit_code 2>/dev/null" 2>/dev/null) && break
  sleep 5
done

kill "$LOG_FOLLOW_PID" > /dev/null 2>&1 || true
wait "$LOG_FOLLOW_PID" > /dev/null 2>&1 || true

if [[ "$TRAIN_EXIT_CODE" -ne 0 ]]; then
  echo "SKY_STAGE: FAILED:training_job_failed"
  echo "Training exited with code $TRAIN_EXIT_CODE. Skipping final rsync."
  exit 1
fi

# Final rsync after job success (remote -> local)
echo "SKY_STAGE: SYNCING_OUTPUTS"
mkdir -p $WORK_DIR/outputs
rsync -Pavz "${CLUSTER}:${WORK_DIR}/outputs/" "${WORK_DIR}/outputs/"
metrics_sync

echo "SKY_STAGE: UPLOADING_RESULTS"
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
        cd /opt/densemax/train-axolotl
        source .venv/bin/activate
        .venv/bin/axolotl merge-lora $CONFIG_AXOLOTL --lora-model-dir=$WORK_DIR/outputs/lora/ \
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

echo "SKY_STAGE: SUCCEEDED"

# Tear down the ray cluster now that training is complete
echo "SKY_STAGE: SHUTTING_DOWN"
sky down -y "$CLUSTER" || true
unset CLUSTER_LAUNCHED  # prevent double teardown in cleanup trap

# Report done status through label so we can keep the pod up for testing
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
kubectl -n "$NAMESPACE" label taskRun "$JOB_ID" sky/state=SUCCEEDED --overwrite

# keep job pod for testing (it will be deleted by studio)
tail -f > /dev/null
