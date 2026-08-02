# Flow Schema 规范

> 本文档定义 Flow Skill 涉及的配置文件和数据格式的完整规范。
> 所有字段类型使用 YAML/JSON 约定：string / boolean / integer / array / object。

---

## 1. config.yaml

### 1.1 根 Agent 配置（`role: orchestrator`）

由 `/flow:init` 生成，位于项目根目录 `.flow/config.yaml`。

```yaml
project:
  name: string              # 必填。项目名称
  role: "orchestrator"      # 必填。固定值
  created: string           # 必填。ISO-8601 日期（如 2026-04-22）

services:                   # 必填。非空数组
  - name: string            # 必填。服务标识符（kebab-case 推荐）
    path: string            # 必填。相对根目录的路径
    type: string            # 可选。服务类型：bff / data-service / admin / gateway / ...
    description: string     # 可选。一句话职责
    flow_initialized: boolean  # 必填。该服务是否已完成 flow:init
    flow_initialized_at: string  # 可选。初始化日期（YYYY-MM-DD）

knowledge_base:
  enabled: boolean          # 必填。默认 false
  path: string              # enabled=true 时必填。知识库根路径（绝对路径）
  overview: string          # 可选。知识库概要说明文档路径（绝对路径），描述 KB 结构、内容概要
  maintenance_guide: string # 可选。知识库维护指南文档路径（绝对路径）
  child_write: boolean      # 必填。默认 true
  review_on_archive: boolean # 必填。默认 true

conventions:
  task_id_prefix: string    # 可选。如 "GLW"，留空则不使用任务号
  branch_pattern: string    # 必填。默认 "feature/<kebab-case>"
  commit_format: string     # 必填。默认 "{type}: {description}"
                            # 如有前缀："{prefix}-{id} {type}: {description}"

child_agent:
  spec_tool: string         # 可选。子 agent 使用的 spec 工具标识
  onboarding_doc: string    # 必填。默认 ".flow/onboarding.md"
```

### 1.2 子 Agent 配置（`role: executor`）

由 `/flow:init` 生成，位于各服务目录 `.flow/config.yaml`。

```yaml
project:
  name: string              # 必填。项目名称
  role: "executor"          # 必填。固定值
  root_path: string         # 必填。从服务目录到项目根目录的相对路径
  service_name: string      # 必填。当前服务名

knowledge_base:
  enabled: boolean          # 必填。
  path: string              # enabled=true 时必填
  overview: string          # 可选。从根 config 继承
  maintenance_guide: string # 可选。从根 config 继承
  child_write: boolean      # 必填。

conventions:
  task_id_prefix: string    # 可选。
  branch_pattern: string    # 必填。
  commit_format: string     # 必填。

child_agent:
  spec_tool: string         # 可选。
  onboarding_doc: string    # 必填。指向根目录 onboarding.md

inline_agents:
  review:
    enabled: boolean        # 必填。默认 true
    knowledge_base_rules_path: string  # 可选。知识库中审核规范路径
  unit_test:
    enabled: boolean        # 必填。默认 true
    test_command: string    # 必填（若 enabled=true）。如 "mvn test"
  knowledge_maintenance:
    enabled: boolean        # 必填。默认 true
    auto_trigger: boolean   # 必填。默认 false
```

---

## 2. tasks.md 元数据头

位于 `.flow/changes/{change-name}/tasks.md`，Markdown YAML frontmatter。

```yaml
---
requirement: string         # 必填。需求标题
type: string                # 必填。枚举：feature / hotfix / refactor
status: string              # 必填。枚举：planning / in_progress / completed / archived
tier: integer               # 必填。1 / 2 / 3
branch: string              # 必填。完整分支名
services: array[string]     # 必填。涉及的服务名列表
created: string             # 必填。ISO-8601 日期
updated: string             # 必填。ISO-8601 日期
archived: string            # 可选。归档时填写
---
```

