---
name: flow-codex-test-design
description: 在业务代码已审核提交后，基于概要设计验收、as-built revision 和本地环境设计可独立实施的 Flow 集成测试。以 test-cases.yaml 为唯一场景源，产出确定性 sidecar、test-design、test-plan、manifest 与 fixtures 契约，不编写 JUnit。
---

# Codex Flow 集成测试设计

作为根编排 agent 执行。读取 `../flow-codex-core/references/platform.md`、
`../flow-codex-core/references/test-controller.md`、
`references/manifest-checklist.md`、`references/scaffold.md` 和已安装模板中的
`test-design.md.tmpl`、`test-plan.md.tmpl`。

## 硬前置与输入

先解析 canonical `.flow/changes/<change_name>/automation-state.yaml`。若 state 已存在，只有 controller `next` 与当前动作相容时才继续；若不存在，可完成 design 产物并形成可提交 design revision，然后以用户明确授权 ceiling、固定 SUT/harness revision、harness certification 和 configuration fingerprint 执行唯一一次 `initialize`。不得自行写 state。

1. 要求根角色为 `orchestrator` 与明确的 `change_name`。以 system-test change 的 `manifest.yaml.testAuthorization`
   作为等价测试状态；首次设计时依据用户本轮明确授权初始化为 `ceiling: design`。不得修改根 task/progress 来
   记录授权，也不得从 skill 建议的 `next` 推导或提升授权。
2. 所有纳入范围的业务 spec 已完成 review、单元测试和提交；`flow-codex-verify` 全量 §A+§B 无 ERROR。
3. 每个 SUT 记录仓库、期望分支、commit、启动模块和配置；未提交业务代码不得作为基线。
4. 读取概要设计验收、操作链路、数据访问契约、OpenSpec/as-built、单元测试结果、本地 playbook 和现有
   system-test 支撑。不得读取本需求已写集成测试代码反推设计。
5. 关键中间件、数据、鉴权、外部依赖替身或观测能力无法盘点时 BLOCKED。

## 步骤

0. 按 `scaffold.md` 解析或初始化 config 中的 system-test 仓；已存在完整仓时只增量更新 change 产物。
1. 为概要设计每条验收分配稳定 `AC-n`，确定集成 Y/N、Non-Goal 或后续阶段；N 不得伪装为覆盖。
2. 先创建 `changes/<change_name>/test-cases.yaml`。它是稳定场景 ID、required、集成 Y/N、测试类/方法、
   report class、runner filter 和 evidence 契约的唯一可执行来源；setup/action/assertions/observability 使用结构化对象，
   cleanup/externalEvidence 使用列表。同一场景不得在 Markdown 维护第二份手写计数或映射。使用确定性生成器更新
   test-plan 的唯一标记区和 `test-cases.generated.json`；manifest 只以 `testCasesContract.path` 引用 sidecar。
   重复或缺失 ID、未知 ID、Java 方法未绑定、报告/证据漂移均在设计验证中拒绝。
3. 设计并写入 `test-design.md`：完整覆盖 TDD.1–TDD.10（目标与风险、SUT revision、拓扑、真实/桩边界、
   鉴权、夹具、观测点、覆盖策略、SQL、失败归因）。
4. 在 `test-plan.md` 只写场景背景、边界和人工说明，不复制可执行场景表、ID、方法或计数。每个 Y 验收仍必须
   在 canonical source 中有 happy path、核心断言和副作用观测；正向能力缺 happy path，或“未写入”缺观测，均 BLOCKED。
5. 由 canonical source 推导 sidecar、IDS、幂等 seed/cleanup、环境契约及必要 release SQL 镜像；manifest 不得承担覆盖论证，
   但必须登记 `requiredEnvBySuite`、system-test 仓库相对的 `wireMockContracts`（SUT Feign method/path/query/minimum response）、
   带 `engine` 的 `fixtureSchema`、`fixtureJavaSources`/`fixtureDynamicSql`、`requiredScenarioCount`、
   Excel 语义契约和 `testCasesContract.path`。sidecar 必须登记 `requiredScenarioCount`、`expectedTestMethodCount`、
   精确 `expectedReportClasses`、runner filters、integration Y/N、evidence index 和 `failureObservability`：
   场景 ID、测试类/方法、关联字段、普通/外部证据路径和可判定类别；
   未映射或证据缺失时必须允许 `UNDETERMINED`，不得预设业务缺陷。
   当设计引用数据库、缓存、SUT 或 WireMock 配置时，另必须登记 `configurationSource`、`requiredEndpoints`、
   `connectivityProbe` 和 `ownership`；来源只能由用户确认，probe 只能是单次最小只读连接/metadata 检查。
6. 数据访问风险必须在 plan 中列最终列表 SQL/count、代表性参数、只读 EXPLAIN 命令/阈值/evidence 路径；不可得则 BLOCKED。
7. 对每一个首次写入、静态校验和提交目标，先执行
   `flow-codex-core/assets/scripts/test-scope-guard.ps1 -AuthorizedRepo <system-test> -TargetPath <target> -Stage design`；任何
   `[FLOW_GUARD] BLOCKED_SCOPE_VIOLATION` 均停止。只可写 system-test 的
   `changes/<change>/test-design.md`、`test-plan.md`、`test-cases.yaml`、`test-cases.generated.json`、manifest 和
   `fixtures/**`，不得改根 task/progress。
8. 只允许 Markdown/JSON/SQL 静态解析与 lint；配置契约已完整且用户明确授权时，允许执行一次其声明的
   `connectivityProbe`。probe 失败必须输出 `[TEST_CONFIGURATION] BLOCKED` 和
   `next: STOP_AWAIT_HUMAN_CONFIGURATION`；不得猜测 schema、改 `.env.local`、安装工具、切换来源或继续实现。
   除该 probe 外，禁止编译、`mvn test`、Docker、doctor、服务启动和 runner。
9. READY 前先运行 `validate-test-cases.ps1 -Generate -CanonicalRevision <test revision> -ManifestPath <manifest>
   -DerivedContractPath <test-cases.generated.json> -TestPlanPath <test-plan>`，再运行
   `flow-codex-core/assets/scripts/validate-test-artifacts.ps1 -SystemTestRepo <path> -ChangeName <name> -Mode design
   -CanonicalRevision <test revision>`。任一
   `[TEST_ARTIFACT_GUARD] ERROR` 均为 BLOCKED，不得提交、写 READY 或进入下一阶段。
   required 场景删除时，另传 previous source/revision、design verifier report、controller state 和受信 verifier identity；
   不得使用自由布尔开关声明 design verify 已通过。
10. 在 manifest 记录 `testAuthorization`（默认 ceiling=design）、review identity/reject rounds 和 capability
   fingerprint；不得修改根 task/progress，也不得因自身 READY 勾选通过。

禁止写 JUnit、修改业务源码，或在 design/plan 中写实际 PASS、日期、耗时、真实 EXPLAIN 与事后 evidence。

## 结果

```text
[TEST_DESIGN_RESULT] READY | BLOCKED
change_name: <name>
service_name: <system-test service name>
service_path: <absolute path>
business_revisions:
  - <repo> <branch> <commit>
acceptance: <AC count>; required_scenarios: <count>
topology: <summary>
blocked:
  - <item or none>
authorization_ceiling: design | implementation | execution | result
next_authorized: true | false
next: flow-codex-test-verify design | STOP_AWAIT_USER_AUTHORIZATION
```

设计 verify PASS 后，若 ceiling 仍为 `design`，必须输出 `next: STOP_AWAIT_USER_AUTHORIZATION`；不得派发或
创建实现 agent。
