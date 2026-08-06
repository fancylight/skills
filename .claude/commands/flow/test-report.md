---
name: "Flow: Test Report"
description: "Record st-api implementation complete under REPORT_LEASE_GRANTED; accept-result via controller"
category: Workflow
tags: [workflow, orchestration, testing, executor]
version: "0.1.0"
---

要求 `REPORT_LEASE_GRANTED`。review PASS + 静态实现校验 PASS + 可恢复 commit。

controller `accept-result` 接受 proposedTestRevision 后才更新根 task 的 st-api 条目（勾选「集成测试代码完成」，**不**勾选「集成测试执行 PASS」）。返回 `[REPORT] complete`。不回写开发文档/发版记录/Apifox/业务代码。
