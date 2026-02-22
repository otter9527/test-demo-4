#!/usr/bin/env python3
"""AI adapter with mock and optional real API mode."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def _extract_output_text(resp: dict[str, Any]) -> str:
    if isinstance(resp.get("output_text"), str) and resp["output_text"].strip():
        return str(resp["output_text"]).strip()
    output = resp.get("output")
    if isinstance(output, list):
        chunks: list[str] = []
        for item in output:
            if not isinstance(item, dict):
                continue
            content = item.get("content")
            if not isinstance(content, list):
                continue
            for c in content:
                if isinstance(c, dict) and isinstance(c.get("text"), str):
                    chunks.append(c["text"])
        if chunks:
            return "\n".join(chunks).strip()
    return ""


def _mock_note(task_id: str, task_type: str) -> str:
    return f"Mock planner executed for {task_id} ({task_type}). Apply deterministic implementation." 


def _real_note(task_id: str, task_type: str) -> tuple[str, bool, str]:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        return (
            "OPENAI_API_KEY missing; fallback to deterministic local plan.",
            True,
            "no_api_key",
        )

    base_url = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
    endpoint = f"{base_url}/responses"

    payload = {
        "model": model,
        "input": (
            "You are helping with CI-safe coding task generation. "
            f"Task: {task_id} ({task_type}). "
            "Return one concise implementation hint in <= 30 words."
        ),
    }

    req = urllib.request.Request(
        endpoint,
        method="POST",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            body = res.read().decode("utf-8")
        parsed = json.loads(body)
        note = _extract_output_text(parsed)
        if note:
            return note, False, "ok"
        return "Real API call returned empty content; fallback deterministic.", True, "empty_output"
    except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as exc:
        return f"Real API call failed: {exc}; fallback deterministic.", True, "api_error"


def _codex_note(task_id: str, task_type: str, issue: str, summary: str) -> tuple[str, bool, str]:
    prompt = (
        "You are a software engineer assistant. "
        "Given the task context, return one concise implementation hint in <= 30 words. "
        f"task_id={task_id}; task_type={task_type}; issue={issue}; summary={summary}"
    )
    with tempfile.NamedTemporaryFile(prefix="codex-note-", suffix=".txt", delete=False) as tmp:
        output_file = tmp.name

    argv = [
        "codex",
        "exec",
        "--skip-git-repo-check",
        "--sandbox",
        "read-only",
        "--output-last-message",
        output_file,
        prompt,
    ]

    model = os.getenv("CODEX_MODEL", "").strip()
    if model:
        argv.extend(["--model", model])

    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=120, check=False)
        text = Path(output_file).read_text(encoding="utf-8").strip() if Path(output_file).exists() else ""
        if proc.returncode != 0:
            msg = proc.stderr.strip() or proc.stdout.strip() or "codex_exec_failed"
            return f"Codex CLI failed: {msg}; fallback deterministic.", True, "codex_error"
        if not text:
            return "Codex CLI returned empty output; fallback deterministic.", True, "codex_empty"
        return text, False, "ok"
    except (subprocess.TimeoutExpired, OSError) as exc:
        return f"Codex CLI execution failed: {exc}; fallback deterministic.", True, "codex_error"
    finally:
        try:
            Path(output_file).unlink(missing_ok=True)
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["mock", "real", "codex"], required=True)
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--task-type", required=True)
    parser.add_argument("--issue", required=True)
    parser.add_argument("--summary", default="")
    args = parser.parse_args()

    if args.mode == "mock":
        payload = {
            "ok": True,
            "mode": "mock",
            "task_id": args.task_id,
            "task_type": args.task_type,
            "issue": args.issue,
            "used_fallback": False,
            "reason": "mock",
            "note": _mock_note(args.task_id, args.task_type),
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    if args.mode == "real":
        note, used_fallback, reason = _real_note(args.task_id, args.task_type)
    else:
        note, used_fallback, reason = _codex_note(args.task_id, args.task_type, args.issue, args.summary)
    payload = {
        "ok": True,
        "mode": args.mode,
        "task_id": args.task_id,
        "task_type": args.task_type,
        "issue": args.issue,
        "used_fallback": used_fallback,
        "reason": reason,
        "note": note,
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
