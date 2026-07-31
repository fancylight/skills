---
name: flow-codex-test-assign
description: 向 system-test 仓派发 st-api 集成测试 spec。仅在当前轮 flow-codex-test-verify design PASS 后使用，不修改业务派发链路。
---

# Codex Flow 集成测试派发

作为根编排 agent 执行。读取 core platform、checkpoints、scheduler 与 test-child-agent-prompt。

## 派发前检查

1. 根角色为 `orchestrator`，并提供 `change_name`。
2. `flow-codex-verify` 全量 §A+§B 无 ERROR。
3. 当前轮 `[TEST_VERIFY_RESULT] PASS` 且 `verify_mode: design`；其 SUT/test 仓 revision 与当前基线一致。
4. config 可解析 system-test 仓，且 manifest、test-design、test-plan、IDS、seed、cleanup 存在。
5. task 中 st-api 依赖的业务 spec 已完成；不得以 task checkbox 或 TEST_DESIGN READY 替代第 3 项。
6. 期望分支及 scoped-clean 基线成立；不明历史改动时停止。

## 派发

1. 为 `st-api-<change_name>` 启动一个 system-test 执行 agent，附带 receive、apply、report 和 child prompt。
2. 执行 agent 依序 receive → apply → report；不得跳过 review 或报告租约。
3. 收到 REVIEW_REQUEST 时启动同级 `flow-codex-review` test 模式，设计路径包含 test-design、test-plan、manifest。
4. REVIEW PASS、冒烟通过后才发放唯一 REPORT_LEASE；等待 `[REPORT] complete` 并更新根调度状态。

不要在根上下文编写测试代码或修改业务服务。