### 正文格式

```markdown
## 开发顺序

1. {service} — {原因}
2. {service} — {原因}

---

## {service-name}
> child agent change: `{change-name 或 待创建}`
> blocked by: [{service}] {接口描述}   # 可选

- [ ] {任务描述}
- [x] {已完成任务描述}
```

---

## 3. api.md（提供者接口文档）

由子 agent 在开发完成后生成，位于子服务 spec 工作区。

```markdown
---
service: string             # 必填。服务名
change: string              # 必填。关联的 change 名
version: string             # 可选。接口版本，如 "1.0.0"
updated: string             # 必填。ISO-8601 日期
---

# {service} 接口变更

## 新增接口

| 序号 | Method | Path | 描述 | 状态 |
|------|--------|------|------|------|
| 1 | POST | /api/v1/users | 创建用户 | 已实现 |

## 修改接口

| 序号 | Method | Path | 变更内容 | 状态 |
|------|--------|------|----------|------|
| 1 | GET | /api/v1/users/{id} | 响应新增 `email` 字段 | 已实现 |

## 废弃接口

| 序号 | Method | Path | 替代方案 | 计划移除日期 |
|------|--------|------|----------|-------------|

## 详细定义

### POST /api/v1/users

**请求**
```json
{
  "name": "string",
  "email": "string"
}
```

**响应 200**
```json
{
  "id": "string",
  "name": "string",
  "email": "string"
}
```

**异常**
| 状态码 | 场景 | 响应体 |
|--------|------|--------|
| 400 | 参数校验失败 | `{ "error": "string" }` |
| 409 | 用户已存在 | `{ "error": "string" }` |
```

---

## 4. {consumer}-api.md（消费者期望接口文档）

由消费者服务生成，描述期望上游提供的接口。

```markdown
---
consumer: string            # 必填。消费者服务名
provider: string            # 必填。提供者服务名
change: string              # 必填。关联的 change 名
updated: string             # 必填。ISO-8601 日期
---

# {consumer} 对 {provider} 的接口期望

## 期望接口

| 序号 | Method | Path | 用途 | 优先级 |
|------|--------|------|------|--------|
| 1 | GET | /api/v1/permissions/{userId} | 查询用户权限 | 必须 |

## 详细定义

### GET /api/v1/permissions/{userId}

**请求参数**
| 参数 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| userId | path | string | 是 | 用户 ID |

**响应 200（期望）**
```json
{
  "userId": "string",
  "permissions": ["string"]
}
```

**约束**
- 响应时间 < 100ms
- 必须支持批量查询（未来扩展）
```

---

## 5. proposal.md

位于 `.flow/changes/{change-name}/proposal.md`。

```markdown
# {需求标题}

## 背景
{为什么要做这个需求}

## 目标
{要达到什么效果}

## 涉及服务
| 服务 | 职责 | 依赖 |
|------|------|------|
| {name} | {responsibility} | {depends_on} |

## 开发顺序
1. {service-a}（无依赖，先开发）
2. {service-b}（依赖 service-a 的接口）

## 接口契约
{跨服务 API 定义}

## 分支策略
分支：{branch-pattern}/{change-name}

## 非目标
{明确不做的事项}
```

---

## 6. report 汇报结构

由 `/flow:report` 生成，纯文本结构化格式。

```markdown
【归档汇报】
服务：{service_name}
Change：{change_name}
功能：{summary}
Commit：{commit_id}

【测试验证】
单元测试：✅ 通过（X/X）/ ❌ 失败（详情见下）
集成测试：⏳ 待根 agent 触发 /flow:test

【接口变更】（如有）
- 新增：{METHOD} {path}（见 api.md）
- 修改：{METHOD} {path}（见 api.md）
- 废弃：{METHOD} {path}（替代方案：{alternative}）

【知识库更新】（如有）
- {path} — {description}

【遗留问题】（如有）
- {问题描述}
```

