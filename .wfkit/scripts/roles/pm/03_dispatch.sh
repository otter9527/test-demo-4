#!/usr/bin/env bash
set -euo pipefail

REPO=""
RUN_ID="$(date +%Y%m%d-%H%M%S)"
EVENT="manual_dispatch"
ASSIGN_SELF="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --event) EVENT="$2"; shift 2 ;;
    --assign-self) ASSIGN_SELF="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Usage: 03_dispatch.sh --repo <owner/name> [--run-id <id>] [--event <name>] [--assign-self true|false]" >&2
  exit 1
fi

if [[ "$ASSIGN_SELF" != "true" && "$ASSIGN_SELF" != "false" ]]; then
  echo "Invalid --assign-self: $ASSIGN_SELF (true|false)" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "Run inside generated project root" >&2
  exit 1
fi
cd "$ROOT"

python3 .wfkit/scripts/pm/sync_state.py --repo "$REPO" --run-id "$RUN_ID" --event "$EVENT"
if [[ "$ASSIGN_SELF" == "true" ]]; then
  python3 .wfkit/scripts/pm/dispatch_tasks.py --repo "$REPO" --run-id "$RUN_ID" --assign-self
else
  python3 .wfkit/scripts/pm/dispatch_tasks.py --repo "$REPO" --run-id "$RUN_ID"
fi
