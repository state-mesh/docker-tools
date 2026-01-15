#!/bin/bash
set -euo pipefail

cd /opt/densemax/eval
source /opt/densemax/eval/.venv/bin/activate

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
DEPLOYED_MODEL_NAME="${DEPLOYED_MODEL_NAME:-model}"
DEPLOYED_MODEL_NAMESPACE="${DEPLOYED_MODEL_NAMESPACE:-default}"
BENCHMARKS="${BENCHMARKS:-[]}"
LANGUAGE="${LANGUAGE:-en}"
USE_GATEWAY="${USE_GATEWAY:-false}"
JUDGE_MODEL="${JUDGE_MODEL:-}"
JUDGE_MODEL_API="${JUDGE_MODEL_API:-}"
QUALITY_METRICS="${QUALITY_METRICS:-[]}"
CONVERSATION_METRICS="${CONVERSATION_METRICS:-[]}"
PERFORMANCE_METRICS="${PERFORMANCE_METRICS:-[]}"
RESULTS_REPO="${RESULTS_REPO:-eval-results}"
RESULTS_BRANCH="${RESULTS_BRANCH:-main}"
JOB_NAME="${JOB_NAME:-DenseMAX Evaluation}"
JOB_DESCRIPTION="${JOB_DESCRIPTION:-Auto-generated evaluation config}"

WORK_DIR="${WORK_DIR:-/tmp/eval}"
mkdir -p "${WORK_DIR}"

export PYTHONUNBUFFERED=1
CONFIG="${WORK_DIR}/eval_config.yaml"

echo "=========================================="
echo "DenseMAX Evaluation Runner"
echo "=========================================="
echo " DEPLOYED_MODEL_NAME: ${DEPLOYED_MODEL_NAME}"
echo " DEPLOYED_MODEL_NAMESPACE: ${DEPLOYED_MODEL_NAMESPACE}"
echo " MODEL_ENDPOINT: ${MODEL_ENDPOINT}"
echo " LANGUAGE: ${LANGUAGE}"
echo " USE_GATEWAY: ${USE_GATEWAY}"
echo " JUDGE_MODEL: ${JUDGE_MODEL:-none}"
echo "=========================================="

# Generate YAML config using Python
python3 << PYTHON_SCRIPT
import json
import os
import yaml

job_name = os.environ.get('JOB_NAME', 'DenseMAX Evaluation')
job_description = os.environ.get('JOB_DESCRIPTION', 'Auto-generated evaluation config')

config = {
    'project': {
        'name': job_name,
        'version': '1.0.0',
        'description': job_description,
    },
    'targets': [],
}

deployed_model_name = os.environ.get('DEPLOYED_MODEL_NAME', '')
model_endpoint = os.environ.get('MODEL_ENDPOINT', '')
language = os.environ.get('LANGUAGE', 'en')
judge_model = os.environ.get('JUDGE_MODEL', '')
judge_model_api = os.environ.get('JUDGE_MODEL_API', '')
benchmarks_json = os.environ.get('BENCHMARKS', '[]')
quality_metrics_json = os.environ.get('QUALITY_METRICS', '[]')
conversation_metrics_json = os.environ.get('CONVERSATION_METRICS', '[]')
work_dir = os.environ.get('WORK_DIR', '/tmp/eval')
config_path = f'{work_dir}/eval_config.yaml'

if judge_model:
    judge_target = {
        'name': 'judge-model',
        'type': 'llm',
        'provider': 'openai',
        'model': judge_model,
    }
    if judge_model_api:
        judge_target['api_key'] = judge_model_api
    config['targets'].append(judge_target)

main_target = {
    'name': 'model-under-test',
    'type': 'llm',
    'provider': 'openai',
    'model': deployed_model_name,
    'base_url': model_endpoint,
    'api_key': 'sk-no-key-required',
    'evaluations': [],
}

