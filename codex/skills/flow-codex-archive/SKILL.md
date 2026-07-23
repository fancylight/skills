---
name: flow-codex-archive
description: 在验证和集成测试后归档已完成的 Flow 需求。用户要求完成或归档 Flow change 时使用。
---

# Codex Flow 归档

读取 `../flow-codex-core/references/platform.md` 与
`../flow-codex-core/assets/templates/verify-checklist.md`。

## 前置

- 要求本 change 已执行 `flow-codex-verify` **全量（§A+§B）** 且**无 ERROR**（WARN 需用户确认）。**不**要求 archive 前再跑 §C
- 要求用户明确确认、集成测试通过、发版记录完整
- 集成测试：`.flow/changes/<change>/集成测试.md` 记录 PASS，或用户明示跳过集成测试
- 确认期望分支干净；分支不匹配或脏 worktree 时停止，不要静默 checkout
- 若概要设计存在 `kb_action: 待沉淀` 且未执行 `flow-codex-kb` change 入口，**WARN** 并提示用户是否先沉淀 KB

归档根需求和匹配的服务 OpenSpec changes，然后报告最终路径和提交状态。
