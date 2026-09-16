---
name: flow-codex-report
description: 在提交后记录一个已完成的 Flow spec，并更新根追踪文档。仅在 Codex 根编排 agent 发放串行报告租约后使用。
---

# Codex Flow 汇报

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「文档与汇报」。沿用现有结果与授权机制，不增加阶段。

读取 `../flow-codex-core/references/platform.md`、
`../flow-codex-core/references/checkpoints.md`、
`../flow-codex-core/assets/templates/task-md-maintenance.md`、
`../flow-codex-core/assets/templates/dev-doc-update-rules.md` 和
`references/task-update-rules.md`。

## 前置条件

要求收到 `REPORT_LEASE_GRANTED`，并明确提供 `root_path`、`service_name`、`change_name`、
`spec_id`、`commit_hash`、进度文件和测试摘要。确认提交存在且审核已通过。

## 更新

1. 只更新根 `.flow/changes/<change_name>/task.md` 中选中的 spec。
2. 标记完成日期和 commit hash，重新计算选中服务的状态和 frontmatter 日期。
3. 仅在存在 DDL、配置或数据访问契约风险时更新 `发版记录.md`；后者在「SQL 风险与 EXPLAIN 证据」登记查询入口、风险形态、最终列表 SQL/分页 count 的 evidence 路径、环境、验收结论、豁免（如有）与回滚方案，不能以源码路径或「待补」代替。
4. 本 spec 涉及接口时，按 `dev-doc-update-rules.md` 的 Apifox 状态表与 requestBody 契约同步；无法匹配的条目逐一说明，MCP 不可用时明确待同步，不静默跳过。将实际返回链接写回接口表。
5. 按 `dev-doc-update-rules.md` 的触发表回写受影响的开发文档章节；写作尺度、可部署服务、自包含 SQL 和业务验收表达以 `dev-doc-maintenance.md` 为准，不复制另一套规则或完整 OpenSpec。
6. 向进度文件追加结构化汇报，含 **【开发文档】** 变更摘要。
7. 返回简短的知识库维护建议。
8. 返回 `[REPORT] complete`，让根 agent 释放租约。

不要与其他执行 agent 并发汇报。REPORT complete 仅表示本次回写完成，不表示根仓已提交；返回本次根文件列表，由根按 ../flow-codex-core/references/delivery.md 提交并执行 flow-codex-check。不要由执行 agent 抢先提交其他 report 的根文件。
