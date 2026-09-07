# 集成测试设计产物清单

`flow-codex-test-design` 必须产出 manifest、test-cases、test-cases.generated.json、test-design、test-plan、IDS、seed 与 cleanup。manifest 使用可解析 JSON
（保留 `.yaml` 扩展名），并在 design 阶段记录 `stage: "design"`、用户授权的 `testAuthorization.ceiling: "design"`。

## 配置与范围

- 新配置中心环境使用 v2 environment/descriptor、configuration targets/ownership、SUT、runner 与 harness；先生成 resolved manifest。只有 v1 声明 `configurationSource`、`requiredEndpoints`、`connectivityProbe`、`ownership`，不得混用。
- native 模式可在启动契约传入 profile/search locations；human 且 Git 忽略的本地配置允许已有凭据，产物只保存来源和 hash。夹具从同一配置中心取得连接信息。
- 外部中间件生命周期为 external。WireMock 契约由 runner.prepare 注册并验证，失败阻断，cleanup 不全局清空。
- 探针只允许对用户确认的来源执行一次最小只读检查；失败输出 `TEST_CONFIGURATION BLOCKED` 并停止。
- `test-plan.md` 必须记录从根 config 动态解析的 system-test path。
- fixture 仅使用 IDS 预留范围，seed/cleanup 幂等且可回收。

## 场景与运行契约

- `test-cases.yaml` 使用严格结构化 schema；manifest 只以 `testCasesContract.path` 指向
  `test-cases.generated.json`，不得在根重复场景 count、filter、report、integration、evidence 或 failureObservability。
- sidecar 必须绑定 controller 的初始 `testBaseline` revision 与 source hash；实际设计/实现提交由 controller revision 单独锁定，
  不得要求 sidecar 绑定包含其自身的提交。sidecar 还必须包含 integration Y/N、required count、expected method count、
  runner filter、report classes、evidence index 骨架和 failure observability 全映射。
- `requiredEnvBySuite`、`wireMockContracts`、`fixtureSchema` 与 `runner.command`（token array）仍由 manifest 人工区维护。
- 迁移旧 manifest 时保留上述人工配置与授权，只新增 sidecar pointer，并移除旧 count/filter/report/integration/
  evidence/failureObservability 派生字段；未迁移字段必须使 design verify 失败。
- `wireMockContracts.mappingFile` 相对 system-test 仓；`fixtureSchema` 声明 engine、表、列、唯一约束及 fixture 来源。
- 外部证据缺失只能登记 `TEST_EXTERNAL_EVIDENCE BLOCKED`，不得自动修改 owning repo。

## 失败可观测性

- sidecar 的 `failureObservability` 覆盖每个场景：场景 ID、测试类/方法、关联字段、普通/外部证据路径。
- 预期类别仅为 `CONFIG_INFRA`、`TEST_HARNESS`、`DATA_SCHEMA_CONTRACT`、`SUT_BUSINESS` 或 `UNDETERMINED`。
- 未映射、原始报告缺失或证据不足必须落入 `UNDETERMINED`；不得预判业务缺陷或记录 secret。

设计文件、manifest 与 SQL fixture 都必须通过 `validate-test-artifacts.ps1`，不得混入工具输出或实际执行结果。
