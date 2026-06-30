---
name: flow-codex-report
description: 在提交后记录一个已完成的 Flow spec，并更新根追踪文档。仅在 Codex 根编排 agent 发放串行报告租约后使用。
---

# Codex Flow 汇报

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
3. 仅在存在 DDL 或配置变更时更新 `发版记录.md`。
4. **同步接口到 Apifox**：读取根 `开发文档.md` **§3.2.4** 接口表格，按 `dev-doc-update-rules.md` 处理：
   - 已有 Apifox 链接 + ✏️修改 → MCP 更新接口定义
   - 待录入 + 🆕新增 → MCP 创建接口
   - 待录入 + ✏️修改 → 提示先手动创建
   - **兜底：表格状态不匹配任何分支时，禁止静默跳过，必须在汇报中逐条列出并提示人工确认**
   **POST 接口 requestBody 格式**：必须用 jsonSchema 模式（`type: "application/json"` + `parameters: []` + 字段放 `jsonSchema.properties`），禁止用 `type: "json"` + `parameters[]` 写法（UI 不渲染）。
   MCP 不可用时降级跳过。同步后将「待录入/待补充」替换为实际链接（格式 `https://app.apifox.com/link/project/{projectId}/apis/api-{entityId}`）。
5. **回写开发文档.md**：按 `dev-doc-update-rules.md` 从本 spec 的 OpenSpec `design.md` 与 commit 更新：
   - §3.2.4 本 spec 相关接口行
   - §3.2.2 存储语义（有 DDL 时，不写 SQL 全文）
   - §3.2.3 数据流转（有新链路时）
   - §3.2.1 业务规则（有收敛时）
   - §4.2 SQL/配置摘要（有变更时）
   禁止写入 spec 名、文件路径清单、完整 JSON。
6. 向进度文件追加结构化汇报，含 **【开发文档】** 变更摘要。
7. 返回简短的知识库维护建议。
8. 返回 `[REPORT] complete`，让根 agent 释放租约。

不要与其他执行 agent 并发汇报。
