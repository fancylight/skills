---
name: flow-codex-verify
description: 只读检查 Flow 需求的发布就绪与产物规范（task、分支、开发文档、发版记录等）。集成测试或归档前使用。不验证跨服务 api.md 契约。
---

# Codex Flow 验证

读取 `../flow-codex-core/references/platform.md` 与
`../flow-codex-core/assets/templates/verify-checklist.md`。

对明确指定的 `change_name` 执行只读检查，输出结构化报告：

- **ERROR**：阻断进入 `flow-codex-test` / `flow-codex-archive`
- **WARN**：提示用户确认后可继续
- **PASS**：该项满足

## 检查范围

1. **流程就绪**：task.md 全部 spec 完成、commit hash、期望分支、worktree、OpenSpec、发版记录（见 checklist §1）
2. **根产物齐全**：概要设计、开发文档、task、发版记录（§2）
3. **开发文档规范**：必须章节、禁止 JSON/Flow 痕迹（§3）；细节见 `dev-doc-maintenance.md`

## 不在范围

- 跨服务 api.md 契约比对（Claude Code 的 flow-verify 专责）
- 业务逻辑正确性、HTTP 集成测试、单元测试覆盖

不要编辑或静默修复任何文件。按服务汇总阻断项。
