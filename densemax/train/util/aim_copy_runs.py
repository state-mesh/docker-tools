#!/usr/bin/env python3
import argparse
import sys
import time
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple
from aim import Repo, Run


def ctx_to_dict(ctx: Any) -> Dict[str, Any]:
    if ctx is None:
        return {}
    if isinstance(ctx, dict):
        return ctx
    try:
        return dict(ctx)
    except Exception:
        return {}


def run_time(run: Any) -> float:
    """Return a sortable timestamp for a run."""
    for attr in ("created_at", "start_time"):
        v = getattr(run, attr, None)
        if v is None:
            continue

        if isinstance(v, datetime):
            return float(v.timestamp())

        if isinstance(v, (int, float)):
            return float(v)

        if isinstance(v, str):
            try:
                return float(v)
            except Exception:
                return 0.0

        if hasattr(v, "timestamp"):
            try:
                return float(v.timestamp())
            except Exception:
                pass

    return 0.0


def is_lock_error(e: Exception) -> bool:
    msg = str(e).lower()
    return ("lock" in msg) or ("locked" in msg)


def retry(op_name: str, fn, tries: int = 120, sleep_s: float = 0.5):
    last: Optional[Exception] = None
    for i in range(1, tries + 1):
        try:
            return fn()
        except Exception as e:
            last = e
            if is_lock_error(e):
                print(f"[replay] {op_name}: locked, retry {i}/{tries} in {sleep_s}s")
                time.sleep(sleep_s)
                continue
            raise
    raise RuntimeError(f"{op_name} failed after {tries} retries: {last}")


def latest_experiment_and_runs(src: Repo) -> Tuple[Optional[str], List[Any]]:
    runs: List[Any] = list(src.iter_runs())
    if not runs:
        return None, []

    runs.sort(key=run_time)
    latest_run = runs[-1]
    latest_exp = getattr(latest_run, "experiment", None)

    exp_runs = [r for r in runs if getattr(r, "experiment", None) == latest_exp]
    exp_runs.sort(key=run_time)
    return latest_exp, exp_runs


def delete_dst_experiment_runs(dst: Repo, experiment: Optional[str]):
    dst_runs = list(dst.iter_runs())
    to_delete = [r.hash for r in dst_runs if getattr(r, "experiment", None) == experiment]

    print(f"[replay] dst runs to delete for experiment={experiment}: {len(to_delete)}")
    for h in to_delete:
        print(f"[replay] deleting dst run {h}")
        retry(f"delete_run({h})", lambda h=h: dst.delete_run(h))


def replay_src_run_to_new_dst_run(
        src: Repo,
        dst_repo_path: str,
        experiment: Optional[str],
        src_run_hash: str,
):
    print(f"[replay] creating new dst run for src_hash={src_run_hash} experiment={experiment}")

    # Create NEW run (new hash) - do not use run_hash=..., because that tries to open existing.
    dst_run = retry(
        f"create_run(experiment={experiment})",
        lambda: Run(repo=dst_repo_path, experiment=experiment),
    )

    # Link back to source run hash for traceability
    try:
        dst_run["source_hash"] = src_run_hash
    except Exception as e:
        print(f"[replay] warning: could not set source_hash metadata: {e}")

    q = f"run.hash == '{src_run_hash}'"
    print(f"[replay] querying src metrics: {q}")

    total_points = 0
    metric_count = 0

    for run_metrics_collection in src.query_metrics(q).iter_runs():
        for metric in run_metrics_collection:
            metric_count += 1
            name = metric.name
            context = ctx_to_dict(metric.context)

            steps, vals = metric.values.sparse_numpy()
            n = len(vals)
            if n == 0:
                continue

            print(f"[replay] metric={name} ctx={context} points={n}")

            for step, val in zip(steps, vals):
                dst_run.track(float(val), name=name, step=int(step), context=context)

            total_points += n

    print(f"[replay] replayed metrics={metric_count} total_points={total_points} for src_hash={src_run_hash}")
    retry("close_run()", dst_run.close)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="Source repo root (contains .aim), e.g. /tmp/aim")
    ap.add_argument("--dst", required=True, help="Destination repo root (central), e.g. /opt/aim")
    args = ap.parse_args()

    src = Repo(args.src)
    experiment, exp_runs = latest_experiment_and_runs(src)
    if experiment is None or not exp_runs:
        print("[replay] no runs/experiments found in source")
        return 0

    print(f"[replay] latest experiment: {experiment}")
    print(f"[replay] src runs in latest experiment: {len(exp_runs)}")
    print("[replay] src hashes:", [r.hash for r in exp_runs])

    for r in exp_runs:
        replay_src_run_to_new_dst_run(
            src=src,
            dst_repo_path=args.dst,
            experiment=experiment,
            src_run_hash=r.hash,
        )

    print("[replay] done (latest experiment replayed into dst)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as e:
        print(f"[replay] ERROR: {e}", file=sys.stderr)
        raise SystemExit(1)
