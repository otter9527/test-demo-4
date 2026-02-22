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
  echo "Usage: 04_queue.sh --repo <owner/name>" >&2
  exit 1
fi

PRS_JSON="$(gh pr list --repo "$REPO" --state open --json number,title,headRefName,baseRefName,author,url,updatedAt)"
export PRS_JSON

python3 - <<'PY'
import json
import os

prs = json.loads(os.environ.get("PRS_JSON", "[]"))
if not isinstance(prs, list):
    prs = []

items = []
for pr in prs:
    if not isinstance(pr, dict):
        continue
    author = pr.get("author") if isinstance(pr.get("author"), dict) else {}
    items.append(
        {
            "pr": pr.get("number"),
            "title": pr.get("title"),
            "head": pr.get("headRefName"),
            "base": pr.get("baseRefName"),
            "author": author.get("login"),
            "url": pr.get("url"),
            "updated_at": pr.get("updatedAt"),
        }
    )

items.sort(key=lambda x: (x.get("updated_at") or "", x.get("pr") or 0))
print(json.dumps({"ok": True, "open_prs": items}, ensure_ascii=False))
PY
