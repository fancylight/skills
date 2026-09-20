---
name: flow-codex-test-design
description: 在业务代码已审核提交后，基于概要设计验收、as-built revision 和本地环境设计可独立实施的 Flow 集成测试。先审核业务用例，再以 test-cases.yaml 为唯一场景源设计技术执行，产出确定性 sidecar、test-design、test-plan、manifest 与 fixtures 契约，不编写 JUnit。
---

# Codex Flow 集成测试设计

旧执行预算耗尽后，用户新授权的设计/开发按 core/references/test-execution-cycle.md 的 revise / review-design 推进，读取 developmentNext；不得把旧 budget-exhausted 当成整个需求永久停止。原轮修复重跑仍受旧预算约束，设计/编码授权不隐含新运行预算。


正式测试先读取 `../flow-codex-core/references/test-execution-cycle.md`。已接入 execution 的需求使用 `flow-test.ps1 status`，按其 prepare/advance/resume 路径推进；以下旧 next/租约步骤仅用于尚未接入的需求。允许已审核的最小切片先正式运行，其余场景保持未验证；同一对话继续，不新增用户阶段。

审核业务判断时先读取 `../flow-codex-core/references/design-challenge.md`，在现有审核中核对原始依据和可证伪输入；结构检查不得自动产生语义 PASS。

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

业务场景及开发小链路按 `../flow-codex-core/references/first-delivery.md` 前置到 design/apply。这里仍是正式测试设计入口，承接同一场景源，不为早期局部测试绕过提交和门禁要求。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「测试与排障」。沿用现有结果与授权机制，不增加阶段。

作为根编排 agent 执行。读取 `../flow-codex-core/references/platform.md`、
`../flow-codex-core/references/test-controller.md`、
`references/manifest-checklist.md`、`references/scaffold.md` 和已安装模板中的
`test-design.md.tmpl`、`test-plan.md.tmpl`。

## 硬前置与输入

先解析 canonical `.flow/changes/<change_name>/automation-state.yaml`。若 state 已存在且用户要求存量设计复核或补充业务用例，优先按协议 `reopen-design`，更新提交后 `accept-design-revision`（design 上限不阻断设计复核）；其他情况只有 controller `next` 与当前动作相容时才继续。不得删除或重建 state；若不存在，可完成 design 产物并形成可提交 design revision，然后以用户明确授权 ceiling、固定 SUT/harness revision、harness certification 和 configuration fingerprint 执行唯一一次 `initialize`。不得自行写 state。

1. 要求根角色为 `orchestrator` 与明确的 `change_name`。以 system-test change 的 `manifest.yaml.testAuthorization`
   记录初始用户授权（缺少后续阶段授权时 ceiling=design；已明确授权更高阶段时如实记录）。controller 初始化后，当前有效上限读取 `authorization.maxPhase` 及 grants，追加授权用协议 `grant-authorization`，不修改已提交 manifest。不得修改根 task/progress 来
   记录授权，也不得从 skill 建议的 `next` 推导或提升授权。
2. 所有纳入范围的业务 spec 已完成 review、单元测试和提交；`flow-codex-verify` 全量 §A+§B 无 ERROR。
3. 每个 SUT 记录仓库、期望分支、commit、启动模块和配置；未提交业务代码不得作为基线。
4. 读取概要设计验收、操作链路、数据访问契约、OpenSpec/as-built、单元测试结果、本地 playbook 和现有
   system-test 支撑。不得读取本需求已写集成测试代码反推设计。
5. 业务草案可先形成；进入技术设计前，关键中间件、数据、鉴权、外部依赖替身或观测能力无法盘点时 BLOCKED。

## 步骤

以下环境约束在业务用例审核补齐后应用。新配置中心环境使用共享 v2 manifest：引用平台已登记的 repo 级 descriptor，声明 configuration targets、ownership、SUT 启动契约、runner 与 harness；旧 v1 才使用 configurationSource 等旧字段。先用 core `assets/scripts/resolve-test-environment.ps1` 生成 resolved manifest，再进行设计校验。native 模式可以由启动契约传入 profile/search locations，无须在业务源码新增配置文件。
本地 dev 配置保存在配置中心；Git 忽略的 human 本地输入允许已有凭据，设计产物只记录来源和完整文件 hash。夹具读取同一配置来源，`.env` 仅用于必要运行参数。配置迁移属于已获授权的平台准备，不在业务 test-design 内生成替代 dev 配置。
外部中间件登记 external，runner 不启停或重建；WireMock 的方法、路径、参数、鉴权及响应契约提前明确，由 `runner.prepare` 注册并验证本次 mapping，失败阻断后续业务，cleanup 只清理本次资源。