---

## 7. fix.md（hotfix 专用）

由 `/flow:hotfix` 生成，位于 spec 工作区 `changes/hotfix-{YYYYMMDD}-{slug}/fix.md`。

```yaml
---
type: hotfix
status: in_progress / completed
service: string             # 必填。受影响的主要服务
created: string             # 必填。YYYY-MM-DD
updated: string             # 必填。YYYY-MM-DD
---

## Bug 描述
{用户输入}

## 复现步骤
{待填写}

## 根因分析
{待填写}

## 修复方案
{待填写}
```

---

## 8. 工作流程.md（子 agent 持久化）

由 `/flow:init`（子模式）生成，位于服务目录 `.flow/工作流程.md`。

内容：服务基本信息 + 三阶段工作循环说明（阶段一设计 → 阶段二编码 → 阶段三汇报）。

---

## 9. 领域模型与概要设计

### 9.1 domain-model.md

由 `flow-codex-design` 的根模式领域发现阶段创建，位于
`.flow/changes/{change-name}/domain-model.md`。它记录本 change 的领域事实，而不是技术方案。

首次设计动作只创建该产物并返回 `DOMAIN_DRAFT`。`DOMAIN_DRAFT` 不是 verifier PASS，不能作为
创建 `概要设计.md`、OpenSpec、`task.md` 或发版产物的依据；后续 `DOMAIN_VERIFIED` 的验证行为由
独立 domain verify 定义。

必备结构：变更决策点、领域实体与关系、领域事实、表与字段语义、身份/唯一性/聚合/覆盖规则、
状态与转换、输入/存储/输出转换、正例/边界/反例、证据索引、冲突与未决问题，以及 DOMAIN_DRAFT
检查点。

领域事实表至少包含：

| 字段 | 要求 |
|---|---|
| `Fact ID` | 在一个 change 内稳定且唯一，格式推荐 `DF-<number>` |
| 概念与精确定义 | 可据事实判断，不能只是名词解释 |
| 生效条件 | 写明规则何时适用 |
| 不生效条件/反例 | 写明规则何时不适用或禁止的泛化 |
| 证据 | 只允许引用证据索引中的 `EV-<number>`；等级、来源和定位仅由证据索引定义，不得仅引用当前概要设计、实现设想或 agent 推断 |
| 影响 Decision ID | 指向本 change 的实现决策点 |

证据索引是 Evidence ID、等级、来源和定位的唯一权威。证据等级：E1（用户明确裁决、已批准需求、权威 KB）
和 E2（当前代码、数据库约束、接口定义、稳定历史 change）可作为事实依据；E3（脱敏样例、日志、已有测试）
只能辅助；E4（命名、注释、agent 推断）只能形成待确认问题，且不得进入事实表。影响实现的证据冲突必须保留为未决问题。

`flow-codex-verify verify_mode=domain` 对该产物执行只读验证。它先运行领域 artifact validator，
再独立抽查高风险事实的代码/schema/契约证据；无 ERROR 时输出 `DOMAIN_VERIFY_RESULT PASS`、
`phase: DOMAIN_VERIFIED` 和 `domain_model_sha256`。该指纹是方案设计消费领域事实的前置条件；
领域模型任何变更都会使旧结论失效。

### 9.2 概要设计.md

由 `/flow:design`（根模式）生成，位于 `.flow/changes/{change-name}/概要设计.md`。只有独立
domain verify 已确认 `DOMAIN_VERIFIED` 后才可生成；概要设计消费 Fact ID，不得反向充当领域事实证据。

概要设计必须有「领域事实引用」表。每个被方案消费的 Fact ID 都要登记影响 Decision ID、消费位置、
正向要求和反例/禁止行为；业务规则、数据访问契约和验收项引用该 ID。子 OpenSpec 的 design 和
requirements 必须传导同一 Fact ID、实现分支、正向要求、反例/禁止行为和单元测试责任。

