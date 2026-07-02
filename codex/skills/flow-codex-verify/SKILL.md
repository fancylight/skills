---
name: flow-codex-verify
description: 只读检查 Flow 根产物与子 OpenSpec 格式；test/archive 前附加发布就绪检查。不验证业务内容正确性与跨服务 api.md 契约。
---

# Codex Flow 验证

读取 `../flow-codex-core/references/platform.md` 与
`../flow-codex-core/assets/templates/verify-checklist.md`。

对明确指定的 `change_name` 执行只读检查，输出结构化报告：

- **ERROR**：阻断进入 `flow-codex-test` / `flow-codex-archive`（全量 verify 时）
- **WARN**：提示用户确认后可继续
- **PASS**：该项满足

## 调用模式

| 模式 | 执行章节 | 时机 |
|------|----------|------|
| **格式复验** | 仅 §A 产物格式 | design 完成后可选；检查 task/概要设计/OpenSpec/开发文档 **结构** |
| **全量 verify** | §A + §B | `flow-codex-test` / `flow-codex-archive` **强制前置** |

格式复验时 §B 未完成属正常，不得因此报 ERROR。

## 检查范围

1. **§A 产物格式**（见 checklist §A）：根四件套、概要设计 Spec 矩阵、task.md 行型与 Spec 粒度、开发文档格式、子 OpenSpec 结构、发版记录行型
2. **§B 发布就绪**（见 checklist §B，仅全量）：spec 完成度、分支、worktree、发版记录覆盖

Spec 粒度（1 c = 1 repo）主门禁在 `flow-codex-design` 第 5 步；verify §A 做只读复验。

## 不在范围

- 跨服务 api.md 契约比对（Claude Code 的 flow-verify 专责）
- 业务逻辑、接口语义、验收标准是否满足、Non-goals 是否正确
- HTTP 集成测试、单元测试覆盖

不要编辑或静默修复任何文件。按服务汇总阻断项。
