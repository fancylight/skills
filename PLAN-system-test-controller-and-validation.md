# 集成测试可执行控制器、Goal 编排与验证方案

> **实施入口**：本文是测试控制器参考，不是任务清单。执行 agent 必须先读取
> [`PLAN-flow-verifiable-automation-implementation.md`](./PLAN-flow-verifiable-automation-implementation.md)，
> 仅在处理 WP3–WP7 时读取本文全文。

## 1. 背景

现有集成测试 Flow 已声明设计、实现、环境、runner 和结果验证的顺序，也增加了授权 ceiling、配置来源、最小探针、revision 和失败报告。然而，这些约束主要由 agent 解释，无法阻止以下行为：

- 未通过门禁就启动服务或 runner；
- 在测试失败后修改业务仓或 skills；
- 为同一失败创建多个 revision、目录或 worktree；
- 手工维护的场景、方法、manifest 和 evidence 发生漂移；
- 把 runner 基础设施问题与业务行为放在同一修复循环；
- 持续目标将“还有问题”解释为无限授权的下一项工作。

本方案保留长期 goal 的自动化方向，但要求 goal 只能驱动确定性控制器，不得直接编排工程动作。

## 2. 目标

1. 将集成测试生命周期变成机器可执行的有限状态机。
2. 用 revision、租约和路径 guard 阻止跨阶段、跨仓和重复执行。
3. 用一个结构化场景源消除测试设计、实现和 evidence 的人工漂移。
4. 将通用 runner/harness 独立认证，业务 change 只实现业务场景。
5. 将每次失败生成稳定指纹，自动路由到唯一责任范围。
6. 支持 goal 长时间运行，但只有存在合法、可证明进展时才能继续。

## 3. 状态机

### 3.1 状态

```text
TEST_DESIGN_DRAFT
TEST_DESIGN_VERIFIED
TEST_IMPLEMENTING
TEST_IMPLEMENTED
TEST_IMPLEMENTATION_VERIFIED
TEST_ENVIRONMENT_VERIFIED
TEST_EXECUTING
TEST_EXECUTED_PASS
TEST_EXECUTED_FAIL
TEST_RESULT_VERIFIED
BLOCKED
```

### 3.2 合法转换

| From | To | 必需输入 | 允许动作 |
|---|---|---|---|
| TEST_DESIGN_DRAFT | TEST_DESIGN_VERIFIED | design verifier PASS | 只读验证 |
| TEST_DESIGN_VERIFIED | TEST_IMPLEMENTING | 有效实现租约 | 写测试仓授权路径 |
| TEST_IMPLEMENTING | TEST_IMPLEMENTED | 结构化实现报告、scope PASS | 提交或形成可恢复 revision |
| TEST_IMPLEMENTED | TEST_IMPLEMENTATION_VERIFIED | implementation verifier PASS | 只读、test-compile |
| TEST_IMPLEMENTATION_VERIFIED | TEST_ENVIRONMENT_VERIFIED | 配置 fingerprint 和最小探针 PASS | 只读连接/健康检查 |
| TEST_ENVIRONMENT_VERIFIED | TEST_EXECUTING | execution 授权、revision 未漂移 | 单次 runner |
| TEST_EXECUTING | TEST_EXECUTED_PASS | runner 原始报告 PASS | 收集 evidence |
| TEST_EXECUTING | TEST_EXECUTED_FAIL | runner 原始报告 FAIL/不可运行 | 归因和失败指纹 |
| TEST_EXECUTED_PASS | TEST_RESULT_VERIFIED | result verifier PASS | 更新最终状态 |

不存在的转换必须由控制器拒绝。`BLOCKED` 的恢复必须提供新的外部输入、配置 fingerprint 或绑定失败指纹的修复 revision。

## 4. 控制器职责

### 4.1 命令模型

```powershell
flow-test-controller.ps1 status
flow-test-controller.ps1 next
flow-test-controller.ps1 issue-lease -Role test-implementer
flow-test-controller.ps1 accept -Report implementation-result.json
flow-test-controller.ps1 verify-transition -To TEST_ENVIRONMENT_VERIFIED
flow-test-controller.ps1 record-run -Evidence evidence/current
flow-test-controller.ps1 classify-failure -Evidence evidence/current
```

### 4.2 控制器必须验证

- change、仓库、branch、HEAD 和配置 fingerprint；
- 当前 phase 和目标 phase；
- 用户授权 ceiling；
- agent 租约是否仍有效；
- 实际 diff 是否完全落在授权路径；
- SUT 是否保持冻结；
- 当前 test revision 是否已运行过；
- failure fingerprint 是否重复；
- verifier 结果是否来自当前 revision；
- harness 认证是否有效。

控制器不读取或保存 secret，只记录配置来源和脱敏 fingerprint。

## 5. Agent 租约

### 5.1 租约结构

```yaml
leaseId: uuid
role: test-implementer
changeName: example-change
phase: TEST_IMPLEMENTING
authorizedRepository: <system-test-repository-path>
authorizedPaths:
  - changes/example-change/**
  - backend-tests/src/test/**/example-change/**
forbiddenRepositories:
  - <sut-repository-path>
  - skills
allowedCapabilities:
  - read
  - write-test-artifact
  - test-compile
forbiddenCapabilities:
  - start-service
  - run-integration
  - modify-business
expectedOutput: implementation-result.json
```

