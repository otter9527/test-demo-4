# Workflow Runbook

本手册用于团队在本仓库执行标准开发流：
Issue -> Dispatch -> Worker PR -> Review -> Merge -> Post-Merge -> Next Task。

## 1. 前置条件
1. 每台机器安装：`git`、`gh`、`python3`。
2. 每位执行者完成登录：`gh auth status` 显示已登录。
3. 仓库 Owner 具备配置 Branch Protection 权限。

## 2. 初始化阶段（Owner/Admin）
```bash
bash .wfkit/scripts/roles/owner/01_setup_repo.sh \
  --repo <owner/name> \
  --visibility private \
  --default-branch main \
  --strict-mode true
```

## 3. 角色机器准备（所有角色各自执行）
```bash
bash .wfkit/scripts/roles/shared/00_prepare_workspace.sh \
  --repo <owner/name> \
  --workspace-root "$HOME/ai-factory-workspaces" \
  --branch main \
  --install-deps true
```

## 4. PM：创建任务与派发
```bash
bash .wfkit/scripts/roles/pm/02_create_task.sh \
  --repo <owner/name> \
  --task-id TASK-001 \
  --task-type IMPL \
  --title "Task 001: <title>" \
  --acceptance "definition of done"
```

```bash
bash .wfkit/scripts/roles/pm/03_dispatch.sh \
  --repo <owner/name> \
  --event manual_dispatch \
  --assign-self false
```

## 5. Worker：执行任务并提交 PR
```bash
bash .wfkit/scripts/roles/worker/03_inbox.sh \
  --repo <owner/name> \
  --worker worker-a \
  --status in_progress
```

```bash
bash .wfkit/scripts/roles/worker/04_run_task.sh \
  --repo <owner/name> \
  --issue <issue_number> \
  --worker worker-a \
  --ai-mode codex
```

## 6. Reviewer：审查与合并
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

## 7. PM：合并后推进
```bash
bash .wfkit/scripts/roles/pm/06_post_merge.sh \
  --repo <owner/name> \
  --pr <pr_number>
```

## 8. 发布快照（Release/QA）
```bash
bash .wfkit/scripts/roles/release/07_collect_report.sh \
  --repo <owner/name>
```

## 9. 标准循环
1. PM 派发。
2. Worker 提交 PR。
3. Reviewer 合并。
4. PM 合并后推进。
5. 重复直到 backlog 清空。

## 10. 注意事项
1. 不允许直推 `main`。
2. PR 必须包含 `Closes #<issue>`。
3. 项目检查入口为 `.wfkit/scripts/ci/run_repo_checks.sh`。
4. 项目可在 `.wfkit/scripts/ci/project_checks.sh` 中添加自定义检查。
