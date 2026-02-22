#!/usr/bin/env bash
set -euo pipefail

REPO=""
PR=""
RUN_ID="$(date +%Y%m%d-%H%M%S)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" || -z "$PR" ]]; then
  echo "Usage: 06_post_merge.sh --repo <owner/name> --pr <number> [--run-id <id>]" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "Run inside generated project root" >&2
  exit 1
fi
cd "$ROOT"

python3 .wfkit/scripts/pm/on_pr_merged.py --repo "$REPO" --pr "$PR" --run-id "$RUN_ID"