try:
    benchmarks = json.loads(benchmarks_json)
    if benchmarks:
        benchmark_list = []
        for b in benchmarks:
            benchmark = {
                'name': b.get('name', '').lower().replace(' ', '_').replace('-', '_'),
                'num_fewshot': b.get('shots', 1),
            }

            selected_tasks = b.get('selectedTasks', [])
            if selected_tasks and 'All' not in selected_tasks:
                benchmark['subset'] = [t.lower() for t in selected_tasks]

            custom_repo = b.get('customDatasetRepo')
            custom_ref = b.get('customDatasetRef')
            if custom_repo:
                ref = custom_ref if custom_ref else 'main'
                benchmark['path'] = f'lakefs://{custom_repo}/{ref}'

            dataset_hub = b.get('datasetHub', 'huggingface')
            if dataset_hub and dataset_hub != 'huggingface':
                benchmark['dataset_hub'] = dataset_hub

            if language and language != 'en':
                benchmark['language'] = language

            benchmark_list.append(benchmark)

        if benchmark_list:
            main_target['evaluations'].append({
                'name': 'accuracy-benchmarks',
                'benchmarks': benchmark_list,
            })
except json.JSONDecodeError as e:
    print(f"Warning: Failed to parse BENCHMARKS: {e}")

try:
    quality_metrics = json.loads(quality_metrics_json)
    for m in quality_metrics:
        dataset_repo = m.get('datasetRepo')
        dataset_ref = m.get('datasetRef', 'main')
        if not dataset_repo:
            print(f"Warning: Quality metric {m.get('name')} has no dataset, skipping")
            continue

        metric_config = {
            'name': m.get('name', '').lower(),
            'type': 'g_eval',
        }
        if m.get('criteria'):
            metric_config['criteria'] = m['criteria']

        if judge_model:
            metric_config['judge_model'] = {'target': 'judge-model'}

        main_target['evaluations'].append({
            'name': f"quality-{m.get('name', '').lower().replace(' ', '-')}",
            'dataset': f"lakefs://{dataset_repo}/{dataset_ref}",
            'metrics': [metric_config],
        })
except json.JSONDecodeError as e:
    print(f"Warning: Failed to parse QUALITY_METRICS: {e}")

try:
    conversation_metrics = json.loads(conversation_metrics_json)
    for m in conversation_metrics:
        dataset_repo = m.get('datasetRepo')
        dataset_ref = m.get('datasetRef', 'main')
        if not dataset_repo:
            print(f"Warning: Conversation metric {m.get('name')} has no dataset, skipping")
            continue

        metric_name = m.get('name', '').lower().replace(' ', '_')
        metric_config = {
            'name': metric_name,
            'type': metric_name,
        }

        config_label = m.get('configLabel', '').lower().replace(' ', '_')
        config_value = m.get('configValue')
        if config_label and config_value is not None:
            metric_config[config_label] = config_value

        if judge_model:
            metric_config['judge_model'] = {'target': 'judge-model'}

        main_target['evaluations'].append({
            'name': f"conv-{m.get('name', '').lower().replace(' ', '-')}",
            'dataset': f"lakefs://{dataset_repo}/{dataset_ref}",
            'metrics': [metric_config],
        })
except json.JSONDecodeError as e:
    print(f"Warning: Failed to parse CONVERSATION_METRICS: {e}")

config['targets'].append(main_target)

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)

print(f"Generated config at {config_path}:")
print("-" * 40)
with open(config_path, 'r') as f:
    print(f.read())
print("-" * 40)
PYTHON_SCRIPT

echo "Running evaluation..."
surogate-eval eval --config "${CONFIG}"

if [[ -d "eval_results" ]]; then
    echo "Preparing LakeFS for results"

    export LAKECTL_SERVER_ENDPOINT_URL="${LAKEFS_ENDPOINT}"
    export LAKECTL_CREDENTIALS_ACCESS_KEY_ID="${LAKEFS_KEY}"
    export LAKECTL_CREDENTIALS_SECRET_ACCESS_KEY="${LAKEFS_SECRET}"

    lakectl repo create "lakefs://${RESULTS_REPO}" "local://${RESULTS_REPO}" 2>/dev/null || true

    echo "Uploading evaluation results to lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}/"
    for file in eval_results/*; do
        if [[ -f "$file" ]]; then
            filename=$(basename "$file")
            lakectl fs upload -s "$file" "lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}/eval_results/${filename}"
        fi
    done

    lakectl commit "lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}" \
        --message "Evaluation results for ${DEPLOYED_MODEL_NAME} $(date -Iseconds)" \
        --meta deployed_model="${DEPLOYED_MODEL_NAME}" \
        --meta deployed_namespace="${DEPLOYED_MODEL_NAMESPACE}" \
        --meta language="${LANGUAGE}"

    echo "Results uploaded to lakefs://${RESULTS_REPO}/${RESULTS_BRANCH}/eval_results/"
fi

echo "=========================================="
echo "Evaluation complete!"
echo "=========================================="