#!/usr/bin/env python3
"""Create a structured task issue with YAML frontmatter."""

from __future__ import annotations

import argparse
import json
from typing import Any

from common import gh_api, render_frontmatter

TASK_TYPES = {
    "REQ",
    "DESIGN",
    "SPLIT",
    "TEST_PLAN",
    "IMPL",
    "DEBUG",
    "REVIEW",
    "INTEGRATION",
}

STATUSES = {"ready", "in_progress", "blocked", "done"}


def _split_csv(raw: str) -> list[str]:
    return [x.strip() for x in raw.split(",") if x.strip()]


def _dedupe_keep_order(items: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        if item not in seen:
            out.append(item)
            seen.add(item)
    return out


def _expect_issue(data: Any) -> dict[str, Any]:
    if not isinstance(data, dict) or "number" not in data:
        raise RuntimeError("unexpected GitHub issue create response")
    return data


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--task-id", required=True, help="e.g. TASK-001")
    parser.add_argument("--task-type", required=True, choices=sorted(TASK_TYPES))
    parser.add_argument("--title", required=True, help="Issue title")
    parser.add_argument("--status", default="ready", choices=sorted(STATUSES))
    parser.add_argument("--depends-on", default="", help="Comma-separated task ids, e.g. TASK-001,TASK-002")
    parser.add_argument("--owner-worker", default="", help="worker-a|worker-b or empty")
    parser.add_argument("--acceptance", action="append", required=True, help="Repeatable. At least one acceptance criterion.")
    parser.add_argument("--body", default="Implement according to acceptance criteria.")
    parser.add_argument("--label", action="append", default=[], help="Extra labels (repeatable)")
    args = parser.parse_args()

    depends_on = _split_csv(args.depends_on)
    acceptance = [x.strip() for x in args.acceptance if x.strip()]
    if not acceptance:
        raise SystemExit("at least one --acceptance is required")

    meta = {
        "task_id": args.task_id.strip(),
        "task_type": args.task_type.strip(),
        "status": args.status.strip(),
        "depends_on": depends_on,
        "owner_worker": args.owner_worker.strip(),
        "acceptance": acceptance,
    }

    issue_body = render_frontmatter(meta, args.body)
    labels = _dedupe_keep_order(["type/task", f"status/{args.status}"] + [x.strip() for x in args.label if x.strip()])

    issue = _expect_issue(
        gh_api(
            f"repos/{args.repo}/issues",
            method="POST",
            payload={
                "title": args.title,
                "body": issue_body,
                "labels": labels,
            },
        )
    )
    number = int(issue["number"])
    url = str(issue.get("html_url") or f"https://github.com/{args.repo}/issues/{number}")
    print(json.dumps({"ok": True, "repo": args.repo, "issue": number, "url": url, "task_id": args.task_id}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
