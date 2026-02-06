#!/usr/bin/env python3
import argparse
import sys
from typing import Any, Dict, List, Optional, Tuple, Set
from aim import Repo, Run


def ctx_to_dict(ctx: Any) -> Dict[str, Any]:
    if ctx is None:
        return {}
    # Aim Context object
    to_dict = getattr(ctx, "to_dict", None)
    if callable(to_dict):
        return to_dict()
    if isinstance(ctx, dict):
        return ctx
    try:
        return dict(ctx)
    except Exception:
        return {}

def single_experiment_and_runs(src: Repo) -> Tuple[Optional[str], List[Any]]:
    runs: List[Any] = list(src.iter_runs())
    if not runs:
        return None, []

    experiments: Set[Optional[str]] = {getattr(r, "experiment", None) for r in runs}

    if len(experiments) > 1:
        raise RuntimeError(
            f"source repo contains multiple experiments ({len(experiments)}): {sorted(experiments)}"
        )

    (experiment,) = tuple(experiments)
    return experiment, runs


def delete_dst_experiment_runs(dst: Repo, experiment: Optional[str]):
    dst_runs = list(dst.iter_runs())
    to_delete = [r.hash for r in dst_runs if getattr(r, "experiment", None) == experiment]

    print(f"[replay] dst runs to delete for experiment={experiment}: {len(to_delete)}")
    for h in to_delete:
        print(f"[replay] deleting dst run {h}")
        dst.delete_run(h)


def replay_src_run_to_new_dst_run(
        src: Repo,
        dst_repo_path: str,
        experiment: Optional[str],
        src_run_hash: str,
):
    print(f"[replay] creating new dst run for src_hash={src_run_hash} experiment={experiment}")

    # Create NEW run (new hash)
    dst_run = Run(repo=dst_repo_path, experiment=experiment)

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
            steps, columns = metric.data.numpy()   # steps: np.ndarray
            vals = columns[0]                      # 'val' column
            n = len(vals)
            if n == 0:
                continue

            context = ctx_to_dict(metric.context)
            print(f"[replay] metric={name} ctx={context} points={n}")

            for step, val in zip(steps, vals):
                dst_run.track(float(val), name=name, step=int(step), context=context)

            total_points += n

    print(f"[replay] replayed metrics={metric_count} total_points={total_points} for src_hash={src_run_hash}")
    dst_run.close()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="Source repo root (contains .aim), e.g. /tmp/aim")
    ap.add_argument("--dst", required=True, help="Destination repo root (central), e.g. /opt/aim")
    args = ap.parse_args()

    src = Repo(args.src)
    dst = Repo(args.dst)

    experiment, runs = single_experiment_and_runs(src)
    if not runs:
        print("[replay] no runs/experiments found in source")
        return 0

    print(f"[replay] source experiment: {experiment}")
    print(f"[replay] src runs in experiment: {len(runs)}")
    print("[replay] src hashes:", [r.hash for r in runs])

    delete_dst_experiment_runs(dst, experiment)

    for r in runs:
        replay_src_run_to_new_dst_run(
            src=src,
            dst_repo_path=args.dst,
            experiment=experiment,
            src_run_hash=r.hash,
        )

    print("[replay] done (single experiment replayed into dst)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as e:
        print(f"[replay] ERROR: {e}", file=sys.stderr)
        raise SystemExit(1)
