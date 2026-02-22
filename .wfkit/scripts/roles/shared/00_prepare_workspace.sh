#!/usr/bin/env bash
set -euo pipefail

REPO=""
WORKSPACE_ROOT="${HOME}/ai-factory-workspaces"
BRANCH="main"
INSTALL_DEPS="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --workspace-root) WORKSPACE_ROOT="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --install-deps) INSTALL_DEPS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Usage: 00_prepare_workspace.sh --repo <owner/name> [--workspace-root <dir>] [--branch main] [--install-deps true|false]" >&2
  exit 1
fi

if [[ "$INSTALL_DEPS" != "true" && "$INSTALL_DEPS" != "false" ]]; then
  echo "Invalid --install-deps: ${INSTALL_DEPS}" >&2
  exit 1
fi

TARGET="${WORKSPACE_ROOT}/$(basename "$REPO")"
mkdir -p "$WORKSPACE_ROOT"

if [[ -d "${TARGET}/.git" ]]; then
  git -C "$TARGET" fetch origin "$BRANCH"
  git -C "$TARGET" checkout "$BRANCH"
  git -C "$TARGET" pull --ff-only origin "$BRANCH"
else
  git clone "https://github.com/${REPO}.git" "$TARGET"
  git -C "$TARGET" checkout "$BRANCH"
fi

if [[ "$INSTALL_DEPS" == "true" && -f "${TARGET}/.wfkit/requirements.txt" ]]; then
  python3 -m pip install -q -r "${TARGET}/.wfkit/requirements.txt"
fi

HEAD_SHA="$(git -C "$TARGET" rev-parse HEAD)"

python3 - <<PY
import json
print(json.dumps({"ok": True, "repo": "${REPO}", "workspace": "${TARGET}", "branch": "${BRANCH}", "head": "${HEAD_SHA}"}, ensure_ascii=False))
PY
