---
name: flow-codex-system-test
description: 使用 system-test manifest runner 执行 Flow change 的 API/UI/E2E/CDC 测试并收集原始证据。可用于编排执行或 standalone 复现；runner PASS 不等同完整 Flow 完成。
---

# Codex Flow 系统测试执行

读取 core platform、`../flow-codex-core/references/test-controller.md`、runtime-contract 和 local-pitfalls。不得修改业务服务代码、整体 mock SUT，或操作 manifest
预留 ID 外的数据。

## 输入与定位

要求 `change_name`、`testAuthorization` 和 design verify 已核验的配置契约（`configurationSource`、
`requiredEndpoints`、`connectivityProbe`、`ownership`）；`suite` 可选。`execution_mode` 为
`orchestrated` 或 `standalone`，未由 `flow-codex-test` 委托时默认为 standalone。任何模式均不得绕过授权：
配置契约缺失/漂移、最近一次最小只读探针失败、ceiling<execution 时拒绝健康检查、up、run、Docker 和服务启动，
并输出 `STOP_AWAIT_USER_AUTHORIZATION`。解析根 config、概要设计、manifest、test-design、test-plan 与 system-test 仓。

## 执行

orchestrated 模式先要求 controller `next=RUN_ONCE`，验证当前 harness certification 后调用 `start-run`；只有 controller 已原子持久化 `TEST_EXECUTING` 才运行 manifest 唯一命令。结束后要求 `next=AWAIT_RUN_RESULT`，以当前 active run 的 revision/configuration 和原始 evidence 调用一次 `record-run`。start/record 任一步失败都不运行或重跑。standalone 模式不写 controller state，也不完成 Flow。

1. 在 ceiling>=execution 且 implementation PASS 后，在测试仓执行 scope guard（写入仅限 evidence；运行命令按
   health/service/api/runner 传入对应 `-Action test -CommandKind`），再执行设计声明的最小健康检查，
   以 `-ExecutionMode <execution_mode>` 执行 run；runner 管理启动、seed、测试、原始报告、evidence 和 cleanup。
2. 验证 required suite 无 skipped，原始 Surefire/Playwright 报告与 summary 的计数一致；缺原始报告或不一致即 FAIL。
3. 对设计声明的 SQL 风险，仅执行 plan 指定的最终列表 SQL/count 的只读 EXPLAIN；保存脱敏参数、时间、环境、阈值。
4. 无论 PASS 或 FAIL，都必须生成 `changes/<change>/evidence/current/index.md`、原始报告索引和脱敏后的日志/桩/数据库证据目录。
   FAIL 时还必须生成 `failure-report.md`：覆盖每个 failure/error 的场景、方法、分类、确定性、首个证据和建议动作；原始
   报告缺失时明确标记 unavailable 与 `UNDETERMINED`，不得猜测业务缺陷或泄露 secret。
5. 将摘要镜像到根 `集成测试.md`，但不得修改 task、概要设计或推导 Flow 完成。ceiling=`execution` 时，结果只可
   标记为 runner evidence，`next: STOP_AWAIT_USER_AUTHORIZATION`；不得自动进入 result verify。

## 结果

```text
[SYSTEM_TEST_RESULT] PASS | FAIL | BLOCKED
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
failure_report: <absolute path or none>
triage: CONFIG_INFRA | TEST_HARNESS | DATA_SCHEMA_CONTRACT | SUT_BUSINESS | UNDETERMINED
next: flow-codex-test-verify result | blocked
```