必须章节：
- 背景
- 目标
- 涉及服务
- 开发顺序
- 接口契约草稿
- **验收标准**（集成测试依据，必须）
- 非目标
- 变更记录（如有变更）

---

## 10. 开发文档.md

由 `flow-codex-design` / `/flow:design`（根模式）创建骨架，由 `flow-codex-report` / `/flow:report` 按实现回写，位于 `.flow/changes/{change-name}/开发文档.md`。

**读者**：开发、测试、运维、发版（**非** Agent 编排文档）。

### 10.1 必须章节

- §1 需求文档（链接；用户自维护）
- §2 需求分析（表格，见模板）
- §3.2.1 业务规则
- §3.2.2 存储与数据（字段语义；完整 SQL 在 §4.2）
- §3.2.3 数据流转（服务/接口路径级）
- §3.2.4 接口设计（Apifox 索引表；服务列 = 可部署单元）
- §4.1 服务-分支（可部署/运行单元，非 git 仓库名）
- §4.2 SQL、配置（DDL/SQL 直接写在本节；无则「无」）
- §4.3 测试与验收（业务验收语义）

### 10.2 可选章节

- §3.1 前端：模块/页面级影响，**禁止**文件路径清单

### 10.3 权威边界

| 内容 | 权威来源 |
|------|----------|
| 接口字段与 JSON 示例 | Apifox |
| 实现类/文件级设计 | 服务 OpenSpec `design.md`（勿写入开发文档） |
| spec 拆分、编排向验收、c7 测试 | `概要设计.md` |
| 发版侧 DDL/配置登记 | `发版记录.md`（可与 §4.2 语义一致；开发文档 §4.2 须自包含） |
| 上线用 SQL/配置（给人读） | 开发文档 §4.2 |
| 业务验收要点（给人测） | 开发文档 §4.3 |
| spec 完成勾选 | `task.md`（仅 report 写入） |

### 10.4 禁止内容

- spec 名（`c{n}-*`）、`$flow-codex-*`、Flow 测试分层、审核返修记录、commit hash
- 本地相对路径；以「详见发版记录 / openspec / 概要设计」代替正文
- Java 类名/方法名堆砌、.vue/.js 文件改动表
- §3.2.4 中的完整 JSON 响应/请求体
- §4.1 用 git 仓库名冒充可部署服务
- §4.3 写成测试类名、本机地址或本地启动说明
- 照搬概要设计的开发顺序与验收标准全文

详细规则见模板目录 `dev-doc-maintenance.md`。

---

## 11. 集成测试生命周期

集成测试设计、执行配置和证据分别位于 system-test 仓的
`changes/{change}/test-design.md`、`test-plan.md`、`manifest.yaml` 和 `evidence/`；根
`.flow/changes/{change}/集成测试.md` 仅镜像执行结果。

| 状态 | 语义 | 不能替代 |
|---|---|---|
| `TEST_DESIGN_RESULT READY` | 设计产物者认为完成 | `TEST_VERIFY_RESULT design PASS` |
| `TEST_VERIFY_RESULT design PASS` | 设计可派发 | 测试代码实现 |
| `TEST_VERIFY_RESULT implementation PASS` | review/report/revision 可复现 | runner 结果 |
| `SYSTEM_TEST_RESULT PASS` | 一次指定 revision 的 runner 成功 | 完整 Flow 完成 |
| `TEST_VERIFY_RESULT result PASS` | 运行证据、revision 和验收一致 | 业务 release verify |
| `INTEGRATION_TEST_RESULT PASS` | 完整集成测试 Flow 完成 | archive |

`test-design.md` 必须说明 SUT revision、拓扑、真实/桩边界、数据/观测/覆盖/SQL/失败归因；
`test-plan.md` 必须将概要设计 AC 映射到场景、方法、准备、步骤和断言。`manifest.yaml` 仅承载运行配置。

