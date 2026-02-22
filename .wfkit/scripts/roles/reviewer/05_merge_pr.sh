#!/usr/bin/env bash
set -euo pipefail

REPO=""
PR=""
MERGE_METHOD="squash"
WAIT_CHECKS="true"
TIMEOUT_SEC="1800"
POLL_SEC="10"
DELETE_BRANCH="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --pr) PR="$2"; shift 2 ;;
    --merge-method) MERGE_METHOD="$2"; shift 2 ;;
    --wait-checks) WAIT_CHECKS="$2"; shift 2 ;;
    --timeout-sec) TIMEOUT_SEC="$2"; shift 2 ;;
    --poll-sec) POLL_SEC="$2"; shift 2 ;;
    --delete-branch) DELETE_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" || -z "$PR" ]]; then
  echo "Usage: 05_merge_pr.sh --repo <owner/name> --pr <number> [--merge-method squash|merge|rebase] [--wait-checks true|false] [--timeout-sec 1800] [--poll-sec 10] [--delete-branch true|false]" >&2
  exit 1
fi

if [[ "$MERGE_METHOD" != "squash" && "$MERGE_METHOD" != "merge" && "$MERGE_METHOD" != "rebase" ]]; then
  echo "Invalid --merge-method: $MERGE_METHOD" >&2
  exit 1
fi

if [[ "$WAIT_CHECKS" != "true" && "$WAIT_CHECKS" != "false" ]]; then
  echo "Invalid --wait-checks: $WAIT_CHECKS" >&2
  exit 1
fi

if [[ "$DELETE_BRANCH" != "true" && "$DELETE_BRANCH" != "false" ]]; then
  echo "Invalid --delete-branch: $DELETE_BRANCH" >&2
  exit 1
fi

wait_for_checks() {
  local repo="$1"
  local pr="$2"
  local timeout="$3"
  local poll="$4"

  local sha
  sha="$(gh pr view "$pr" --repo "$repo" --json headRefOid -q '.headRefOid')"
  local started
  started="$(date +%s)"

  while true; do
    export CHECKS_JSON
    CHECKS_JSON="$(gh api "repos/${repo}/commits/${sha}/check-runs" 2>/dev/null || true)"

    read -r total pending failed <<<"$(python3 - <<'PY'
import json
import os

raw = os.environ.get("CHECKS_JSON", "")
if not raw.strip():
    print("0 0 0")
    raise SystemExit(0)
obj = json.loads(raw)
runs = obj.get("check_runs", [])
total = len(runs)
pending = 0
failed = 0
ok_conclusions = {"success", "neutral", "skipped"}
for run in runs:
    status = str(run.get("status") or "")
    conclusion = str(run.get("conclusion") or "")
    if status != "completed":
        pending += 1
    elif conclusion not in ok_conclusions:
        failed += 1
print(f"{total} {pending} {failed}")
PY
)"

    if [[ "$total" -gt 0 && "$pending" -eq 0 ]]; then
      if [[ "$failed" -gt 0 ]]; then
        gh pr checks "$pr" --repo "$repo" || true
        echo "Checks failed for PR #$pr" >&2
        return 1
      fi
      return 0
    fi

    local now
    now="$(date +%s)"
    if (( now - started > timeout )); then
      gh pr checks "$pr" --repo "$repo" || true
      echo "Timed out waiting checks for PR #$pr" >&2
      return 1
    fi
    sleep "$poll"
  done
}

if [[ "$WAIT_CHECKS" == "true" ]]; then
  wait_for_checks "$REPO" "$PR" "$TIMEOUT_SEC" "$POLL_SEC"
fi

MERGE_FLAG="--squash"
if [[ "$MERGE_METHOD" == "merge" ]]; then
  MERGE_FLAG="--merge"
elif [[ "$MERGE_METHOD" == "rebase" ]]; then
  MERGE_FLAG="--rebase"
fi

if [[ "$DELETE_BRANCH" == "true" ]]; then
  gh pr merge "$PR" --repo "$REPO" "$MERGE_FLAG" --delete-branch
else
  gh pr merge "$PR" --repo "$REPO" "$MERGE_FLAG"
fi

MERGED_AT="$(gh pr view "$PR" --repo "$REPO" --json mergedAt -q '.mergedAt // ""')"
if [[ -z "$MERGED_AT" ]]; then
  echo "PR #$PR is not merged" >&2
  exit 1
fi

python3 - <<PY
import json
print(json.dumps({"ok": True, "repo": "${REPO}", "pr": int("${PR}"), "merge_method": "${MERGE_METHOD}", "merged_at": "${MERGED_AT}"}, ensure_ascii=False))
PY
