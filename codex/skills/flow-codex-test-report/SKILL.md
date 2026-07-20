---
name: flow-codex-test-report
description: 记录已完成的 st-api 集成测试 spec，更新根 task.md。仅在根 agent 发放串行报告租约后使用。不回写开发文档。
---

# Codex Flow 集成测试汇报

读取 `../flow-codex-core/references/platform.md`、
`../flow-codex-core/references/checkpoints.md`、
`../flow-codex-core/assets/templates/task-md-maintenance.md` 和
`references/task-update-rules.md`。

## 前置条件

要求收到 `REPORT_LEASE_GRANTED`，并明确提供 `root_path`、`change_name`、`spec_id`
（`st-api-<change_name>`）、`commit_hash`（或 `local-only`）、进度文件和测试摘要。

## 更新

1. 只更新根 `.flow/changes/<change_name>/task.md` 中 `st-api-<change_name>` 条目。
2. 标记完成：`完成：{date} commit {hash}` 或 `完成：{date} local-only`。
3. **重写** `## glm-system-test` 服务头部状态行。
4. 勾选完成检查清单：`集成测试代码完成`。
5. 更新 frontmatter `updated`。
6. **禁止**回写 `开发文档.md`、Apifox 或 `发版记录.md`（无业务 DDL）。
7. 向进度文件追加结构化汇报。
8. 返回 `[REPORT] complete`。

不要与其他执行 agent 并发汇报。
