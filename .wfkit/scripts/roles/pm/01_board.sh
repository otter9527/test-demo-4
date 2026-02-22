#!/usr/bin/env bash
set -euo pipefail

REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Usage: 01_board.sh --repo <owner/name>" >&2
  exit 1
fi

ISSUES_JSON="$(gh api "repos/${REPO}/issues?state=open&labels=type/task&per_page=100")"
export ISSUES_JSON

python3 - <<'PY'
import json
import os
import re

issues = json.loads(os.environ.get("ISSUES_JSON", "[]"))
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

tasks = []
for issue in issues:
    if not isinstance(issue, dict) or "pull_request" in issue:
        continue
    meta = parse_meta(str(issue.get("body") or ""))
    tasks.append(
        {
            "issue": issue.get("number"),
            "title": issue.get("title"),
            "task_id": meta.get("task_id", ""),
            "task_type": meta.get("task_type", ""),
            "status": meta.get("status", ""),
            "owner_worker": meta.get("owner_worker", ""),
            "url": issue.get("html_url"),
        }
    )

summary = {"ready": 0, "in_progress": 0, "blocked": 0, "other": 0}
for t in tasks:
    status = str(t.get("status") or "")
    if status in summary:
        summary[status] += 1
    else:
        summary["other"] += 1

print(json.dumps({"ok": True, "summary": summary, "tasks": tasks}, ensure_ascii=False))
PY
