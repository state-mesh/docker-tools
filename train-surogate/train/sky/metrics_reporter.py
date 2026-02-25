#!/usr/bin/env python3
"""
Background metrics reporter that reads AIM training metrics
and outputs structured TRAINING_METRICS lines to stdout.
These lines flow through sky logs back to the densemax orchestrator pod,
where the Java log parser picks them up for real-time status updates.
"""
import json
import sys
import time

from aim import Repo


def get_latest_metrics(repo_path: str) -> dict | None:
    try:
        repo = Repo(repo_path, read_only=True)
    except Exception:
        return None

    runs = list(repo.iter_runs())
    if not runs:
        return None

    # Take the most recent run
    run = runs[-1]
    run_hash = run.hash

    metrics = {}
    for run_metrics in repo.query_metrics(f"run.hash == '{run_hash}'").iter_runs():
        for metric in run_metrics:
            name = metric.name
            steps, columns = metric.data.numpy()
            vals = columns[0]
            if len(vals) == 0:
                continue
            # Take the latest value
            metrics[name] = {
                "step": int(steps[-1]),
                "value": float(vals[-1]),
            }

    if not metrics:
        return None

    result = {}

    # Extract step/total_steps
    if "global_step" in metrics:
        result["step"] = metrics["global_step"]["step"]
    elif any(m in metrics for m in ("loss", "train_loss")):
        key = "loss" if "loss" in metrics else "train_loss"
        result["step"] = metrics[key]["step"]

    if "total_steps" in metrics:
        result["totalSteps"] = int(metrics["total_steps"]["value"])
    elif "max_steps" in metrics:
        result["totalSteps"] = int(metrics["max_steps"]["value"])

    # Extract epoch info
    if "epoch" in metrics:
        result["epoch"] = int(metrics["epoch"]["value"])
    if "total_epochs" in metrics:
        result["totalEpochs"] = int(metrics["total_epochs"]["value"])
    elif "num_train_epochs" in metrics:
        result["totalEpochs"] = int(metrics["num_train_epochs"]["value"])

    # Extract loss
    for key in ("loss", "train_loss", "training_loss"):
        if key in metrics:
            result["loss"] = round(metrics[key]["value"], 6)
            break

    # Extract learning rate
    for key in ("learning_rate", "lr"):
        if key in metrics:
            result["learningRate"] = metrics[key]["value"]
            break

    # Compute progress percent
    if "step" in result and "totalSteps" in result and result["totalSteps"] > 0:
        result["progressPercent"] = round(
            result["step"] / result["totalSteps"] * 100, 2
        )

    return result if result else None


def main():
    repo_path = "/opt/aim"
    interval = 10  # seconds

    last_output = None
    while True:
        try:
            metrics = get_latest_metrics(repo_path)
            if metrics and metrics != last_output:
                print(
                    f"TRAINING_METRICS: {json.dumps(metrics)}",
                    flush=True,
                )
                last_output = metrics
        except Exception:
            pass

        time.sleep(interval)


if __name__ == "__main__":
    main()
