#!/bin/bash

set -eo pipefail

cd /opt/densemax/sky
source .venv/bin/activate

CLUSTER="${JOB_ID}-cluster"
echo "Shutting down cluster"

MAX_WAIT_SEC="${MAX_WAIT_SEC:-300}"   # 5 min default
SLEEP_SEC="${SLEEP_SEC:-5}"

# If the cluster is not in SkyPilot state, there's nothing for sky down to do.
if ! sky status 2>/dev/null \
    | sed -r 's/\x1b\[[0-9;]*m//g' \
    | grep -qE "^[[:space:]]*${CLUSTER}([[:space:]]|$)"; then
  exit 0
fi

deadline=$(( $(date +%s) + MAX_WAIT_SEC ))

# Cluster exists in state: wait until it leaves INIT.
while true; do
    status="$(
      sky status 2>/dev/null \
        | sed -r 's/\x1b\[[0-9;]*m//g' \
        | grep -E "^[[:space:]]*${CLUSTER}[[:space:]]" \
        | head -n1 \
        | grep -oE '\b(INIT|UP|STOPPED)\b' \
        | head -n1
    )"

  # If it disappears while we're waiting, treat as success.
  if [[ -z "${status:-}" ]]; then
    exit 0
  fi

  if [[ "$status" != "INIT" ]]; then
    break
  fi

  if (( $(date +%s) >= deadline )); then
    echo "Cluster '$CLUSTER' stayed in INIT too long; skipping sky down." >&2
    exit 0
  fi

  sleep "$SLEEP_SEC"
done

echo "Leaving INIT; about to run: sky down $CLUSTER"
set +e
out="$(sky down -y "$CLUSTER" 2>&1)"
rc=$?
set -e
echo "$out"
echo "sky down exit code: $rc"
exit $rc