### 5.2 租约规则

- 一个写阶段同一仓库只能有一个有效租约；
- agent 完成、失败或权限上下文改变后租约失效；
- 旧 agent 不得恢复并继续使用原租约；
- 控制器只接受结构化输出，不因 agent 口述“完成”改变状态；
- 超范围 diff 必须拒绝，不能由 reviewer waive。

## 6. 单一测试场景源

新增：

```text
changes/<change>/test-cases.yaml
```

### 6.1 示例结构

```yaml
schemaVersion: 1
scenarios:
  - id: AC-1-S1
    acceptance: AC-1
    required: true
    suite: api
    setup:
      fixtures: [project, worker]
    action:
      method: POST
      path: /example
    assertions:
      response: [success]
      database: [row-created]
      sideEffects: [none-unexpected]
    cleanup: [project, worker]
    observability:
      correlationField: X-Test-Scenario
      allowedEvidence: [junit, service-log, wiremock, database]
```

### 6.2 派生产物

由生成器或静态校验器维护：

- `test-plan.md` 场景矩阵；
- manifest 的 Y/N 映射；
- required scenario count；
- expected test method count；
- runner filter；
- expected report classes；
- evidence index 骨架；
- failure observability 映射。

测试方法通过注解或命名约定绑定场景 ID。重复、缺失或未知 ID 在 implementation verify 阶段失败。

## 7. Harness 认证

### 7.1 平台能力

通用 harness 负责：

- 配置加载和脱敏；
- 服务和 WireMock 生命周期；
- MySQL、PostgreSQL、Redis 连接；
- seed、cleanup 和 zero baseline；
- Maven/Gradle/Playwright 参数调用；
- 原始测试报告收集；
- 日志、桩、数据库 evidence；
- failure report 和 cleanup 结果。

### 7.2 Self-test

system-test 仓必须提供不依赖具体业务 change 的 self-test：

- 正常启动、执行和清理；
- 服务启动失败；
- 参数中含空格、引号和 `-D`；
- Surefire 未生成；
- fixture seed 失败；
- cleanup 失败；
- WireMock unmatched；
- evidence 文件缺失；
- UTF-8/中文日志；
- 中途终止后的状态恢复。

认证结果绑定 harness revision。业务 change 只引用已认证 revision，不在需求执行中修改 harness；必须修改时进入独立平台 change 并重新认证。

## 8. 环境认证

环境认证由 manifest 声明，控制器执行，不允许 agent 自由寻找替代配置。

```yaml
configuration:
  source: .env.local
  ownership: human
  requiredEndpoints:
    - mysql
    - postgres
    - redis
    - wiremock
    - sut
  probes:
    mysql: SELECT 1
    postgres: SELECT 1
    redis: PING
    wiremock: GET /__admin/mappings
    sut: GET /actuator/health
```

路由规则：

- `ownership=human`：失败后 BLOCKED，等待新的配置 fingerprint；
- `ownership=harness`：转入独立平台修复；
- 禁止猜测密码、扫描其他配置文件、修改本地私有配置或创建替代环境。

## 9. 失败指纹与单调进展

### 9.1 指纹

```text
fingerprint = hash(
  phase,
  sutRevision,
  testRevision,
  scenarioId,
  failureCategory,
  normalizedFirstEvidence
)
```

### 9.2 继续条件

失败后只有满足以下条件才能产生下一次执行：

1. 失败已有 confirmed 或明确 `UNDETERMINED` 分类；
2. 已确定责任仓和允许修改路径；
3. 新 revision 的 diff 只处理登记的失败；
4. 重新通过对应 implementation/environment 门禁；
5. 新 revision 未运行过；
6. 没有改变冻结的 SUT、配置所有权或 harness revision。

### 9.3 非单调进展

控制器在以下情况停止自动循环：

- 相同失败指纹再次出现；
- 修复 revision 与登记失败没有可追溯 diff；
- 失败集合没有减少且新增无关失败；
- 测试问题修复触及业务仓；
- 业务问题通过删除场景、放宽断言或减少 required count 消失；
- 修改 harness 但没有新的平台认证。

这里不依赖固定时间或固定重试次数，而以“是否存在可证明的新进展”决定能否继续。

## 10. 失败责任路由

| 分类 | 责任范围 | 自动动作 | 禁止动作 |
|---|---|---|---|
| `CONFIG_INFRA` | 配置所有者 | harness 所有可走平台修复；人工所有则等待 | 猜配置、切换来源 |
| `TEST_HARNESS` | 测试平台仓 | 独立平台 change、自测、重新认证 | 在业务 change 中临时修 runner |
| `FIXTURE_ASSERTION` | 当前 system-test change | 签发测试修复租约 | 修改 SUT |
| `DATA_SCHEMA_CONTRACT` | 先确认权威 schema | 形成待裁决输入 | 直接判测试或业务错误 |
| `SUT_BUSINESS` | 业务 Flow | 生成业务缺陷输入 | 未授权直接修改业务代码 |
| `UNDETERMINED` | evidence | 只补缺失诊断一次 | 猜测归因并修改代码 |

