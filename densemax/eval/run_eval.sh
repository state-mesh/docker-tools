#!/bin/bash
set -euo pipefail

cd /opt/densemax/eval
source /opt/densemax/eval/.venv/bin/activate

# Job identification
EVAL_JOB_ID="${EVAL_JOB_ID:-}"
export EVAL_JOB_ID

# Model endpoints
MODEL_ENDPOINT="${MODEL_ENDPOINT:-}"
MODEL_ENDPOINT_FALLBACK="${MODEL_ENDPOINT_FALLBACK:-}"

# Validate we have at least one endpoint
if [ -z "$MODEL_ENDPOINT" ] && [ -z "$MODEL_ENDPOINT_FALLBACK" ]; then
    echo "ERROR: Neither MODEL_ENDPOINT nor MODEL_ENDPOINT_FALLBACK is set"
    exit 1
fi

# Test internal endpoint, fallback to ingress if needed
if [ -n "$MODEL_ENDPOINT" ]; then
    echo "Testing internal endpoint: ${MODEL_ENDPOINT}"
    if curl -s --connect-timeout 5 "${MODEL_ENDPOINT}/models" > /dev/null 2>&1; then
        echo "Internal endpoint is reachable"
        FINAL_ENDPOINT="${MODEL_ENDPOINT}"
    else
        echo "Internal endpoint not reachable, trying fallback..."
        if [ -n "$MODEL_ENDPOINT_FALLBACK" ]; then
            FINAL_ENDPOINT="${MODEL_ENDPOINT_FALLBACK}"
            echo "Using fallback endpoint: ${FINAL_ENDPOINT}"
        else
            echo "ERROR: Internal endpoint not reachable and no fallback available"
            exit 1
        fi
    fi
else
    FINAL_ENDPOINT="${MODEL_ENDPOINT_FALLBACK}"
    echo "No internal endpoint, using fallback: ${FINAL_ENDPOINT}"
fi

export MODEL_ENDPOINT="${FINAL_ENDPOINT}"

# Optional env vars with defaults
export DEPLOYED_MODEL_NAME="${DEPLOYED_MODEL_NAME:-model}"
export DEPLOYED_MODEL_NAMESPACE="${DEPLOYED_MODEL_NAMESPACE:-default}"
export BENCHMARKS="${BENCHMARKS:-[]}"
export LANGUAGE="${LANGUAGE:-en}"
export USE_GATEWAY="${USE_GATEWAY:-false}"

# Judge model config
export JUDGE_MODEL="${JUDGE_MODEL:-}"
export JUDGE_MODEL_API="${JUDGE_MODEL_API:-}"
export JUDGE_MODEL_BASE_URL="${JUDGE_MODEL_BASE_URL:-}"
export JUDGE_MODEL_PROVIDER="${JUDGE_MODEL_PROVIDER:-openai}"

# Simulator model config
export SIMULATOR_MODEL="${SIMULATOR_MODEL:-}"
export SIMULATOR_MODEL_API="${SIMULATOR_MODEL_API:-}"
export SIMULATOR_MODEL_BASE_URL="${SIMULATOR_MODEL_BASE_URL:-}"
export SIMULATOR_MODEL_PROVIDER="${SIMULATOR_MODEL_PROVIDER:-openai}"

export QUALITY_METRICS="${QUALITY_METRICS:-[]}"
export CONVERSATION_METRICS="${CONVERSATION_METRICS:-[]}"
export PERFORMANCE_METRICS="${PERFORMANCE_METRICS:-[]}"
export CUSTOM_EVAL_DATASETS="${CUSTOM_EVAL_DATASETS:-[]}"
export RESULTS_REPO="${RESULTS_REPO:-eval-results}"
export RESULTS_BRANCH="${RESULTS_BRANCH:-main}"
export SECURITY_TESTS="${SECURITY_TESTS:-[]}"
export RED_TEAMING_CONFIG="${RED_TEAMING_CONFIG:-{}}"
export JOB_NAME="${JOB_NAME:-DenseMAX Evaluation}"
export JOB_DESCRIPTION="${JOB_DESCRIPTION:-Auto-generated evaluation config}"
export LAKECTL_SERVER_ENDPOINT_URL="${LAKEFS_ENDPOINT}"
export LAKECTL_CREDENTIALS_ACCESS_KEY_ID="${LAKEFS_KEY}"
export LAKECTL_CREDENTIALS_SECRET_ACCESS_KEY="${LAKEFS_SECRET}"

WORK_DIR="${WORK_DIR:-/tmp/eval}"
mkdir -p "${WORK_DIR}"

export PYTHONUNBUFFERED=1
CONFIG="${WORK_DIR}/eval_config.yaml"

