#!/usr/bin/env python3
"""
Copy Aim runs from a source repo to a destination repo without re-tracking metrics.
- Copies only runs (by hash) that do not exist in the destination repo yet.
- Safe to call repeatedly (idempotent-ish).

Usage:
  ./aim_copy_runs.py --src ./aim_tmp --dst /srv/aim-repo
"""

import argparse
import sys
from aim import Repo


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="Source Aim repo path (rsynced temp)")
    ap.add_argument("--dst", required=True, help="Destination Aim repo path (central repo)")
    args = ap.parse_args()

    src = Repo(args.src)
    dst = Repo(args.dst)

    src_hashes = [run.hash for run in src.iter_runs()]

    to_copy = []
    for h in src_hashes:
        try:
            r = dst.get_run(h)
        except Exception:
            r = None
        if r is None:
            to_copy.append(h)

    if to_copy:
        src.copy_runs(to_copy, dst)
        print(f"[aim-copy] copied {len(to_copy)} new run(s) from {args.src} -> {args.dst}")
    else:
        print("[aim-copy] nothing new to copy")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as e:
        print(f"[aim-copy] error: {e}", file=sys.stderr)
        raise SystemExit(1)
