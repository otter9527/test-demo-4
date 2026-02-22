#!/usr/bin/env bash
set -euo pipefail

REPO=""
WORKER=""
STATUS="in_progress"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --worker) WORKER="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" || -z "$WORKER" ]]; then
  echo "Usage: 03_inbox.sh --repo <owner/name> --worker <worker-a|worker-b> [--status in_progress|ready|all]" >&2
  exit 1
fi

if [[ "$STATUS" != "in_progress" && "$STATUS" != "ready" && "$STATUS" != "all" ]]; then
  echo "Invalid --status: ${STATUS}" >&2
  exit 1
fi

ISSUES_JSON="$(gh api "repos/${REPO}/issues?state=open&labels=type/task&per_page=100")"
export ISSUES_JSON STATUS WORKER

python3 - <<'PY'
import json
import os
import re

issues = json.loads(os.environ.get("ISSUES_JSON", "[]"))
status_filter = os.environ.get("STATUS", "in_progress")
worker = os.environ.get("WORKER", "")
if not isinstance(issues, list):
    issues = []

def parse_meta(body: str) -> dict:
    text = body or ""
    lines = text.splitlines()
    out = {}
    if len(lines) >= 3 and lines[0].strip() == "---":
        for line in lines[1:]:
            if line.strip() == "---":
                break
            m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line.strip())
            if not m:
                continue
            out[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return out

items = []
for issue in issues:
    if not isinstance(issue, dict) or "pull_request" in issue:
        continue
    meta = parse_meta(str(issue.get("body") or ""))
    status = str(meta.get("status", ""))
    owner_worker = str(meta.get("owner_worker", ""))
    if status_filter != "all" and status != status_filter:
        continue
    if owner_worker and owner_worker != worker:
        continue
    items.append(
        {
            "issue": issue.get("number"),
            "title": issue.get("title"),
            "task_id": meta.get("task_id", ""),
            "task_type": meta.get("task_type", ""),
            "status": status,
            "owner_worker": owner_worker,
            "url": issue.get("html_url"),
            "updated_at": issue.get("updated_at"),
        }
    )

items.sort(key=lambda x: (x.get("updated_at") or "", x.get("issue") or 0))
print(json.dumps({"ok": True, "worker": worker, "status": status_filter, "items": items}, ensure_ascii=False))
PY
