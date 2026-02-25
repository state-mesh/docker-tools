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
  kill "$AIM_SYNC_PID" > /dev/null 2>&1 || true
  wait "$AIM_SYNC_PID" > /dev/null 2>&1 || true

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
AIM_SYNC_PID=""
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

python -c 'from aim import Repo; Repo("/tmp/aim", init=True)'
rsync -Pavz --delete "/tmp/aim/" "${CLUSTER}:/opt/aim/"

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
echo "SKY_STAGE: TRAINING_RUNNING"
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

if [[ "$JOB_OK" -ne 1 ]]; then
  echo "SKY_STAGE: FAILED:training_job_failed"
  echo "Job did not succeed (see logs above). Skipping final rsync."
  exit 1
fi

# Final rsync after job success (remote -> local)
echo "SKY_STAGE: SYNCING_OUTPUTS"
mkdir -p $WORK_DIR/outputs
rsync -Pavz "${CLUSTER}:${WORK_DIR}/outputs/" "${WORK_DIR}/outputs/"
aim_sync

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

# Report done status through label so we can keep the pod up for testing
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
kubectl -n "$NAMESPACE" label taskRun "$JOB_ID" sky/state=SUCCEEDED --overwrite

# keep job pod for testing (it will be deleted by studio)
tail -f > /dev/null