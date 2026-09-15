---
name: "Flow: System Test"
description: "Run system-test manifest runner (orchestrated or standalone); collect evidence; runner PASS ≠ Flow complete"
category: Workflow
tags: [workflow, orchestration, testing, runner]
version: "0.2.0"
---

质量要求：读取 ~/.claude/commands/flow/templates/engineering-quality.md 的「测试与排障」。沿用现有结果与授权机制，不增加阶段。

执行 manifest runner 并收集证据。orchestrated：须 `next=RUN_ONCE` → `start-run` → run → `record-run`；v2 run 必须把 active run 锁定的 configuration fingerprint 传入 runner。standalone 不写 controller、不完成 Flow。

ceiling < execution、配置契约缺失/探针失败 → 拒绝并 `STOP_AWAIT_USER_AUTHORIZATION`。

v2 standalone 支持 `-ScenarioIds`，从 canonical 派生契约确定过滤器和报告集合；空选集、未知 ID、零匹配或 skipped 必须失败。输出 `fullSuite=false`，不能登记全量 PASS。证据写入 `evidence/runs/<run-id>/`，不覆盖旧全量结果。配置中心本地凭据、external 资源、身份校验和 prepare/cleanup 契约遵循共享 `schema.md` §11.2.4 及 system-test 模板 README。

输出 `[SYSTEM_TEST_RESULT] PASS|FAIL|BLOCKED`，`flow_completed: false`。orchestrated 摘要镜像根 `集成测试.md`；standalone 只保存本次证据，不改 task 或全量控制状态。