### 11.1 授权与不可重置状态

根 change 的集成测试状态必须记录在 system-test change 的 `manifest.yaml`（等价 YAML）中；测试设计、审核和
执行流程不得为记录授权而修改根 `task.md` 或业务 progress：

```yaml
testAuthorization:
  ceiling: design | implementation | execution | result
  grantedBy: user
  grantedAt: string
reviewIdentity: "<change_name>/<spec_id>/<design_fingerprint>"
reviewRejectRounds: integer
capabilityFingerprint:
  sandboxMode: string
  approvalPolicy: string
  dockerAvailable: boolean
  networkAvailable: boolean
```

`ceiling` 默认 `design`，只能由用户明确要求提升。baseline、SUT revision、branch、executor 或 reviewer 改变会使当前
验证失效，但不得清零 `reviewRejectRounds`。外部证据缺失以 `[TEST_EXTERNAL_EVIDENCE] BLOCKED` 记录 owning repo、anchor
和 required assertion；当前测试 Flow 不得自动修改该仓。

### 11.2 配置契约与 runner 前置

`manifest.yaml` 在 design 时必须声明 `configurationSource`、`requiredEndpoints`、`connectivityProbe` 和 `ownership`；
来源必须由用户确认，probe 只能为单次最小只读连接或 metadata 检查。失败输出 `[TEST_CONFIGURATION] BLOCKED` 与
`STOP_AWAIT_HUMAN_CONFIGURATION`，不得自行修配置、切换来源或继续实现。

manifest 还须记录 `requiredEnvBySuite`、`environmentContract`、`wireMockContracts`、`fixtureSchema`、
`requiredScenarioCount`、`expectedTestMethodCount`、`expectedReportClasses`、`runner.command`（token array）、
`integrationDecisions`、`excelAssertions` 和 `implementationVerification`。implementation PASS、execution 授权、配置契约
及 probe 证据一致时，才可进入唯一 runner；runner PASS 不代表 result PASS 或 Flow 完成。

### 11.3 失败归因证据

manifest 必须声明 `failureObservability`，将 required 场景映射到稳定场景 ID、测试类/方法、关联字段、原始报告及日志/桩/数据库证据路径。
runner 无论 PASS 或 FAIL 都生成 `evidence/current/index.md`；FAIL 还生成 `failure-report.md`，逐项记录分类、确定性、首个证据和建议动作。
分类限于 `CONFIG_INFRA`、`TEST_HARNESS`、`DATA_SCHEMA_CONTRACT`、`SUT_BUSINESS`、`UNDETERMINED`。证据不足只能为
`UNDETERMINED`；只有 confirmed 的 `SUT_BUSINESS` 可作为独立业务 Flow 输入。当前 revision 不得重跑，修复或诊断增强后必须
形成新 revision 并重新经过 implementation verify。

### 11.4 automation-state.yaml（WP3 controller state）

根 `.flow/changes/{change}/automation-state.yaml` 是集成测试 machine state 的唯一权威。首版由
`flow-test-controller.ps1` 原子写入；它使用 JSON 兼容的 YAML 子集，不保存密码、token、完整连接串或其他 secret。

```yaml
schemaVersion: 1
changeName: string
phase: TEST_DESIGN_DRAFT | TEST_DESIGN_VERIFIED | TEST_IMPLEMENTING | TEST_IMPLEMENTED |
  TEST_IMPLEMENTATION_VERIFIED | TEST_ENVIRONMENT_VERIFIED | TEST_EXECUTING |
  TEST_EXECUTED_PASS | TEST_EXECUTED_FAIL | TEST_RESULT_VERIFIED | BLOCKED
authorization:
  maxPhase: design | implementation | execution | result
repositories:
  systemTest: canonical absolute path
  sut: canonical absolute path
revisions:
  designRevision: immutable design revision captured at initialize
  testBaseRevision: immutable test revision captured at initialize
  testBaseline: compatibility alias for the initial test base revision
  test: current accepted system-test implementation revision; updated only by accept-result
  sut: immutable SUT revision
  harness: immutable harness revision
configurationFingerprint: string
leases: array # implementation lease records implementationBaseRevision at issue time; accept scopes base -> proposed HEAD
runs: array
failureFingerprints: array[string]
activeRun: object | null       # TEST_EXECUTING 的唯一已持久化 runner；启动前按 test revision 去重
scopeVerification: object | null # trusted scope PASS and controller-computed implementation-base-to-proposed diff
verifier: object | null
history: array
integrityHash: sha256
```

