---
name: flow-codex-system-test
description: 使用 system-test manifest runner 执行 Flow change 的 API/UI/E2E/CDC 测试并收集原始证据。可用于编排执行或 standalone 复现；runner PASS 不等同完整 Flow 完成。
---

# Codex Flow 系统测试执行

读取 core platform、runtime-contract 和 local-pitfalls。不得修改业务服务代码、整体 mock SUT，或操作 manifest
预留 ID 外的数据。

## 输入与定位

要求 `change_name`；`suite` 可选。`execution_mode` 为 `orchestrated` 或 `standalone`，未由 `flow-codex-test`
委托时默认为 standalone。解析根 config、概要设计、manifest、test-design、test-plan 与 system-test 仓。

## 执行

1. 在测试仓执行 doctor，再以 `-ExecutionMode <execution_mode>` 执行 run；runner 管理启动、seed、测试、原始报告、evidence 和 cleanup。
2. 验证 required suite 无 skipped，原始 Surefire/Playwright 报告与 summary 的计数一致；缺原始报告或不一致即 FAIL。
3. 对设计声明的 SQL 风险，仅执行 plan 指定的最终列表 SQL/count 的只读 EXPLAIN；保存脱敏参数、时间、环境、阈值。
4. evidence 必须记录命令、执行时间、服务版本、测试仓 revision、业务仓 revisions、manifest hash 和 cleanup 状态。
5. 将摘要镜像到根 `集成测试.md`，但不得修改 task、概要设计或推导 Flow 完成。

## 结果

```text
[SYSTEM_TEST_RESULT] PASS | FAIL
change_name: <name>
execution_mode: orchestrated | standalone
flow_completed: false
suites: <comma-separated suites>
passed: <count>
failed: <count>
skipped: <count>
evidence: <absolute path>
sql_plan_evidence: <absolute path or none>
retained_state: true | false
cleanup_command: <command or none>
next: flow-codex-test-verify result | blocked
```