0. 按 `scaffold.md` 解析或初始化 config 中的 system-test 仓；已存在完整仓时只增量更新 change 产物。
1. 为概要设计每条验收分配稳定 `AC-n`，确定集成 Y/N、Non-Goal 或后续阶段；N 不得伪装为覆盖。
2. 先在 `test-cases.yaml` 编写稳定 id、acceptance、required、integration 与结构化 `business`，暂不要求测试类、方法、HTTP路径或夹具。
   business 必须让业务用户能审核：验证目的、规则配置与初态、具体输入、操作顺序、独立预期最终结果、预期依据及推导、关键反例、Y/N与证据边界。
   先用 `validate-test-cases.ps1 -TestCasesPath <source> -Mode business -TestPlanPath <plan> -Generate` 生成业务预览（只更新既有标记区，无 sidecar）。
   对照需求逐条审核业务覆盖并补齐：区分配置分支、边界、变更重算、重复/乱序及真实最终落点；仅在当前需求适用时纳入。
   单对话由当前执行者自查并在 test-design 的既有覆盖策略中记明依据、发现与补充及源 hash；不得冒称用户已审核。
   用户要求先审核用例时在此展示预览并等待其意见；否则在已有授权内完成自查后继续，不额外创造审批关卡。
   业务歧义或缺独立预期尚未解决时，不用技术设计掩盖缺口。反例描述必须落实到相应场景/断言或有明确的外部证据边界，不能只写反例文字就计为已覆盖。
   业务审核补齐后，才在同一场景添加 setup/action/assertions/observability 对象、cleanup/externalEvidence 列表及技术绑定。
   后续技术可行性改变业务覆盖时返回本步复核受影响用例；技术设计不得反向篡改预期以迎合实现。
3. 设计并写入 `test-design.md`：完整覆盖 TDD.1–TDD.10（目标与风险、SUT revision、拓扑、真实/桩边界、
   鉴权、夹具、观测点、覆盖策略、SQL、失败归因）。
4. `test-plan.md` 的唯一生成区以业务用例为主体、技术映射为附录；人工区只写背景与边界，不手工复制第二套用例、ID或计数。每个 Y 验收仍必须
   在 canonical source 中有 happy path、核心断言和副作用观测；正向能力缺 happy path，或“未写入”缺观测，均 BLOCKED。
5. 由 canonical source 推导 sidecar、IDS、幂等 seed/cleanup、环境契约及必要 release SQL 镜像；manifest 不得承担覆盖论证，
   但必须登记 `requiredEnvBySuite`、system-test 仓库相对的 `wireMockContracts`（SUT Feign method/path/query/minimum response）、
   带 `engine` 的 `fixtureSchema`、`fixtureJavaSources`/`fixtureDynamicSql`、
   Excel 语义契约和 `testCasesContract.path`。sidecar 必须登记 `requiredScenarioCount`、`expectedTestMethodCount`、
   精确 `expectedReportClasses`、runner filters、integration Y/N、evidence index 和 `failureObservability`：
   场景 ID、测试类/方法、关联字段、普通/外部证据路径和可判定类别；
   未映射或证据缺失时必须允许 `UNDETERMINED`，不得预设业务缺陷。
   当设计引用数据库、缓存、SUT 或 WireMock 配置时，v2 登记 environment、configuration targets、结构化 probes、resources 生命周期及 resolved fingerprint；v1 才登记 `configurationSource`、`requiredEndpoints`、
   `connectivityProbe` 和 `ownership`。来源只能由用户确认，preflight probe 只能是单次最小只读连接/metadata 检查。
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
9. READY 前先取得初始化前 system-test 仓当前提交，作为稳定的 `<test baseline revision>`。sidecar 只绑定该基线、
   `test-cases.yaml` 内容 hash 与 test-plan 人工区 hash；不得尝试绑定包含 sidecar 自身的设计提交，否则会形成不可收敛的
   commit 自引用。先运行 `validate-test-cases.ps1 -Generate -CanonicalRevision <test baseline revision> -ManifestPath <manifest>
   -DerivedContractPath <test-cases.generated.json> -TestPlanPath <test-plan>`，再运行
   `flow-codex-core/assets/scripts/validate-test-artifacts.ps1 -SystemTestRepo <path> -ChangeName <name> -Mode design
   -CanonicalRevision <test baseline revision>`。设计产物提交后，controller `initialize` 必须分别记录该 baseline 和实际
   design revision；后续 verifier 从 controller `revisions.testBaseline` 取得同一参数，并独立校验当前设计/实现 revision。
   任一
   `[TEST_ARTIFACT_GUARD] ERROR` 均为 BLOCKED，不得提交、写 READY 或进入下一阶段。
   required 场景删除时，另传 previous source/revision、design verifier report、controller state 和受信 verifier identity；
   不得使用自由布尔开关声明 design verify 已通过。
10. 在 manifest 记录初始 `testAuthorization`（默认 ceiling=design；已有更高授权如实记录，initialize 以 grant 报告绑定用户原话及引用）、review identity/reject rounds 和 capability
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
