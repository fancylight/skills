---
name: "Flow: Test Report"
description: "Record st-api implementation complete under REPORT_LEASE_GRANTED; accept-result via controller"
category: Workflow
tags: [workflow, orchestration, testing, executor]
version: "0.1.0"
---

质量要求：读取 ~/.claude/commands/flow/templates/engineering-quality.md 的「测试与排障、文档与汇报」。沿用现有结果与授权机制，不增加阶段。

要求 `REPORT_LEASE_GRANTED`。review PASS + 静态实现校验 PASS + 可恢复 commit。

controller `accept-result` 接受 proposedTestRevision 后才更新根 task 的 st-api 条目（勾选「集成测试代码完成」，**不**勾选「集成测试执行 PASS」）。返回 `[REPORT] complete`。不回写开发文档/发版记录/Apifox/业务代码。
