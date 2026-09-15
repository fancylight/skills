---
name: flow-codex-system-test
description: 使用 system-test manifest runner 执行 Flow change 的 API/UI/E2E/CDC 测试并收集原始证据。可用于编排执行或 standalone 复现；runner PASS 不等同完整 Flow 完成。
---

# Codex Flow 系统测试执行

初始化后，当前有效授权从 controller `authorization.maxPhase` 及 grants 读取；manifest.testAuthorization 仅为初始授权。用户追加授权按 core/references/test-controller.md 的 grant-authorization 入账，不从 next 推断、不要求重复授权、不改 manifest 来伪造授权。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「测试与排障」。沿用现有结果与授权机制，不增加阶段。

读取 core platform、`../flow-codex-core/references/test-controller.md`、runtime-contract 和 local-pitfalls。不得修改业务服务代码、整体 mock SUT，或操作 manifest
预留 ID 外的数据。

执行已有用例先读取 ../flow-codex-core/references/test-execution.md；复用适用的项目执行路径，不重新设计测试或维护环境。

## 输入与定位

要求 `change_name`、`testAuthorization` 和 design verify 已核验的配置契约。v2 使用 `environment`、
`configuration.targets/ownership/environmentFile`、`suts`、`runner` 和 resolved fingerprint；v1 保留 `configurationSource`、`requiredEndpoints`、`connectivityProbe`、`ownership` 旧契约。`suite` 可选。`execution_mode` 为
`orchestrated` 或 `standalone`，未由 `flow-codex-test` 委托时默认为 standalone。任何模式均不得绕过授权：
配置契约缺失/漂移、最近一次最小只读探针失败、ceiling<execution 时拒绝健康检查、up、run、Docker 和服务启动，
并输出 `STOP_AWAIT_USER_AUTHORIZATION`。解析根 config、概要设计、manifest、test-design、test-plan 与 system-test 仓。

## 执行

orchestrated 模式先要求 controller `next=RUN_ONCE`，验证当前 harness certification 后调用 `start-run`；只有 controller 已原子持久化 `TEST_EXECUTING` 才运行 manifest 唯一命令。v2 manifest 调用 `system-test.ps1` 时必须把 active run 的 configuration fingerprint 作为 `-ConfigurationFingerprint` 传入。结束后要求 `next=AWAIT_RUN_RESULT`，以当前 active run 的 revision/configuration 和原始 evidence 调用一次 `record-run`。start/record 任一步失败都不运行或重跑。standalone 模式不写 controller state，也不完成 Flow。

独立 smoke 可用 v2 `-ScenarioIds`：仅从 `testCasesContract.path` 的 canonical 派生契约选取精确测试方法，
将 `${FLOW_TEST_FILTER}` 与 `${FLOW_TEST_REPORT_DIR}` 交给 runner 命令。空选集、未知 ID、零匹配、缺失或越界报告、skipped 均失败。
结果必须 `fullSuite=false`，不能登记全量 PASS。新证据写入 `evidence/runs/<run-id>/`，保留旧全量结果和控制状态。
配置中心是本地 dev 配置唯一来源；Git 忽略且 `ownership=human` 的本地文件允许已有凭据，完整文件摘要参与指纹，
日志脱敏后才能进入 evidence。测试夹具使用 `FLOW_RESOLVED_MANIFEST` 查找同一配置，不维护第二份连接凭据。
外部中间件只执行只读探针。managed 复用必须同时通过显式身份与健康探针；无法确认的占用端口直接阻断。
WireMock 本次 mapping 的注册及响应验证放在 `runner.prepare`，失败立即阻断 SUT/业务执行；`runner.cleanup` 仅清理本次夹具。
服务启动默认 120 秒，业务 suite 默认 600 秒；启动适配器同步等待子进程，清理只针对已验证 PID/启动时间的本次进程树。

1. 在 ceiling>=execution 且 implementation PASS 后，在测试仓执行 scope guard（写入仅限 evidence；运行命令按
   health/service/api/runner 传入对应 `-Action test -CommandKind`），再执行设计声明的最小健康检查，
   以 `-ExecutionMode <execution_mode>` 执行 run；runner 管理启动、seed、测试、原始报告、evidence 和 cleanup。
2. 验证 required suite 无 skipped，原始 Surefire/Playwright 报告与 summary 的计数一致；缺原始报告或不一致即 FAIL。
3. 对设计声明的 SQL 风险，仅执行 plan 指定的最终列表 SQL/count 的只读 EXPLAIN；保存脱敏参数、时间、环境、阈值。
4. 无论 PASS 或 FAIL，都必须生成 evidence index、原始报告索引和脱敏后的日志/桩/数据库证据目录（v2 使用 `evidence/runs/<run-id>/`；v1 使用 `evidence/current/`）。
   FAIL 时还必须生成 `failure-report.md`：覆盖每个 failure/error 的场景、方法、分类、确定性、首个证据和建议动作；原始
   报告缺失时明确标记 unavailable 与 `UNDETERMINED`，不得猜测业务缺陷或泄露 secret。
5. orchestrated 结果将摘要镜像到根 `集成测试.md`；standalone smoke 只保存本次证据，不覆盖全量摘要。不得修改 task、概要设计或推导 Flow 完成。ceiling=`execution` 时，结果只可
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
