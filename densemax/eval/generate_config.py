#!/usr/bin/env python3
import json
import os
import yaml


def sanitize_json(json_str):
    """Remove trailing extra braces if brace count is unbalanced."""
    json_str = json_str.strip()
    open_count = json_str.count('{')
    close_count = json_str.count('}')
    while close_count > open_count and json_str.endswith('}'):
        json_str = json_str[:-1]
        close_count -= 1
    return json_str


def generate_config(config_path):
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
    judge_model_base_url = os.environ.get('JUDGE_MODEL_BASE_URL', '')
    simulator_model = os.environ.get('SIMULATOR_MODEL', '')
    simulator_model_api = os.environ.get('SIMULATOR_MODEL_API', '')
    simulator_model_base_url = os.environ.get('SIMULATOR_MODEL_BASE_URL', '')
    benchmarks_json = os.environ.get('BENCHMARKS', '[]')
    quality_metrics_json = os.environ.get('QUALITY_METRICS', '[]')
    conversation_metrics_json = os.environ.get('CONVERSATION_METRICS', '[]')
    security_tests_json = os.environ.get('SECURITY_TESTS', '[]')
    red_teaming_config_json = os.environ.get('RED_TEAMING_CONFIG', '{}')

    # Add judge model target if configured
    if judge_model:
        judge_target = {
            'name': 'judge-model',
            'type': 'llm',
            'provider': 'openai',
            'model': judge_model,
        }
        if judge_model_api:
            judge_target['api_key'] = judge_model_api
        if judge_model_base_url:
            judge_target['base_url'] = judge_model_base_url
        config['targets'].append(judge_target)

    # Add simulator model target if configured (separate from judge)
    if simulator_model and simulator_model != judge_model:
        simulator_target = {
            'name': 'simulator-model',
            'type': 'llm',
            'provider': 'openai',
            'model': simulator_model,
        }
        sim_api = simulator_model_api or judge_model_api
        if sim_api:
            simulator_target['api_key'] = sim_api
        sim_base_url = simulator_model_base_url or judge_model_base_url
        if sim_base_url:
            simulator_target['base_url'] = sim_base_url
        config['targets'].append(simulator_target)

    # Main target - model under test
    main_target = {
        'name': 'model-under-test',
        'type': 'llm',
        'provider': 'openai',
        'model': deployed_model_name,
        'base_url': model_endpoint,
        'api_key': 'sk-no-key-required',
        'infrastructure': {
            'backend': 'local',
            'workers': 2,
        },
        'evaluations': [],
    }

    # Parse benchmarks
    try:
        benchmarks = json.loads(benchmarks_json)
        if benchmarks:
            benchmark_list = []
            for b in benchmarks:
                benchmark_name = b.get('evalScopeName') or b.get('name', '').lower().replace(' ', '_').replace('-', '_')
                supports_fewshot = b.get('supportsFewshot', True)

                benchmark = {
                    'name': benchmark_name,
                    'num_fewshot': b.get('shots', 0) if supports_fewshot else 0,
                }

                limit = b.get('limit')
                if limit:
                    benchmark['limit'] = limit

                selected_tasks = b.get('selectedTasks', [])
                if selected_tasks and 'All' not in selected_tasks:
                    benchmark['subset'] = [t.lower() for t in selected_tasks]

                if language and language != 'en':
                    benchmark['language'] = language

                max_workers = b.get('maxWorkers', 4)
                if max_workers and max_workers > 1:
                    benchmark['backend_params'] = {
                        'max_workers': max_workers,
                    }

                benchmark_list.append(benchmark)

            if benchmark_list:
                main_target['evaluations'].append({
                    'name': 'accuracy-benchmarks',
                    'benchmarks': benchmark_list,
                })
    except json.JSONDecodeError as e:
        print(f"Warning: Failed to parse BENCHMARKS: {e}")

    # Parse quality metrics
    try:
        quality_metrics = json.loads(quality_metrics_json)
        for m in quality_metrics:
            dataset_repo = m.get('datasetRepo')
            dataset_ref = m.get('datasetRef', 'main')
            dataset_path = m.get('datasetPath', '')

            if not dataset_repo:
                print(f"Warning: Quality metric {m.get('name')} has no dataset repo, skipping")
                continue

            if not dataset_path:
                print(f"Warning: Quality metric {m.get('name')} has no dataset path, skipping")
                continue

            # Build full LakeFS path
            dataset_full_path = f"lakefs://{dataset_repo}/{dataset_ref}/{dataset_path}"

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
                'dataset': dataset_full_path,
                'metrics': [metric_config],
            })
    except json.JSONDecodeError as e:
        print(f"Warning: Failed to parse QUALITY_METRICS: {e}")

    # Parse conversation metrics
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

    # Parse security tests (Red Teaming)
    try:
        security_tests = json.loads(security_tests_json)
        rtc = sanitize_json(red_teaming_config_json)
        red_teaming_config = json.loads(rtc) if rtc else {}

        if security_tests and red_teaming_config.get('enabled', False):
            vulnerabilities = []
            vulnerability_types = {}
            all_attacks = set()

            for test in security_tests:
                vuln_name = test.get('evalScopeName')
                if not vuln_name:
                    continue

                vulnerabilities.append(vuln_name)

                selected_subtypes = test.get('selectedSubtypes', [])
                if selected_subtypes:
                    vulnerability_types[vuln_name] = selected_subtypes

                attacks = test.get('attacks', [])
                all_attacks.update(attacks)

            if vulnerabilities:
                red_teaming = {
                    'enabled': True,
                    'vulnerabilities': vulnerabilities,
                    'attacks': list(all_attacks) if all_attacks else ['prompt_injection', 'roleplay', 'prompt_probing'],
                    'attacks_per_vulnerability': red_teaming_config.get('attacksPerVulnerability', 3),
                    'max_concurrent': red_teaming_config.get('maxConcurrent', 5),
                }

                if vulnerability_types:
                    red_teaming['vulnerability_types'] = vulnerability_types

                purpose = red_teaming_config.get('purpose', '')
                if purpose:
                    red_teaming['purpose'] = purpose

                if simulator_model:
                    red_teaming['simulator_model'] = simulator_model
                    if simulator_model != judge_model:
                        red_teaming['simulator_target'] = 'simulator-model'
                    sim_base_url = simulator_model_base_url or judge_model_base_url
                    if sim_base_url:
                        red_teaming['simulator_base_url'] = sim_base_url
                elif judge_model:
                    red_teaming['simulator_model'] = judge_model
                    red_teaming['simulator_target'] = 'judge-model'
                    if judge_model_base_url:
                        red_teaming['simulator_base_url'] = judge_model_base_url
                else:
                    red_teaming['simulator_model'] = 'gpt-3.5-turbo'

                if judge_model:
                    red_teaming['evaluation_model'] = judge_model
                    red_teaming['evaluation_target'] = 'judge-model'
                    if judge_model_base_url:
                        red_teaming['evaluation_base_url'] = judge_model_base_url
                else:
                    red_teaming['evaluation_model'] = 'gpt-4o-mini'

                api_key = simulator_model_api or judge_model_api
                if api_key:
                    os.environ['OPENAI_API_KEY'] = api_key
                    print(f"Set OPENAI_API_KEY from {'simulator' if simulator_model_api else 'judge'} model API")
                else:
                    print("WARNING: No API key provided for simulator/judge models. Red teaming may fail.")

                main_target['red_teaming'] = red_teaming
                main_target['guardrails'] = {'enabled': False}

                print(f"Red teaming enabled:")
                print(f"  - Vulnerabilities: {len(vulnerabilities)}")
                print(f"  - Attack types: {list(all_attacks)}")
                print(f"  - Simulator model: {red_teaming.get('simulator_model')} (target: {red_teaming.get('simulator_target', 'default')})")
                print(f"  - Simulator base URL: {red_teaming.get('simulator_base_url', 'default')}")
                print(f"  - Evaluation model: {red_teaming.get('evaluation_model')} (target: {red_teaming.get('evaluation_target', 'default')})")
                print(f"  - Evaluation base URL: {red_teaming.get('evaluation_base_url', 'default')}")

    except json.JSONDecodeError as e:
        print(f"Warning: Failed to parse SECURITY_TESTS or RED_TEAMING_CONFIG: {e}")
        import traceback
        traceback.print_exc()

    config['targets'].append(main_target)

    # Write config
    with open(config_path, 'w') as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)

    print(f"\nGenerated config at {config_path}:")
    print("-" * 40)
    with open(config_path, 'r') as f:
        print(f.read())
    print("-" * 40)


if __name__ == '__main__':
    import sys
    config_path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/eval/eval_config.yaml'
    generate_config(config_path)