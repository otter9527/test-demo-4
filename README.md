# test-demo-4

Low-intrusion GitHub workflow-control project generated from `workflow-control-kit`.

## Initial Requirement
- Issue -> PR -> Review -> Merge workflow

## What This Repository Provides
- strict branch protection and required checks on `main`
- structured issue -> dispatch -> PR -> merge -> post-merge progression
- role-based scripts for distributed teams (Owner/PM/Worker/Reviewer/Release)
- GitHub-driven coordination (no shared filesystem required)
- workflow internals are isolated under `.wfkit/` to avoid mixing with business code

## Role Entry Points
All role scripts are under `.wfkit/scripts/roles/`.

### Shared setup (every machine)
```bash
bash .wfkit/scripts/roles/shared/00_prepare_workspace.sh \
  --repo <owner/name> \
  --workspace-root "$HOME/ai-factory-workspaces" \
  --branch main \
  --install-deps true
```

### Owner/Admin
```bash
bash .wfkit/scripts/roles/owner/01_setup_repo.sh \
  --repo <owner/name> \
  --visibility private \
  --default-branch main \
  --strict-mode true
```

### PM
```bash
bash .wfkit/scripts/roles/pm/02_create_task.sh \
  --repo <owner/name> \
  --task-id TASK-001 \
  --task-type IMPL \
  --title "Task 001: <title>" \
  --acceptance "definition of done"
```

```bash
bash .wfkit/scripts/roles/pm/03_dispatch.sh --repo <owner/name> --event manual_dispatch --assign-self false
```

### Worker
Apply code changes locally first, then submit:
```bash
bash .wfkit/scripts/roles/worker/04_run_task.sh \
  --repo <owner/name> \
  --issue <issue_number> \
  --worker worker-a \
  --ai-mode codex
```

### Reviewer
```bash
bash .wfkit/scripts/roles/reviewer/05_merge_pr.sh \
  --repo <owner/name> \
  --pr <pr_number> \
  --merge-method squash \
  --wait-checks true
```

### Release/QA
```bash
bash .wfkit/scripts/roles/release/07_collect_report.sh --repo <owner/name>
```

## Repository Checks
- baseline checks run in `.wfkit/scripts/ci/run_repo_checks.sh`
- add project-specific checks by copying:
  `.wfkit/scripts/ci/project_checks.sh.example -> .wfkit/scripts/ci/project_checks.sh`

## Notes
- Detailed flow: `.wfkit/docs/ROLE-WORKFLOW.md`
- Execution runbook: `.wfkit/docs/WORKFLOW-RUNBOOK.md`
- AI mode options: `mock|real|codex`
- Optional env for Codex CLI: `CODEX_MODEL`
