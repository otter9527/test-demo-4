#!/usr/bin/env bash
set -euo pipefail

REPO=""
ISSUE=""
WORKER=""
AI_MODE="mock"
BASE_BRANCH="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --worker) WORKER="$2"; shift 2 ;;
    --ai-mode) AI_MODE="$2"; shift 2 ;;
    --base-branch) BASE_BRANCH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" || -z "$ISSUE" || -z "$WORKER" ]]; then
  echo "Usage: run_task.sh --repo <owner/name> --issue <num> --worker <worker-a|worker-b> [--ai-mode mock|real|codex] [--base-branch main]" >&2
  exit 1
fi

if [[ "$AI_MODE" != "mock" && "$AI_MODE" != "real" && "$AI_MODE" != "codex" ]]; then
  echo "Invalid --ai-mode: ${AI_MODE}. Allowed: mock|real|codex" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "Must run inside a git repo" >&2
  exit 1
fi
cd "$ROOT"

ISSUE_JSON="$(gh api "repos/${REPO}/issues/${ISSUE}")"
export ISSUE_JSON
TASK_META_JSON="$(python3 - <<'PY'
import json
import os
import re

import yaml

issue = json.loads(os.environ["ISSUE_JSON"])
body = issue.get("body") or ""
lines = body.splitlines()
meta = {}
if len(lines) >= 3 and lines[0].strip() == "---":
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is not None:
        raw = "\n".join(lines[1:end])
        val = yaml.safe_load(raw) or {}
        if isinstance(val, dict):
            meta = val

task_id = str(meta.get("task_id") or "").strip()
task_type = str(meta.get("task_type") or "").strip()
status = str(meta.get("status") or "").strip()
if not task_id:
    raise SystemExit("task_id missing in issue frontmatter")
m = re.search(r"(\d+)", task_id)
if not m:
    raise SystemExit(f"invalid task_id: {task_id}")
marker = f"task_{int(m.group(1)):03d}"
print(
    json.dumps(
        {
            "task_id": task_id,
            "task_type": task_type,
            "status": status,
            "marker": marker,
            "title": issue.get("title", ""),
        }
    )
)
PY
)"

export TASK_META_JSON
TASK_ID="$(python3 - <<'PY'
import json
import os
print(json.loads(os.environ["TASK_META_JSON"])["task_id"])
PY
)"
TASK_TYPE="$(python3 - <<'PY'
import json
import os
print(json.loads(os.environ["TASK_META_JSON"])["task_type"])
PY
)"
TASK_STATUS="$(python3 - <<'PY'
import json
import os
print(json.loads(os.environ["TASK_META_JSON"])["status"])
PY
)"
MARKER="$(python3 - <<'PY'
import json
import os
print(json.loads(os.environ["TASK_META_JSON"])["marker"])
PY
)"
ISSUE_TITLE="$(python3 - <<'PY'
import json
import os
print(json.loads(os.environ["TASK_META_JSON"])["title"])
PY
)"

if [[ "$TASK_STATUS" != "in_progress" && "$TASK_STATUS" != "ready" ]]; then
  echo "Issue #${ISSUE} status is '${TASK_STATUS}', expected in_progress/ready before submission" >&2
fi

BRANCH_SUFFIX="$(echo "$TASK_ID" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
BRANCH="worker/${WORKER}/task-${BRANCH_SUFFIX}"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Working tree has uncommitted changes on '${CURRENT_BRANCH}'. Commit/stash before switching to '${BRANCH}'." >&2
    exit 1
  fi
  git fetch origin "$BASE_BRANCH"
  git checkout "$BASE_BRANCH"
  git pull --ff-only origin "$BASE_BRANCH"
  git checkout -B "$BRANCH" "origin/${BASE_BRANCH}"
fi

AI_RESULT="$(python3 .wfkit/scripts/worker/ai_adapter.py --mode "$AI_MODE" --task-id "$TASK_ID" --task-type "$TASK_TYPE" --issue "$ISSUE" --summary "$ISSUE_TITLE")"
export AI_RESULT
AI_NOTE="$(python3 - <<'PY'
import json
import os
print(json.loads(os.environ["AI_RESULT"]).get("note", ""))
PY
)"

if [[ -x "$ROOT/.wfkit/scripts/ci/run_local_checks.sh" ]]; then
  bash "$ROOT/.wfkit/scripts/ci/run_local_checks.sh"
else
  echo "No local checks script found at .wfkit/scripts/ci/run_local_checks.sh; skipping."
fi

git config user.name "$WORKER"
git config user.email "${WORKER}@local.invalid"
git add -A
if git diff --cached --quiet; then
  echo "No staged changes detected. Implement task changes before running submit." >&2
  exit 1
fi

git commit -m "feat(${TASK_ID}): update by ${WORKER} [${AI_MODE}]"
git push -u origin "$BRANCH"

PR_NUMBER="$(gh pr list --repo "$REPO" --head "$BRANCH" --json number -q '.[0].number // empty')"
PR_BODY=$(cat <<PRBODY
## Summary
- Worker ${WORKER} submitted updates for ${TASK_ID} (${TASK_TYPE})

## Task Link
Closes #${ISSUE}

## Checks
- [x] \`bash .wfkit/scripts/ci/run_local_checks.sh\`

## AI
- mode: ${AI_MODE}
- note: ${AI_NOTE}
PRBODY
)

if [[ -z "$PR_NUMBER" ]]; then
  gh pr create --repo "$REPO" --head "$BRANCH" --base "$BASE_BRANCH" --title "feat: ${TASK_ID} by ${WORKER}" --body "$PR_BODY" >/dev/null
  PR_NUMBER="$(gh pr list --repo "$REPO" --head "$BRANCH" --json number -q '.[0].number // empty')"
  if [[ -z "$PR_NUMBER" ]]; then
    echo "Failed to resolve PR number after creation for branch ${BRANCH}" >&2
    exit 1
  fi
  PR_URL="https://github.com/${REPO}/pull/${PR_NUMBER}"
else
  gh pr edit "$PR_NUMBER" --repo "$REPO" --title "feat: ${TASK_ID} by ${WORKER}" --body "$PR_BODY" >/dev/null
  PR_URL="https://github.com/${REPO}/pull/${PR_NUMBER}"
fi

python3 - <<PY
import json

payload = {
    "ok": True,
    "repo": "${REPO}",
    "issue": int("${ISSUE}"),
    "task_id": "${TASK_ID}",
    "worker": "${WORKER}",
    "ai_mode": "${AI_MODE}",
    "marker": "${MARKER}",
    "branch": "${BRANCH}",
    "pr_number": int("${PR_NUMBER}"),
    "pr_url": "${PR_URL}",
}
print(json.dumps(payload, ensure_ascii=False))
PY
