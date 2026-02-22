#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  echo "Run inside generated project root" >&2
  exit 1
fi

exec "$ROOT/.wfkit/scripts/pm/bootstrap_repo.sh" "$@"
