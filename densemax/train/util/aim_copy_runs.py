#!/usr/bin/env python3
import argparse
import time
from typing import Any, Dict, List

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


def run_time(run) -> float:
    # Prefer real timestamps if available
    for attr in ("created_at", "start_time"):
        v = getattr(run, attr, None)
        if v is not None:
            return float(v)
    return 0.0


def retry(op_name: str, fn, tries=60, sleep_s=0.5):
    last = None
    for i in range(1, tries + 1):
        try:
            return fn()
        except Exception as e:
            last = e
            msg = str(e).lower()
            if "lock" in msg or "locked" in msg:
                print(f"[replay] {op_name}: locked, retry {i}/{tries}")
                time.sleep(sleep_s)
                continue
            raise
    raise RuntimeError(f"{op_name} failed after {tries} retries: {last}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="Source repo root (contains .aim), e.g. /tmp/aim")
    ap.add_argument("--dst", required=True, help="Central repo root, e.g. /opt/aim")
    args = ap.parse_args()

    src = Repo(args.src, read_only=True)
    dst = Repo(args.dst)

    runs: List[Any] = list(src.iter_runs())
    if not runs:
        print("[replay] no runs found in source repo")
        return 0

    # Determine latest experiment by latest run timestamp
    runs.sort(key=run_time)
    latest_run = runs[-1]
    latest_experiment = getattr(latest_run, "experiment", None)

    print(f"[replay] latest experiment: {latest_experiment}")

    exp_runs = [r for r in runs if getattr(r, "experiment", None) == latest_experiment]
    exp_runs.sort(key=run_time)

    print(f"[replay] runs in experiment: {len(exp_runs)}")
    print("[replay] run hashes:", [r.hash for r in exp_runs])

    for r in exp_runs:
        h = r.hash
        print(f"\n[replay] === replaying run {h} ===")

        # delete existing run in dst
        def _delete():
            existing = dst.get_run(h)
            if existing is not None:
                print(f"[replay] deleting dst run {h}")
                dst.delete_run(h)

        retry(f"delete_run({h})", _delete)

        # recreate run with same hash + experiment
        def _create():
            return Run(
                run_hash=h,
                repo=args.dst,
                experiment=latest_experiment,
            )

        dst_run = retry(f"create_run({h})", _create)

        # replay metrics
        q = f"run.hash == '{h}'"
        total_points = 0

        for run_metrics_collection in src.query_metrics(q).iter_runs():
            for metric in run_metrics_collection:
                name = metric.name
                context = ctx_to_dict(metric.context)
                steps, vals = metric.values.sparse_numpy()

                if not len(vals):
                    continue

                print(f"[replay] metric={name} ctx={context} points={len(vals)}")

                for step, val in zip(steps, vals):
                    dst_run.track(
                        float(val),
                        name=name,
                        step=int(step),
                        context=context,
                    )
                total_points += len(vals)

        print(f"[replay] total points replayed for run {h}: {total_points}")

        retry(f"close_run({h})", dst_run.close)

    print("[replay] done (latest experiment fully replayed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
