---
name: flow-codex-archive
description: 在验证和集成测试后归档已完成的 Flow 需求。用户要求完成或归档 Flow change 时使用。
---

# Codex Flow 归档

读取 `../flow-codex-core/references/platform.md` 与
`../flow-codex-core/assets/templates/verify-checklist.md`。

## 前置

- 要求本 change 已执行 `flow-codex-verify` **发布 verify（§A+§B+§F）** 且**无 ERROR**（WARN 需用户确认）。**不**要求 archive 前再跑 §C/§D/§E；§F 的 SQL 风险契约和 EXPLAIN 证据缺失均阻断归档。
- 要求用户明确确认、集成测试通过、发版记录完整
- 集成测试：最近一次 `[TEST_VERIFY_RESULT] PASS` 且 `verify_mode: result`，并且 `.flow/changes/<change>/集成测试.md`
  一致；用户明示跳过只允许不需要集成测试的 change，不得将 standalone runner PASS 视为替代
- 集成测试状态中的 authorization ceiling 必须至少为 `result`；任何越级执行、scope violation、stale agent 恢复或
  `MAX_REJECT_ROUNDS` 后未经用户授权的 fingerprint 重置均阻断归档
- 确认期望分支干净；分支不匹配或脏 worktree 时停止，不要静默 checkout
- 若概要设计存在 `kb_action: 待沉淀` 且未执行 `flow-codex-kb` change 入口，**WARN** 并提示用户是否先沉淀 KB

归档根需求和匹配的服务 OpenSpec changes，然后报告最终路径和提交状态。