echo "=========================================="
echo "DenseMAX Evaluation Runner"
echo "=========================================="
echo " EVAL_JOB_ID: ${EVAL_JOB_ID:-not set}"
echo " DEPLOYED_MODEL_NAME: ${DEPLOYED_MODEL_NAME}"
echo " DEPLOYED_MODEL_NAMESPACE: ${DEPLOYED_MODEL_NAMESPACE}"
echo " MODEL_ENDPOINT: ${MODEL_ENDPOINT}"
echo " LANGUAGE: ${LANGUAGE}"
echo " USE_GATEWAY: ${USE_GATEWAY}"
echo " JUDGE_MODEL: ${JUDGE_MODEL:-none}"
echo " JUDGE_MODEL_BASE_URL: ${JUDGE_MODEL_BASE_URL:-default}"
echo " JUDGE_MODEL_PROVIDER: ${JUDGE_MODEL_PROVIDER}"
echo " SIMULATOR_MODEL: ${SIMULATOR_MODEL:-same as judge}"
echo " SIMULATOR_MODEL_BASE_URL: ${SIMULATOR_MODEL_BASE_URL:-same as judge}"
echo " SIMULATOR_MODEL_PROVIDER: ${SIMULATOR_MODEL_PROVIDER}"
echo " SECURITY_TESTS: ${SECURITY_TESTS}"
echo " RED_TEAMING: ${RED_TEAMING_CONFIG}"
echo " CUSTOM_EVAL_DATASETS: ${CUSTOM_EVAL_DATASETS}"
echo "=========================================="

# Generate config
python3 /opt/densemax/eval/generate_config.py "${CONFIG}"

# Set API keys for red teaming (priority: simulator > judge)
if [ -n "${SIMULATOR_MODEL_API}" ]; then
    export OPENAI_API_KEY="${SIMULATOR_MODEL_API}"
    echo "OPENAI_API_KEY set from SIMULATOR_MODEL_API"
elif [ -n "${JUDGE_MODEL_API}" ]; then
    export OPENAI_API_KEY="${JUDGE_MODEL_API}"
    echo "OPENAI_API_KEY set from JUDGE_MODEL_API"
else
    echo "WARNING: No API key provided for simulator/judge models. Red teaming may fail."
fi

# Set base URL for OpenRouter or custom endpoints
if [ -n "${SIMULATOR_MODEL_BASE_URL}" ]; then
    export OPENAI_API_BASE="${SIMULATOR_MODEL_BASE_URL}"
    echo "OPENAI_API_BASE set from SIMULATOR_MODEL_BASE_URL: ${SIMULATOR_MODEL_BASE_URL}"
elif [ -n "${JUDGE_MODEL_BASE_URL}" ]; then
    export OPENAI_API_BASE="${JUDGE_MODEL_BASE_URL}"
    echo "OPENAI_API_BASE set from JUDGE_MODEL_BASE_URL: ${JUDGE_MODEL_BASE_URL}"
fi

echo "Running evaluation..."
surogate-eval eval --config "${CONFIG}"

if [[ -d "eval_results" ]]; then
    echo "Preparing LakeFS for results"

    lakectl repo create "lakefs://${RESULTS_REPO}" "local://${RESULTS_REPO}" 2>/dev/null || true

    echo "Uploading evaluation results to lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}/"
    for file in eval_results/*; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")

            if [[ -n "${EVAL_JOB_ID}" ]]; then
                if [[ "$filename" == eval_*.json ]]; then
                    new_filename="eval_${EVAL_JOB_ID}.json"
                elif [[ "$filename" == report_*.md ]]; then
                    new_filename="report_${EVAL_JOB_ID}.md"
                elif [[ "$filename" == report_*.pdf ]]; then
                    new_filename="report_${EVAL_JOB_ID}.pdf"
                else
                    new_filename="$filename"
                fi
            else
                new_filename="$filename"
            fi

            echo "Uploading ${filename} as ${new_filename}"
            lakectl fs upload -s "$file" "lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}/eval_results/${new_filename}"
        fi
    done

    lakectl commit "lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}" \
        --message "Evaluation results for ${DEPLOYED_MODEL_NAME} $(date -Iseconds)" \
        --meta deployed_model="${DEPLOYED_MODEL_NAME}" \
        --meta deployed_namespace="${DEPLOYED_MODEL_NAMESPACE}" \
        --meta language="${LANGUAGE}" \
        --meta job_id="${EVAL_JOB_ID:-unknown}"

    echo "Results uploaded to lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}/eval_results/"
fi

echo "=========================================="
echo "Evaluation complete!"
echo "=========================================="