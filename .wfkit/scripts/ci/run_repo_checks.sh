#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "run_repo_checks.sh must run inside a git repository" >&2
  exit 1
fi
cd "$ROOT"

echo "[repo-checks] scanning unresolved merge conflict markers"
if git grep -nE '^(<<<<<<< .+|=======$|>>>>>>> .+)$' -- . ':!*.lock' ':!*.svg'; then
  echo "[repo-checks] found unresolved merge conflict markers" >&2
  exit 1
fi

if [[ -x "$ROOT/.wfkit/scripts/ci/project_checks.sh" ]]; then
  echo "[repo-checks] running project-specific checks: .wfkit/scripts/ci/project_checks.sh"
  "$ROOT/.wfkit/scripts/ci/project_checks.sh"
else
  echo "[repo-checks] no project-specific checks found, baseline checks only"
fi

echo "[repo-checks] completed"
