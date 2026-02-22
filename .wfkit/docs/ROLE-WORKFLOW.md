# Role Workflow

This project is split into explicit role scripts so each person runs only their stage.
Assumption is always distributed: each role may run on different host/network.
No shared filesystem is required; only GitHub repo/issue/PR/workflow is shared.

## Role Mapping
- `A` Owner/Admin: repository setup and policy.
- `B` PM: task creation, dispatch, and post-merge progression.
- `C` Worker: implement task and create PR.
- `D` Reviewer: verify checks and merge PR.
- `E` Release/QA: collect project snapshot report.

## Step-by-Step
0. Each role prepares local workspace independently.
```bash
bash .wfkit/scripts/roles/shared/00_prepare_workspace.sh \
  --repo <owner/name> \
  --workspace-root "$HOME/ai-factory-workspaces" \
  --branch main \
  --install-deps true
```

1. `A` initialize repository and gatekeeping.
```bash
bash .wfkit/scripts/roles/owner/01_setup_repo.sh \
  --repo <owner/name> \
  --visibility public \
  --default-branch main \
  --strict-mode true
```

2. `B` create one or more structured task issues.
```bash
bash .wfkit/scripts/roles/pm/02_create_task.sh \
  --repo <owner/name> \
  --task-id TASK-001 \
  --task-type IMPL \
  --title "Task 001: <title>" \
  --acceptance "definition of done"

bash .wfkit/scripts/roles/pm/02_create_task.sh \
  --repo <owner/name> \
  --task-id TASK-002 \
  --task-type IMPL \
  --title "Task 002: <title>" \
  --depends-on TASK-001 \
  --acceptance "definition of done"
```

3. `B` run dispatch to assign ready tasks.
```bash
bash .wfkit/scripts/roles/pm/03_dispatch.sh --repo <owner/name> --event manual_dispatch --assign-self false
```

4. `C` check inbox and execute assigned issue.
```bash
bash .wfkit/scripts/roles/worker/03_inbox.sh --repo <owner/name> --worker worker-a --status in_progress
```

Worker applies code changes locally first, then submits with unified checks + PR flow:
```bash
bash .wfkit/scripts/roles/worker/04_run_task.sh \
  --repo <owner/name> \
  --issue <issue_number> \
  --worker worker-a \
  --ai-mode codex
```

5. `D` check review queue and merge PR only after checks are green.
```bash
bash .wfkit/scripts/roles/reviewer/04_queue.sh --repo <owner/name>
```

```bash
bash .wfkit/scripts/roles/reviewer/05_merge_pr.sh \
  --repo <owner/name> \
  --pr <pr_number> \
  --merge-method squash \
  --wait-checks true \
  --delete-branch true
```

6. `B` run post-merge progression (close issue, unlock downstream, redispatch).
```bash
bash .wfkit/scripts/roles/pm/06_post_merge.sh --repo <owner/name> --pr <pr_number>
```

7. Repeat steps 3-6 until task chain completes.

8. `E` generate release/operation snapshot report.
```bash
bash .wfkit/scripts/roles/release/07_collect_report.sh --repo <owner/name>
```

## Parameter Notes
- `--repo`: GitHub repository in `owner/name`.
- `--task-type`: `REQ|DESIGN|SPLIT|TEST_PLAN|IMPL|DEBUG|REVIEW|INTEGRATION`.
- `--depends-on`: comma-separated task ids (e.g. `TASK-001,TASK-002`).
- `--ai-mode`: `mock|real|codex`.
- `--wait-checks`: reviewer waits for all checks to finish and pass.
- `--assign-self`: in distributed mode usually `false` to avoid PM node as assignee.

## CI and Checks
- Required checks are configured in `.wfkit/config/policy.yaml`.
- Default required checks:
  - `policy-check`
  - `repo-checks`
- Baseline check entry:
  - `.wfkit/scripts/ci/run_repo_checks.sh`
- Project-specific checks:
  - copy `.wfkit/scripts/ci/project_checks.sh.example` to `.wfkit/scripts/ci/project_checks.sh`.

## Handoff Contract (GitHub-Only)
- `PM -> Worker`: issue number (`#N`) + expected worker id.
- `Worker -> Reviewer`: PR number (`#M`) from worker script JSON output.
- `Reviewer -> PM`: merged PR number (`#M`) for post-merge progression.
- `PM -> Release`: repository + release point in `main`.
