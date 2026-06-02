---
name: flow-codex-archive
description: 在验证和集成测试后归档已完成的 Flow 需求。用户要求完成或归档 Flow change 时使用。
---

# Codex Flow 归档

读取 `../flow-codex-core/references/platform.md`。要求用户明确确认、验证通过、集成测试通过、发版
记录完整，并确认期望分支干净。遇到分支不匹配或脏 worktree 时停止，不要静默 checkout。归档根需求
和匹配的服务 OpenSpec changes，然后报告最终路径和提交状态。
