#!/usr/bin/env bash
set -euo pipefail

REPO=""
OUTPUT=""
RUN_LIMIT="20"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --run-limit) RUN_LIMIT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Usage: 07_collect_report.sh --repo <owner/name> [--output <path>] [--run-limit 20]" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "Run inside generated project root" >&2
  exit 1
fi

if [[ -z "$OUTPUT" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  OUTPUT="$ROOT/.wfkit/reports/release-report-${TS}.md"
fi
mkdir -p "$(dirname "$OUTPUT")"

ISSUES_TSV="$(gh issue list --repo "$REPO" --state all --limit 200 --json number,state,title,labels -q '.[] | [.number,.state,.title,([.labels[].name]|join(","))] | @tsv' || true)"
PRS_TSV="$(gh pr list --repo "$REPO" --state all --limit 200 --json number,state,mergedAt,title,headRefName -q '.[] | [.number,.state,.mergedAt,.headRefName,.title] | @tsv' || true)"
RUNS_TSV="$(gh run list --repo "$REPO" --limit "$RUN_LIMIT" --json databaseId,name,event,status,conclusion,headBranch -q '.[] | [.databaseId,.name,.event,.status,.conclusion,.headBranch] | @tsv' || true)"

{
  echo "# Release Report"
  echo
  echo "- generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- repo: https://github.com/${REPO}"
  echo
  echo "## Issues"
  echo "| # | State | Title | Labels |"
  echo "|---|---|---|---|"
  if [[ -n "$ISSUES_TSV" ]]; then
    while IFS=$'\t' read -r num state title labels; do
      safe_title="${title//|/\\|}"
      safe_labels="${labels//|/\\|}"
      echo "| ${num} | ${state} | ${safe_title} | ${safe_labels} |"
    done <<< "$ISSUES_TSV"
  else
    echo "| - | - | none | - |"
  fi
  echo
  echo "## Pull Requests"
  echo "| # | State | Merged At | Head Branch | Title |"
  echo "|---|---|---|---|---|"
  if [[ -n "$PRS_TSV" ]]; then
    while IFS=$'\t' read -r num state merged_at head title; do
      safe_title="${title//|/\\|}"
      echo "| ${num} | ${state} | ${merged_at} | ${head} | ${safe_title} |"
    done <<< "$PRS_TSV"
  else
    echo "| - | - | - | - | none |"
  fi
  echo
  echo "## Workflow Runs (latest ${RUN_LIMIT})"
  echo "| Run ID | Workflow | Event | Status | Conclusion | Branch |"
  echo "|---|---|---|---|---|---|"
  if [[ -n "$RUNS_TSV" ]]; then
    while IFS=$'\t' read -r run_id name event status conclusion branch; do
      echo "| ${run_id} | ${name} | ${event} | ${status} | ${conclusion} | ${branch} |"
    done <<< "$RUNS_TSV"
  else
    echo "| - | - | - | - | - | - |"
  fi
} > "$OUTPUT"

python3 - <<PY
import json
print(json.dumps({"ok": True, "repo": "${REPO}", "output": "${OUTPUT}"}, ensure_ascii=False))
PY