lease 对象必须绑定 agent、role、过期时间、canonical repository、authorized paths、allowed/forbidden capabilities；
verifier 对象必须绑定 identity、mode、test/SUT/harness revision、configuration fingerprint 和报告 `summaryHash`；
不得把 verifier summary 原文写入 state。
所有写状态动作必须提交并校验当前 test/SUT/harness revision 与 configuration fingerprint；controller 同时读取
canonical system-test/SUT Git HEAD，不能由省略参数或调用方报告绕过锁定。
控制器拒绝非法 phase transition、revision 或 configuration fingerprint 漂移、非 canonical repository/path、
过期或跨 agent lease、未授权 capability、旧 revision verifier、同一 test revision 的第二次 runner，以及重复
failure fingerprint。runner 开始和 runner 结果是两个动作：前者先原子持久化 `TEST_EXECUTING`，后者只能消费
该 activeRun 的完整 revision/configuration/evidence。
state 的 `integrityHash` 用于检测手工篡改或半写入；每次成功替换后保留同 revision 的校验备份，主文件损坏时
只恢复该最后有效副本；主文件与备份同时损坏则拒绝继续，绝不推断下一阶段。

### 11.5 test-cases.yaml（WP4 canonical scenario source）

`changes/{change}/test-cases.yaml` 是 system-test 场景的唯一可执行来源；`test-plan.md` 只能承载背景、边界和
人工说明，不得维护第二份场景计数或可执行映射。文件使用 JSON-compatible YAML 子集，结构如下：

```yaml
schemaVersion: 1
changeName: string
sourceOfTruth: test-cases.yaml
scenarios:
  - id: AC-n-Sn
    acceptance: AC-n
    required: true | false
    suite: api | ui | cdc | other
    integration: Y | N
    testClass: fully.qualified.ClassName
    testMethod: stableMethodName
    reportClass: report.class.Name
    filter: stable-runner-filter
    evidence: [junit, service-log]
    externalEvidence: []
```

`id` 必须唯一且稳定；每个 Java 测试方法通过稳定 ID 注解绑定到一个场景，未知、重复、缺失或方法/类漂移均拒绝。
manifest 的 `requiredScenarioCount`、`expectedTestMethodCount`、`expectedReportClasses`、runner filters、evidence
映射和 `scenarioSourceSha256` 必须由该文件确定性生成或严格校验。required 场景删除前必须重新完成 design verify；
`integration: N` 场景必须声明外部证据，证据路径不存在或 source hash 漂移均不得进入 implementation/result verify。

## 12. feedback（线上反馈，独立于 change）

由 `/flow:feedback` 或 `flow-codex-feedback` 懒创建，位于 `.flow/feedback/`。**与 `.flow/changes/`、`task.md`、OpenSpec spec 无关联**；禁止写入 task.md 或创建 spec 目录。

### 11.1 目录布局

```text
.flow/feedback/
  _index.md
  {YYYY-MM-DD}-{slug}/
    反馈记录.md
    调查报告.md
```

- `feedback_id` = 目录名 = `{YYYY-MM-DD}-{slug}`（slug 为 kebab-case）
- 首次执行 feedback skill 时创建 `.flow/feedback/` 与 `_index.md`

### 11.2 `_index.md` 台账

