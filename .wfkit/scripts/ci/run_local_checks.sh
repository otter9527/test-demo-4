#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "run_local_checks.sh must run inside a git repository" >&2
  exit 1
fi
cd "$ROOT"

exec "$ROOT/.wfkit/scripts/ci/run_repo_checks.sh"