## 11. Goal 编排协议

Goal 只允许以下循环：

```text
while true:
  state = controller.status()
  action = controller.next()

  if action == COMPLETE:
      finish
  if action == BLOCKED:
      report blocker and stop

  result = execute(action.lease)
  controller.accept(result)
```

Goal 不得直接调用任意后续 skill。所有 skill 入口首先读取 controller state；当前 phase 不匹配时必须拒绝。

## 12. Skills 改动面

| 组件 | 改动 |
|---|---|
| `flow-codex-core` | controller、state schema、lease、failure fingerprint、transition guard |
| `flow-codex-test-design` | 生成测试架构和 `test-cases.yaml` |
| `flow-codex-test-verify` | 消费控制器状态；验证当前 revision，不自行提升阶段 |
| `flow-codex-test-assign/receive/apply` | 使用实现租约和结构化返回 |
| `flow-codex-system-test` | 只运行认证 harness，输出机器结果 |
| `flow-codex-test` | 从自由编排器改为 controller 驱动器 |
| `flow/docs/schema.md` | state、lease、scenario、failure schema |
| `codex/validate.ps1` | schema、派生映射和 skill 引用校验 |

## 13. 验证方案

### 13.1 控制器单元测试

必须覆盖：

- 所有合法转换；
- 所有跨级转换；
- revision 漂移；
- 配置 fingerprint 漂移；
- 过期租约；
- 跨仓和越路径 diff；
- 手工篡改 phase；
- verifier 对象来自旧 revision；
- 相同 revision 重跑；
- 相同 failure fingerprint 重复；
- result evidence 不完整却申请完成。

### 13.2 Schema 和生成器测试

- `test-cases.yaml` 正反例；
- 场景 ID 重复和缺失；
- Java 方法映射缺失；
- manifest/report class/count 漂移；
- 已删除场景仍存在 evidence 要求；
- integration-N 缺外部证据；
- 敏感字段进入 state/evidence。

### 13.3 Harness self-test

覆盖第 7.2 的全部平台故障，并验证 cleanup 和 evidence 在失败路径同样可靠。

### 13.4 通用事故回放矩阵

| 事故动作 | 期望首次阻断位置 |
|---|---|
| design 阶段启动服务 | capability lease guard |
| implementation review 前运行 runner | phase transition guard |
| 测试 agent 修改业务仓 | repository scope guard |
| 恢复旧 agent | expired lease guard |
| 修改 SUT HEAD | immutable SUT guard |
| 新建第二测试目录 | canonical repository guard |
| 文件混入工具输出 | artifact parser |
| 相同失败重复运行 | failure fingerprint guard |
| 删除 required 场景以通过 | scenario source diff guard |
| 修改 harness 绕过业务失败 | harness certification guard |
| 配置不通后猜测其他来源 | ownership route guard |

事故回放必须验证系统在非法动作第一次发生时停止，而不是依赖后续 reviewer 发现。

### 13.5 Forward test

在隔离仓使用全新上下文 agent 执行：

1. 单服务同步 API；
2. 数据库加异步任务；
3. 多服务加外部 stub；
4. runner 平台故障；
5. 真实业务断言失败。

不得向 agent 泄露预期失败点。记录工具调用、状态转换、revision、失败指纹和是否越界。

### 13.6 Shadow 模式

控制器先只读运行，不阻止现有 Flow，输出：

- 当前推断状态；
- 唯一合法下一步；
- 当前动作是否会被拒绝；
- 拒绝原因和对应 guard。

与人工审核结果一致后才开启 enforcement。

### 13.7 Goal 故障注入

最后在隔离环境使用持续 goal，依次注入：

- 人工配置错误；
- WireMock 契约错误；
- fixture 错误；
- runner 报告缺失；
- SUT 业务失败；
- evidence 不足；
- agent 超范围写入。

验证 goal 能自动处理可修复问题，在人工所有或不可判定问题上停止，且不会重复同一失败、扩张范围或错误完成。

## 14. 验收指标

- 非法状态转换拦截率 100%；
- 非授权写入拦截率 100%；
- 相同 failure fingerprint 重复 runner 为 0；
- 手工维护的场景清单只有一个；
- 平台 self-test 未通过时业务 runner 无法启动；
- 测试问题不会触发业务仓修改；
- 业务失败不会通过降低 required count 或放宽断言消失；
- goal 每一轮都对应一个 controller transition 或明确 BLOCKED；
- 最终状态只能由当前 revision 的 result verifier PASS 产生。

## 15. 推进顺序

1. 先实现 state/transition/revision/scope 的最小控制器；
2. 用事故回放验证硬门禁；
3. 再实现单一场景源和派生校验；
4. 将 harness self-test 与业务 change 分离；
5. 运行 forward test 和 shadow mode；
6. 最后开启 goal 驱动，不允许跳过前述验证直接投入真实需求。