表头列：`feedback_id` | `status` | `type` | `resolution` | 标题 | `updated`

Intake 时追加一行；关闭或状态变更时更新对应行。

### 11.3 反馈记录.md

由 Intake 写入，调查开始后**只读**（禁止后续步骤修改）。

```yaml
---
feedback_id: string           # 必填。与目录名一致
received: string              # 必填。YYYY-MM-DD
reporter: string              # 可选。客户/渠道/内部
environment: string           # 可选。public | private
tenant: string                # 可选。私有云客户名
contact: string               # 可选
severity: string              # 可选。P0 | P1 | P2 | unknown
related_services: array       # 可选。初步猜测
duplicate_of: string          # 可选。重复反馈时填原 feedback_id
related_change: string        # 可选。仅背景参考，不挂靠
---
```

正文必须章节：问题描述、复现材料、补充。

**最小可接受输入**：问题描述 +（接口路径 或 业务主键 之一）。

模板源：`flow/templates/feedback-record.md.tmpl`

### 11.4 调查报告.md

Frontmatter 为**唯一状态源**；正文不重复枚举 type/resolution/remediation。

```yaml
---
feedback_id: string           # 必填
status: string                # 必填。investigating | confirmed | closed
type: string                  # 问题性质：bug | data-issue | by-design | unknown
resolution: string            # 收尾路径：fix-now | fix-later | data-fix | kb-only | close | pending
remediation: string           # 修复形态：pending | data-fix | code-fix | none
services: array[string]       # 调查后确认的服务名
created: string               # 必填。YYYY-MM-DD
updated: string               # 必填。YYYY-MM-DD
closed: string                # status=closed 时必填
fix_service: string           # resolution=fix-now 时
fix_commit: string            # 直接修复完成后
fix_branch: string
kb_ref: string                # flow-codex-kb / flow:kb 写入后（可选；data-fix 不强制）
---
```

正文必须章节：反馈场景、相关链路、数据验证、根因、判定摘要、建议分流、数据修复说明、修复记录、调查日志。

**字段正交**：`type` = 问题性质；`resolution` = 收尾路径；`remediation` = 修复形态（如 `data-fix`↔`data-fix`，`fix-now`↔`code-fix`）。

**状态机**：`investigating` → `confirmed` → `closed`

- `type=unknown` 仅允许 `status=investigating`
- `closed` 条件（满足其一）：`resolution=data-fix` 且修复说明已交付并经用户确认执行/不执行；或 `fix_commit` 已填；或 `kb_ref` 已填；或 `resolution=close` 且理由已写

**修复路径**：

- `resolution=fix-now`：在服务仓库**直接改代码并 commit**，不走 `flow:hotfix` / assign / apply；回填「修复记录」与 `fix_commit`
- `resolution=data-fix`：填「数据修复说明」（修改内容 / 根本原因 / 影响范围 + 预览/修正/验证 SQL）；由用户/工单执行，skill **不**自动写库

**Discover**（Intake 后）：查已有 feedback、KB 选篇、CDP playbook（`{root}/.flow/cdp/`）；规范见 `flow-codex-feedback/references/cdp.md`，产物不进 `local_rag`。

模板源：`flow/templates/feedback-report.md.tmpl`；CDP playbook 模板：`flow/templates/cdp-playbook.md.tmpl`

### 11.5 与 hotfix / change 的关系

| 体系 | 路径 | 关系 |
|------|------|------|
| feature change | `.flow/changes/{change}/` | **无关联** |
| hotfix 编排 | task.md `### Hotfix` + OpenSpec | feedback 默认**不经过** |
| feedback | `.flow/feedback/{id}/` | 独立事件流 |

KB 沉淀：`flow-codex-kb feedback/{id}` 或 `/flow:kb feedback/{id}`，读取调查报告写入知识库。

模板源（index）：`flow/templates/feedback-index.md.tmpl`

