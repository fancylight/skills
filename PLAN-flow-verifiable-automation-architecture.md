# Flow 可验证自动化架构改进方案

> **实施入口**：不要从本文直接开始修改代码。先读取
> [`PLAN-flow-verifiable-automation-implementation.md`](./PLAN-flow-verifiable-automation-implementation.md)，
> 按其中 Work Package 的依赖顺序一次只实施一个包。本文只解释总体架构和取舍。

## 1. 背景

当前 Flow 已具有设计、审核、实现、测试和归档等完整阶段，也在 skills 中声明了仓库边界、授权上限、revision、审核轮次和失败停止规则。但这些规则主要以自然语言存在，由 agent 自行解释和执行。

当根 agent 使用持续目标驱动完整流程时，一次错误判断可能扩张为重复派发、重复审核、重复运行、跨仓修改、配置来源切换或工具链改造。每一步表面上都有新产物，实际却不一定更接近业务验收完成。

本方案的目标不是禁止长期目标或降低自动化程度，而是把 Flow 从“由 agent 阅读的流程说明”改造成“由确定性控制器约束、由 agent 执行有限动作”的可验证自动化系统。

## 2. 核心问题

### 2.1 软门禁不能保证安全

Skill 中的 `MUST`、`禁止` 和 `不得` 只能影响模型决策，不能阻止 agent 实际执行非法状态转换或越界写入。

### 2.2 缺少机器可判定的单调进展

现有流程能记录 revision 和审核状态，但不能可靠回答：

- 新一轮修改是否解决了已知失败；
- 失败集合是否缩小；
- 是否重复执行了相同 revision 和相同失败；
- 是否通过修改基线、审核身份或产物名称绕过旧结论；
- 是否改变了已冻结的 SUT、配置来源或测试平台。

### 2.3 同一契约存在多个手工副本

领域概念、验收场景、manifest、测试方法、runner filter、报告类和 evidence 清单之间主要依赖人工同步，导致 revision 漂移和验证循环。

### 2.4 平台缺陷与业务缺陷混在同一闭环

测试平台、runner、配置探针、fixture、业务断言和 SUT 行为共用一个失败出口。agent 可以把平台问题扩大为业务修改，也可以通过放宽断言掩盖业务问题。

## 3. 设计原则

1. **Agent 负责推理，控制器负责授权。** Agent 可以提出动作，但只有控制器可以批准状态转换和写入范围。
2. **状态单调前进。** 任何回退、重跑或新 revision 都必须引用可验证的失败指纹和修复范围。
3. **单一事实源。** 领域事实和测试场景分别只有一个权威结构化来源；派生产物由工具生成或校验。
4. **业务基线不可变。** 进入测试设计后，SUT revision、工作区和配置所有权被冻结；改变基线必须形成显式新流程输入。
5. **失败按责任路由。** 配置、测试平台、fixture/断言、数据契约和业务行为进入不同修复通道。
6. **长期目标只调度合法动作。** goal 可以持续请求 `next`，但不能直接决定跨阶段、跨仓写入或重复运行。
7. **确定性规则优先脚本化。** 路径、revision、状态、计数、映射和失败指纹不得依赖 LLM 自觉遵守。

## 4. 目标架构

```text
User / Goal
    |
    | 请求推进最终目标
    v
Flow Controller
    |- 读取 machine state
    |- 校验 transition guard
    |- 签发阶段租约
    |- 验收结构化结果
    |- 计算唯一合法 next
    v
Stage Agent / Deterministic Script
    |- 只读取租约允许的输入
    |- 只修改租约允许的路径
    |- 返回结果与证据
    v
Verifier
    |- 独立只读判断
    |- 不提升授权
    v
Flow Controller 更新状态或 BLOCKED
```

### 4.1 三类权威数据

| 数据 | 权威来源 | 禁止事项 |
|---|---|---|
| 领域事实 | `domain-model.md` 或后续结构化等价物 | 不得从概要设计反推领域事实 |
| 流程状态 | 控制器维护的 machine state | agent 不得手工声明 PASS 或修改 phase |
| 测试场景 | `test-cases.yaml` | manifest、Java、evidence 不得各自维护独立场景清单 |

### 4.2 Machine state 示例

```yaml
schemaVersion: 1
changeName: example-change
phase: IMPLEMENTATION_VERIFIED
domainRevision: sha256:...
designRevision: sha256:...
sut:
  repository: <sut-repository>
  branch: feature/example
  revision: abcdef1
systemTest:
  repository: <system-test-repository>
  revision: 1234567
harness:
  version: 3
  certification: PASS
configuration:
  sourceFingerprint: sha256:...
  ownership: human
lastFailure: null
allowedNext:
  - VERIFY_ENVIRONMENT
```

Machine state 不保存密码、token 或完整连接串。

## 5. 生命周期

### 5.1 业务设计

```text
DOMAIN_DRAFT
→ DOMAIN_VERIFIED
→ SOLUTION_DRAFT
→ SOLUTION_VERIFIED
→ ASSIGNED
→ IMPLEMENTED
→ REVIEWED
→ UNIT_TESTED
→ BUSINESS_REPORTED
```

