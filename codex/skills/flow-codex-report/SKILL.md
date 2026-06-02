---
name: flow-codex-report
description: 在提交后记录一个已完成的 Flow spec，并更新根追踪文档。仅在 Codex 根编排 agent 发放串行报告租约后使用。
---

# Codex Flow 汇报

读取 `../flow-codex-core/references/platform.md`、
`../flow-codex-core/references/checkpoints.md`、
`../flow-codex-core/assets/templates/task-md-maintenance.md` 和 `references/task-update-rules.md`。

## 前置条件

要求收到 `REPORT_LEASE_GRANTED`，并明确提供 `root_path`、`service_name`、`change_name`、
`spec_id`、`commit_hash`、进度文件和测试摘要。确认提交存在且审核已通过。

## 更新

1. 只更新根 `.flow/changes/<change_name>/task.md` 中选中的 spec。
2. 标记完成日期和 commit hash，重新计算选中服务的状态和 frontmatter 日期。
3. 仅在存在 DDL 或配置变更时更新 `发版记录.md`。
4. 向进度文件追加结构化汇报。
5. 返回简短的知识库维护建议。
6. 返回 `[REPORT] complete`，让根 agent 释放租约。

不要与其他执行 agent 并发汇报。
