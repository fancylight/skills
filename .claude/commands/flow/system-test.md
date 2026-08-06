---
name: "Flow: System Test"
description: "Run system-test manifest runner (orchestrated or standalone); collect evidence; runner PASS ≠ Flow complete"
category: Workflow
tags: [workflow, orchestration, testing, runner]
version: "0.1.0"
---

执行 manifest runner 并收集证据。orchestrated：须 `next=RUN_ONCE` → `start-run` → run → `record-run`。standalone 不写 controller、不完成 Flow。

ceiling < execution、配置契约缺失/探针失败 → 拒绝并 `STOP_AWAIT_USER_AUTHORIZATION`。

输出 `[SYSTEM_TEST_RESULT] PASS|FAIL|BLOCKED`，`flow_completed: false`。摘要镜像根 `集成测试.md`，不改 task。