### 5.2 集成测试

```text
TEST_DESIGN_DRAFT
→ TEST_DESIGN_VERIFIED
→ TEST_IMPLEMENTED
→ TEST_IMPLEMENTATION_VERIFIED
→ TEST_ENVIRONMENT_VERIFIED
→ TEST_EXECUTED_PASS | TEST_EXECUTED_FAIL
→ TEST_RESULT_VERIFIED
```

每条转换由控制器登记：输入 fingerprint、允许写入路径、执行者租约、输出 artifact 和 verifier 结论。

## 6. Skills 分工调整

### 6.1 保持公开入口稳定

初期保留现有 `flow-codex-*` 名称，避免一次性破坏调用方；skills 内部改为调用控制器。

| Skill | 调整方向 |
|---|---|
| `flow-codex-design` | 分为领域发现和方案设计两个受控阶段 |
| `flow-codex-verify` | 增加 domain truth gate；design gate 只校验方案消费与传导 |
| `flow-codex-assign/receive/apply/report` | 使用控制器签发的仓库与路径租约 |
| `flow-codex-test-design` | 生成测试架构与唯一场景源，不复制运行结果 |
| `flow-codex-test-verify` | 验证设计、实现和结果，但不能改变 phase |
| `flow-codex-test` | 只请求控制器执行合法的 runner transition |
| `flow-codex-system-test` | 运行经过认证的 harness，输出结构化结果和失败指纹 |

后续可将 assign/receive 收敛为控制器内部动作，但不作为首轮改造前置条件。

### 6.2 控制器建议位置

确定性脚本放在共享源：

```text
flow/templates/system-test/scripts/
codex/scripts/
flow/docs/schema.md
```

安装时复制到 `flow-codex-core/assets/scripts/`。不得在安装副本中直接维护源代码。

## 7. 实施阶段

### Phase 0：冻结协议与建立回放基线

- 汇总现有授权、范围、生命周期、配置、失败报告等 PLAN 文档；
- 选取已经发生过的越界与循环事件，形成不包含具体业务数据的通用事故夹具；
- 记录当前 skills 在这些夹具上的实际行为，作为对照基线。

### Phase 1：领域真实性门禁

- 实现 `DOMAIN_DRAFT → DOMAIN_VERIFIED`；
- 新增领域事实模板和检查清单；
- 将方案设计改为只消费已验证领域事实。

详细方案见 `PLAN-domain-discovery-and-design-truth-gate.md`。

### Phase 2：最小控制器

- 实现状态 schema、transition guard、revision lock、路径租约和结构化结果；
- 先覆盖测试设计到 runner 的链路；
- skills 仍负责内容推理，但不能越过控制器。

### Phase 3：单一测试场景源与 harness 认证

- 引入 `test-cases.yaml`；
- 自动生成/校验 manifest、方法映射和 evidence 清单；
- 建立 runner self-test 与版本认证。

详细方案见 `PLAN-system-test-controller-and-validation.md`。

### Phase 4：Goal 自动化

- goal 只调用控制器的 `status/next/accept-result`；
- 在隔离仓完成故障注入和耐久验证；
- 所有事故回放通过后，才允许用于真实业务需求。

## 8. 与既有计划的关系

本方案不否定已有单点计划，而是提供统一架构：

- 授权和范围门禁转为 controller lease；
- 生命周期门禁转为 machine state transition；
- 配置停止规则转为 environment ownership route；
- 失败报告转为 failure fingerprint 和责任路由输入；
- readiness 不再是独立凭据，而是对应阶段的确定性 guard。

实施前应逐份建立“旧规则 → 新控制器规则”的迁移矩阵，避免同时存在两个互相矛盾的权威来源。

## 9. 非目标

- 不让 LLM 自动修改人工所有的密码、网络或基础设施配置；
- 不要求领域发现覆盖整个业务系统，只覆盖本 change 改变或依赖的决策点；
- 不保证所有失败都能自动修复；无法可靠归因时必须升级为人工决策；
- 不用更多 Markdown 门禁替代可执行控制器；
- 不在首轮改造中删除全部现有公开 skills。

## 10. 总体验收

- 非法状态转换拦截率 100%；
- 非授权仓库和路径写入拦截率 100%；
- agent 不能手工提升授权、修改 phase 或重置审核结论；
- 相同 revision 与相同失败指纹不能重复执行；
- 领域事实具有独立证据，方案和子 spec 能追溯到事实 ID；
- 测试场景只有一个权威定义，派生清单无人工漂移；
- goal 只能执行 controller 返回的动作；
- 最终完成状态只能由最后一个 verifier PASS 的合法转换产生。

## 11. 决策门禁

本计划完成不等于架构可用。只有以下条件同时满足后，才允许真实业务 goal 使用新流程：

1. 控制器单元测试和非法转换测试全部通过；
2. 通用事故回放全部在首次非法动作处停止；
3. 三类隔离 forward test 通过；
4. shadow 模式与人工判断一致；
5. goal 故障注入测试未发生重复执行、范围扩张或错误完成。
