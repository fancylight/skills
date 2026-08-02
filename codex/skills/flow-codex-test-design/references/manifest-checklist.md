# 集成测试设计产物清单

`flow-codex-test-design` 必须产出 manifest、test-design、test-plan、IDS、seed 与 cleanup。manifest 使用可解析 JSON
（保留 `.yaml` 扩展名），并在 design 阶段记录 `stage: "design"`、用户授权的 `testAuthorization.ceiling: "design"`。

## 配置与范围

- 声明 `configurationSource`、`requiredEndpoints`、`connectivityProbe`、`ownership`。
- 探针只允许对用户确认的来源执行一次最小只读检查；失败输出 `TEST_CONFIGURATION BLOCKED` 并停止。
- `test-plan.md` 必须记录从根 config 动态解析的 system-test path。
- fixture 仅使用 IDS 预留范围，seed/cleanup 幂等且可回收。

## 场景与运行契约

- `requiredEnvBySuite`、`wireMockContracts`、`fixtureSchema`、`requiredScenarioCount`、`expectedTestMethodCount`、
  `expectedReportClasses`、`runner.command`（token array）和 integration Y/N 映射齐全。
- `wireMockContracts.mappingFile` 相对 system-test 仓；`fixtureSchema` 声明 engine、表、列、唯一约束及 fixture 来源。
- 外部证据缺失只能登记 `TEST_EXTERNAL_EVIDENCE BLOCKED`，不得自动修改 owning repo。

## 失败可观测性

- `failureObservability` 覆盖每个 required integration 场景：场景 ID、测试类/方法、关联字段、原始报告和日志/桩/数据库路径。
- 预期类别仅为 `CONFIG_INFRA`、`TEST_HARNESS`、`DATA_SCHEMA_CONTRACT`、`SUT_BUSINESS` 或 `UNDETERMINED`。
- 未映射、原始报告缺失或证据不足必须落入 `UNDETERMINED`；不得预判业务缺陷或记录 secret。

设计文件、manifest 与 SQL fixture 都必须通过 `validate-test-artifacts.ps1`，不得混入工具输出或实际执行结果。
