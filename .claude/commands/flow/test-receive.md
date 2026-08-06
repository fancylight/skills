---
name: "Flow: Test Receive"
description: "Load st-api integration test spec into system-test executor after validate-lease"
category: Workflow
tags: [workflow, orchestration, testing, executor]
version: "0.1.0"
---

要求 controller `next=AWAIT_IMPLEMENTATION_RESULT` 且 `validate-lease` 通过。

读取根 config、task、概要设计验收、system-test `manifest.yaml`/`test-plan.md`/`test-design.md`。确认 `spec_id=st-api-<change>`。不调用 OpenSpec。追加 `[TEST_RECEIVE] complete`。缺失/分支不匹配/stale fingerprint 时停止。
