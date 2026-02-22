#!/usr/bin/env bash
set -euo pipefail

REPO=""
VISIBILITY="private"
DEFAULT_BRANCH="main"
STRICT_MODE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --visibility) VISIBILITY="$2"; shift 2 ;;
    --default-branch) DEFAULT_BRANCH="$2"; shift 2 ;;
    --strict-mode) STRICT_MODE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Usage: bootstrap_repo.sh --repo <owner/name> [--visibility private|public] [--default-branch main] [--strict-mode true|false]" >&2
  exit 1
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "Run inside repo root" >&2
  exit 1
fi
cd "$ROOT"

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  git add .
  git commit -m "chore: initial mvp scaffold"
fi

git branch -M "$DEFAULT_BRANCH"

if gh repo view "$REPO" >/dev/null 2>&1; then
  :
else
  gh repo create "$REPO" "--${VISIBILITY}" --disable-wiki --description "AI Factory MVP E2E flow"
fi

# Ensure task workflow can use GitHub Issues APIs.
gh api -X PATCH "repos/${REPO}" -f has_issues=true >/dev/null

REMOTE_URL="https://github.com/${REPO}.git"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

git push -u origin "$DEFAULT_BRANCH"

# labels
gh label create "type/task" --repo "$REPO" --color "0E8A16" --description "Task issues" --force
gh label create "status/ready" --repo "$REPO" --color "1D76DB" --description "Ready for dispatch" --force
gh label create "status/in_progress" --repo "$REPO" --color "FBCA04" --description "Task in progress" --force
gh label create "status/done" --repo "$REPO" --color "0E8A16" --description "Task done" --force
gh label create "status/blocked" --repo "$REPO" --color "B60205" --description "Task blocked" --force
gh label create "worker/a" --repo "$REPO" --color "5319E7" --description "Assigned to worker-a" --force
gh label create "worker/b" --repo "$REPO" --color "5319E7" --description "Assigned to worker-b" --force

REQUIRED_CHECKS_JSON="$(python3 - <<'PY'
import json
from pathlib import Path

path = Path(".wfkit/config/policy.yaml")
default = ["policy-check", "repo-checks"]
if not path.exists():
    print(json.dumps(default))
    raise SystemExit(0)

lines = path.read_text(encoding="utf-8").splitlines()
checks: list[str] = []
in_block = False
for raw in lines:
    line = raw.rstrip()
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        continue
    if not in_block:
        if stripped == "required_checks:":
            in_block = True
        continue
    if line.startswith("  - "):
        val = line.split("-", 1)[1].strip().strip('"').strip("'")
        if val:
            checks.append(val)
        continue
    if not line.startswith(" "):
        break

clean = [str(x).strip() for x in checks if str(x).strip()]
if not clean:
    clean = default
print(json.dumps(clean))
PY
)"

if [[ "$STRICT_MODE" == "true" ]]; then
  PROTECTION_JSON="$(python3 - <<PY
import json

checks = json.loads('''${REQUIRED_CHECKS_JSON}''')
payload = {
    "required_status_checks": {
        "strict": True,
        "contexts": checks,
    },
    "enforce_admins": True,
    "required_pull_request_reviews": None,
    "restrictions": None,
    "required_linear_history": False,
    "allow_force_pushes": False,
    "allow_deletions": False,
    "block_creations": False,
    "required_conversation_resolution": False,
    "lock_branch": False,
    "allow_fork_syncing": True,
}
print(json.dumps(payload))
PY
)"
  gh api -X PUT "repos/${REPO}/branches/${DEFAULT_BRANCH}/protection" --input - <<JSON
${PROTECTION_JSON}
JSON
fi

python3 - <<PY
import json
strict_mode = "${STRICT_MODE}".strip().lower() == "true"
required_checks = json.loads('''${REQUIRED_CHECKS_JSON}''')
print(json.dumps({"ok": True, "repo": "${REPO}", "default_branch": "${DEFAULT_BRANCH}", "strict_mode": strict_mode, "required_checks": required_checks}, ensure_ascii=False))
PY
