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

flow:                       # 可选。控制面协议（见 flow/docs/control-plane.md）
  protocol_version: string  # 可选。枚举：legacy | lease-v1
                            # 缺省 = legacy（进行中 change 不中断）
                            # 新建 change 由 init/design 写入 lease-v1（Phase 1+）
  test_platform:            # 可选。集成测试环境 v2 的稳定入口（分阶段启用）
    system_test_service: string # services 中 type=system-test 的服务名
    default_environment: string # system-test 仓 config/environments/<id>.json 的默认 id
```

`protocol_version` 也可写在单个 change 的 `task.md` frontmatter（同名字段）；**change 级覆盖根 config**。apply 中途禁止自动改写。词法与租约握手见 [control-plane.md](./control-plane.md)。

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
protocol_version: string    # 可选。legacy | lease-v1；覆盖根 config.flow.protocol_version
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

初始用户授权记录在 system-test change 的 `manifest.yaml` 中；controller 初始化后有效授权与审计读取 automation-state 的 authorization.maxPhase/grants，追加授权仅用 grant-authorization（见 test-controller.md）。测试设计、审核和
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

`ceiling` 默认 `design`，已明确授权更高阶段时如实记录；stage=design 与授权上限相互独立。初始化后的追加授权不修改该初始快照，只能由用户明确要求并通过 controller 绑定版本的 grant-authorization 入账。baseline、SUT revision、branch、executor 或 reviewer 改变会使当前
验证失效，但不得清零 `reviewRejectRounds`。外部证据缺失以 `[TEST_EXTERNAL_EVIDENCE] BLOCKED` 记录 owning repo、anchor
和 required assertion；当前测试 Flow 不得自动修改该仓。

### 11.2 配置契约与 runner 前置

#### 11.2.1 当前 v1 runner 契约

`manifest.yaml` 在 design 时必须声明 `configurationSource`、`requiredEndpoints`、`connectivityProbe` 和 `ownership`；
来源必须由用户确认，probe 只能为单次最小只读连接或 metadata 检查。失败输出 `[TEST_CONFIGURATION] BLOCKED` 与
`STOP_AWAIT_HUMAN_CONFIGURATION`，不得自行修配置、切换来源或继续实现。

manifest 还须记录 `requiredEnvBySuite`、`environmentContract`、`wireMockContracts`、`fixtureSchema`、
`requiredScenarioCount`、`expectedTestMethodCount`、`expectedReportClasses`、`runner.command`（token array）、
`integrationDecisions`、`excelAssertions` 和 `implementationVerification`。implementation PASS、execution 授权、配置契约
及 probe 证据一致时，才可进入唯一 runner；runner PASS 不代表 result PASS 或 Flow 完成。

#### 11.2.2 测试环境 v2（P1 resolver 契约）

v2 将共享环境与 change 差异分开：

- system-test 仓 `config/environments/<id>.json` 是 repo 级 environment descriptor；
- `changes/<change>/manifest.yaml` 保持 JSON-compatible 内容，使用 `schemaVersion: 2`；
- `resolve-test-environment.ps1` 生成 `changes/<change>/resolved-manifest.json`；
- resolved manifest 是后续 design/environment/run/result 的唯一解析快照，但 P1 尚未切换现有 runner；
- v1 顶层字段与 v2 字段不得同时出现。P1 resolver 遇到旧字段返回 `AMBIGUOUS_CONFIGURATION_SCHEMA`，单向迁移在后续阶段实现。

根引用：

```yaml
flow:
  test_platform:
    system_test_service: string
    default_environment: string
```

Environment descriptor 使用 JSON：

```json
{
  "schemaVersion": 1,
  "id": "local",
  "configurationProvider": {
    "kind": "spring-config-native",
    "repository": "${ORCH_ROOT}/config-provider",
    "configurationRepository": "${ORCH_ROOT}/config-provider",
    "baseUri": "http://127.0.0.1:18888",
    "configRoot": "config",
    "serviceRef": "config-provider"
  },
  "resources": [
    {
      "id": "config-provider",
      "kind": "configuration-provider",
      "lifecycle": "managed",
      "executable": "powershell.exe",
      "arguments": ["-NoProfile", "-File", "scripts/start-native.ps1"],
      "workingDirectory": "${ORCH_ROOT}/config-provider",
      "port": 18888,
      "readinessProbe": "config-provider-health",
      "dependsOn": []
    }
  ],
  "probes": [
    {
      "id": "config-provider-health",
      "stage": "runtime",
      "kind": "http",
      "method": "GET",
      "url": "http://127.0.0.1:18888/actuator/health",
      "expectStatus": 200,
      "failureCategory": "CONFIG_INFRA"
    }
  ],
  "evidenceContracts": [
    {
      "id": "sample-sut-config-consumption",
      "kind": "log-regex",
      "pattern": "CONFIG_CONSUMED\\s+sample-sut/dev"
    }
  ]
}
```

`lifecycle` 只允许 `managed|external`。`reused` 是运行时观测状态，不是设计输入。managed 资源必须声明 token-array
`arguments`、working directory、port 和 runtime readiness probe；external 资源不得声明 cleanup。

`configurationProvider.kind` 支持 `spring-config-native|spring-config-git`。`repository` 始终表示 Config Server 实现仓；
`configurationRepository` 表示配置内容仓，省略时与 `repository` 相同。native target 使用
`<configRoot>/<application>/application-<profile>.yml`；git target 使用
`<configRoot>/<application>-<profile>.yml`。两仓 revision 必须分别进入 resolved manifest 与 fingerprint。

Change manifest v2 的配置部分：

```json
{
  "schemaVersion": 2,
  "environment": {
    "id": "local",
    "descriptor": "config/environments/local.json"
  },
  "configuration": {
    "environmentFile": ".env.local",
    "ownership": "human",
    "targets": [
      {
        "application": "sample-sut",
        "profile": "dev",
        "relativeFile": "config/sample-sut/application-dev.yml",
        "endpoint": "/sample-sut/dev",
        "sutEvidence": {
          "kind": "log-pattern",
          "patternId": "sample-sut-config-consumption"
        }
      }
    ]
  },
  "suts": [],
  "harness": { "revision": "sha256" },
  "runner": {
    "workingDirectory": "${TEST_ROOT}",
    "command": ["powershell.exe", "-NoProfile", "-File", "scripts/run-suite.ps1"],
    "failureCategory": "SUT_BUSINESS"
  }
}
```

`configuration.environmentFile` 仅表示环境变量文件，不能再兼作 config provider。probe 必须是结构化对象，禁止自由文本
command。路径必须 canonical 且位于授权根内；SUT/provider/system-test 必须是可解析 Git revision；配置 target 的
application/profile/path/endpoint 必须一致。

resolved manifest 至少包含 inputs hash、environment、provider revision、resources、executionOrder、cleanupPlan、probes、
SUT revisions、审计用 `designInputRevision` 和 `configurationFingerprint`。fingerprint 绑定 manifest、descriptor、provider、
harness、SUT revision、完整 target 文件 SHA256 及规范化 execution contract hash（provider/resources/order/cleanup/probes/evidence
contracts/SUT 启动契约/runner）；system-test 当前 revision 由 controller 独立锁定，不能把生成 resolved manifest 前的
HEAD 纳入 configuration fingerprint，否则产物随设计提交后会天然漂移。产物只记录 secret reference 名称，禁止真实 secret、
完整 `.env` 或带凭据连接串。

#### 11.2.3 v2 environment preflight（P2）

当 controller `next=VERIFY_ENVIRONMENT` 且 resolved manifest 为 v2 时，调用共享
`validate-test-environment.ps1`。输入为 resolved manifest、canonical controller state、verifier identity 和 report path。

verifier 必须只读检查：

- controller phase=`TEST_IMPLEMENTATION_VERIFIED`，test/SUT revision 与 canonical Git HEAD 一致；
- resolved fingerprint 与 controller `configurationFingerprint` 一致；
- manifest/descriptor hash、provider revision、target 完整文件 hash 未漂移；
- environment file 位于 system-test 仓，descriptor/target/probe 所需 reference 已由进程环境或该文件提供；
- managed resource 的 working directory、executable、token-array 中的启动脚本存在，声明端口可绑定；
- 只执行 `stage=preflight` 的 external TCP/HTTP probe；runtime probe 留给 RUN_ONCE。

P2 不启动 managed provider、中间件或 SUT，不运行 Docker/runner，不记录 environment value。报告固定包含
`result=PASS|BLOCKED`、`mode=environment`、verifierId、test/SUT/harness revision、configurationFingerprint、安全 summary、
结构化 steps 和 blockers。只有 PASS 可交给 controller `record-verifier -VerifyMode environment`；BLOCKED/ERROR 停止。

当前 controller state 只建模一个 SUT repository，因此 P2 对多 SUT resolved topology 返回 BLOCKED，后续 controller schema
升级前不得选择性忽略其他 SUT。

#### 11.2.4 v2 隔离生命周期执行（P3）

`run-resolved-environment.ps1` 只消费 P1 resolved manifest 和调用方提供的 expected fingerprint。执行前重新计算 execution
contract hash 与 fingerprint；不一致归为 `TEST_HARNESS` 并停止。执行顺序固定为：external preflight / managed resource
依赖顺序启动 → runtime readiness → Spring Config target application/profile 身份校验 → SUT 启动与 health → 声明的
`log-regex` 配置消费证据 → manifest runner。

managed 端口已占用时，只有显式 identityProbe 和对应 readiness probe 都 PASS 才可记为 `reused`；reused/external 不进入 cleanup。cleanup 仅逆序停止
本轮创建并记录的进程。配置消费证据缺失、provider target 不存在或身份不一致归为 `CONFIG_INFRA`；runner 非零退出按
`runner.failureCategory`（默认 `SUT_BUSINESS`）归因。结果不得包含环境值或原始敏感日志。

P3 引擎已纳入 harness certification。P4 起 `system-test.ps1` 按 manifest schema 分派：v1 原链路不变；v2 要求调用方提供
controller 锁定的 configuration fingerprint，并生成 `evidence/runs/<run-id>/runtime-result.json`、index 和 structured result。
standalone PASS 不得提交为 canonical `record-run`。

`ownership=human` 且 Git 忽略的配置中心本地文件允许已有凭据；其他配置仍要求 secret reference。完整文件摘要绑定 fingerprint，任何配置变化（含凭据变化）都会使快照失效；不向报告输出配置值。
configuration ownership/environmentFile、prepare/cleanup token-array 命令和 identityProbe 均绑定 execution contract。`.env` 仅用于必要运行参数；夹具通过 `FLOW_RESOLVED_MANIFEST` 读取同一配置来源。
`runner.prepare` 在资源就绪和配置目标校验后、SUT 启动前执行并验证本次契约；非零退出阻断业务用例。`runner.cleanup` 只清理本次夹具；禁止全局清空 WireMock。
每个 SUT `id` 对应 configuration target `application`，加载证据只检查该服务目标。默认服务启动 120 秒、suite 600 秒；只清理 PID 与精确启动时间匹配的本次进程树。
v2 standalone 支持 `-ScenarioIds`，由 canonical 派生契约确定 class#method、预期方法数量及 JUnit 报告集合。
runner.command 使用 `${FLOW_TEST_FILTER}` 与 `${FLOW_TEST_REPORT_DIR}`；空选集、未知 ID、零匹配、缺失/越界报告和 skipped 均失败。
部分运行报告必须 `fullSuite=false`，独立保存证据，不改全量 controller state，不能登记全量 Flow PASS。

#### 11.2.5 v1 → v2 单向迁移（P4）

`migrate-test-environment-manifest.ps1` 接收 legacy manifest 和人工审核的 `migration-spec.json`，只写一个不存在的新输出文件，
禁止原地覆盖。迁移器保留 suite、testCasesContract、failureObservability 等非环境字段，仅将旧
`configuration.source/ownership` 转为 `configuration.environmentFile/ownership`，并从 migration spec 引入 environment、targets、
SUT、harness 和 runner。缺少显式映射、输入已是 v2、路径越界、输出已存在或包含 literal sensitive value 均阻断。

P4 runtime 在每次创建 provider/SUT/suite 进程后持久化 `{pid, startedAtUtc}`；正常和失败路径逆序清理，中断后 `cleanup`
只有在 PID 与启动时间均匹配时才停止进程，避免 PID 复用导致误杀。reused/external 仍不写入 ownership state。

### 11.3 失败归因证据

manifest 必须声明 `failureObservability`，将 required 场景映射到稳定场景 ID、测试类/方法、关联字段、原始报告及日志/桩/数据库证据路径。
runner 无论 PASS 或 FAIL 都生成 `evidence/current/index.md`；FAIL 还生成 `failure-report.md`，逐项记录分类、确定性、首个证据和建议动作。
分类限于 `CONFIG_INFRA`、`TEST_HARNESS`、`DATA_SCHEMA_CONTRACT`、`SUT_BUSINESS`、`UNDETERMINED`。证据不足只能为
`UNDETERMINED`；只有 confirmed 的 `SUT_BUSINESS` 可作为独立业务 Flow 输入。当前 revision 不得重跑，修复或诊断增强后必须
形成新 revision 并重新经过 implementation verify。

### 11.4 automation-state.yaml（WP3 controller state）

根 `.flow/changes/{change}/automation-state.yaml` 是集成测试 machine state 的唯一权威。首版由
`flow-test-controller.ps1` 原子写入；它使用 JSON 兼容的 YAML 子集，不保存密码、token、完整连接串或其他 secret。

Harness 认证产物为结构化 JSON，至少包含 `schemaVersion`、`result=PASS`、`harnessVersion`、`harnessRevision`、`selfTestReportHash` 和受控 `files[]`（`path`、`sha256`）。controller 初始化与 runner 启动都必须验证认证绑定的实际文件；文件、revision 或 version 漂移后旧认证立即失效。配置契约的 `source` 是唯一来源，`ownership=human` 失败时状态只能进入 BLOCKED，`ownership=harness` 才能路由到独立平台修复。

公开测试 skill 必须从 canonical state 调用 controller `status`/`next`。`next` 输出当前 `phase`、唯一 `next`、对应 `skill` 和 `lease_required`；Goal 每轮只执行该动作一次。实现 agent 只消费 controller 签发的 lease，并在每次写入前验证 agent、role、capability、repository、path、base revision 与过期时间。skill 文案、manifest 或 agent 口述不得改变 state。

```yaml
schemaVersion: 1
changeName: string
phase: TEST_DESIGN_DRAFT | TEST_DESIGN_VERIFIED | TEST_IMPLEMENTING | TEST_IMPLEMENTED |
  TEST_IMPLEMENTATION_VERIFIED | TEST_ENVIRONMENT_VERIFIED | TEST_EXECUTING |
  TEST_EXECUTED_PASS | TEST_EXECUTED_FAIL | TEST_RESULT_VERIFIED | BLOCKED
authorization:
  maxPhase: design | implementation | execution | result
  grants: optional array # initial/追加用户授权原话、引用、报告hash与版本绑定；旧state可无此字段
repositories:
  systemTest: canonical absolute path
  sut: canonical absolute path
revisions:
  designRevision: current accepted design revision; initialize or pre-implementation accept-design-revision
  testBaseRevision: accepted design base before implementation leasing
  testBaseline: immutable pre-design system-test baseline used by generated sidecar; never replaced by a commit containing that sidecar
  test: current accepted system-test revision; changed only by controller revision acceptance/repair commands
  sut: immutable SUT revision
  harness: immutable harness revision
configurationFingerprint: string
leases: array # implementation lease records implementationBaseRevision at issue time; accept scopes base -> proposed HEAD
runs: array
failureFingerprints: array[string]
activeRun: object | null       # TEST_EXECUTING 的唯一已持久化 runner；启动前按 test revision 去重
scopeVerification: object | null # trusted scope PASS and controller-computed implementation-base-to-proposed diff
verifier: object | null
designRevisions: optional array # reopen-design保留旧revision/verifier/reason；不清除历史
scopeDesignReviews: optional array # 实施中用户范围修订审核：原话/引用、审核人、前后提交及源hash、稳定baseline、SUT/harness/config、diffHash、删除ID、报告hash；只记审计，不推进阶段
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

`changes/{change}/test-cases.yaml` 是业务用例及技术绑定的唯一来源；`test-plan.md` 的唯一生成区先列业务用例，再列技术附录。人工区只承载背景与边界，不得维护第二份手写用例、计数或映射。文件使用固定 schema 的严格 YAML 子集；malformed YAML、
未知字段、错误嵌套、字段类型错误或必填结构缺失均拒绝。结构如下：

```yaml
schemaVersion: 1
scenarios:
  - id: AC-n-Sn
    acceptance: AC-n
    required: true | false
    suite: api | ui | cdc | other
    integration: Y | N
    business:
      purpose: "验证目的"
      preconditions: "具体规则配置及初始状态"
      inputs: "具体输入数据"
      steps: "业务操作/事件顺序"
      expected: "预期最终数值、状态、归属及副作用"
      oracle: "需求或已确认样本位置与独立推导"
      counterexamples: "关键反例及结果；不适用须给理由"
      evidenceBoundary: "Y/N理由、真实与替身范围及最终落点"
    testClass: fully.qualified.ClassName
    testMethod: stableMethodName
    reportClass: report.class.Name
    filter: stable-runner-filter
    externalEvidence: []
    setup:
      fixtures: [fixture-id]
    action:
      method: POST
      path: /resource
    assertions:
      response: [success]
      database: [row-created]
      sideEffects: [none-unexpected]
    cleanup: [fixture-id]
    observability:
      correlationField: X-Test-Scenario
      allowedEvidence: [reports/junit.xml, logs/service.log]
```

`id` 必须唯一且稳定；`integration: Y` 必须声明 testClass/testMethod/reportClass/filter，并由 Java 测试方法通过稳定
ID 注解绑定；`integration: N` 不得声明这些可执行字段，只能以 externalEvidence 证明覆盖。未知、重复、缺失或方法/类漂移均拒绝。
manifest 以 `testCasesContract.path` 引用 `test-cases.generated.json`，不得在根重复维护场景派生字段。sidecar
确定性承载 source hash、初始化前的 `testBaseline` revision、integration Y/N 全映射、required/expected method count、runner filters、
report classes、evidence index 骨架和 failure observability；test-plan 只在
`FLOW_TEST_CASES_GENERATED` 标记区显示生成镜像，区外人工说明按字节保留并绑定 outside hash。
实际 design/implementation commit 由 controller 的 `designRevision`/`test` 单独锁定。禁止要求 sidecar 绑定包含其自身的
commit；该要求会形成不可收敛的 commit 自引用。

旧 manifest 迁移时保留环境、fixture、WireMock、runner 与授权配置，新增 `testCasesContract.path`，由 canonical
source 生成 sidecar，并删除根层旧 count/filter/report/integration/evidence/failureObservability 派生字段。
validator 对未迁移的旧字段明确报错并退回 design verify，不静默采用旧值。

required 场景删除必须提供 controller state 完整性校验通过且 summaryHash 一致的结构化 design verifier PASS，
绑定 previous/current revision、previous/current source hash 与 verifier identity；自由布尔开关、伪造或陈旧 report
均拒绝。`integration` 只允许 `Y`/`N`；`N` 必须声明 externalEvidence。提供 EvidenceRoot 时，普通和外部证据都必须落地。

business 为上述八个非空单行字符串；不放实际执行状态或以被测输出充当预期。schemaVersion 仍为1，旧技术字段和ID保持兼容。
`validate-test-cases -Mode business` 仅要求 id/acceptance/required/integration/business；可用 -Generate -TestPlanPath 预览业务用例，不要求技术字段、manifest或sidecar。
完成业务语义审核并补齐后再设计技术字段，以默认design模式生成完整计划和sidecar。
正式 `validate-test-artifacts` 各阶段强制 RequireBusiness；旧源仍可解析/导出，但缺业务用例不能取得新的正式设计通过。
脚本只证明结构、绑定及确定性；具体预期正确性、覆盖是否充分由 test-verify 对原始需求审查，不因字段齐全自动通过。
存量设计按 test-controller.md 的 reopen-design/accept-design-revision 复核，保留旧审核和稳定baseline，不制造历史。

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



## Codex Git 命名扩展（flow-v1）

仅 Codex 模板启用 `conventions.agent_git: flow-v1`；Claude legacy 字段与安装行为不变。`branch_pattern` 是完整模式 `feature/{change_name}`，`commit_format` 为 `{requirement_id} {type} {description}`，`commit_language` 为 `zh-CN`，项目级不得固定 task_id。

首次 design 的命名身份保存在 `.flow/changes/<change_name>/change.json`：`version: 1`、`requirement_id`（小写 glw-数字）、`title`（中文）、`slug`（英文 kebab-case）、`delivery_date`（初始交期 YYYYMMDD）、`change_name`（slug-交期）、`branch`（完整 feature/change_name）、`legacy: false`。这不是设计方案，不解除 domain 门禁；task 与概要设计读取该身份，延期不改路径。

定点接入存量需求使用 `legacy: true`，slug/delivery_date 为 null，保留真实旧 change_name/branch，另记 `evidence_repo`（核实当前分支的仓库）；不自动批量迁移。工作目录绑定及 Agent 提交回执存于实际 Git dir，不纳入业务版本库。详细命令见 `codex/skills/flow-codex-core/references/git-conventions.md`。


## Codex 集成测试观测增量（2026-09）

本节仅用于 Codex 新版，不改变旧 Claude 安装。`test-cases.yaml` 的 `business.tables` 可选，为具名表数组（当前严格 YAML 解析器接受单行 JSON 数组）：每表含 `name`、文本列名 `columns`、等宽文本二维数组 `rows`。旧 business 字符串、ID 与技术绑定保留。表格只表达原用例，不生成通过结论。

v2 manifest 可选 `runner.check` 为非空命令 token 数组，在资源启动前用实际运行环境执行依赖检查；纳入 resolved 执行契约和指纹，缺省保持旧行为。不得在 check 中写业务数据。

manifest 可选 `nonBuildInputs` 为精确内容的构建影响审核记录：repository（绝对仓路径）、path（Git 相对文件）、sha256、reason、evidencePath。用于保留经核实不参与构建或运行的文件，不接受通配排除，不默认按扩展名忽略；内容变化即失效。该记录参与 execution binding，源码及配置不因存在无关文件而被清理。

根 change 的 `test-timeline.jsonl` 是观测日志，不是 controller 状态：schemaVersion=1，eventId、cycleId、parentCycleId、UTC at、action、stage、reason、reference、intervention、outcome、sessionId。事件追加、重复 eventId 幂等；损坏尾行保留并报告缺失。部分交付可 resume 原周期，完整完成或取消后新范围使用显式新周期。计时不重置执行预算，不授予权限、不影响 PASS。

runner 的可选 `businessMetrics` 来源于测试适配器实际断言埋点，事件包含 kind=assertion、scenarioId、UTC at；controller 仅收录当前选中场景。缺失埋点时未知，不从 suite 启动时间推导。计时、运行摘要及业务验收分别保留责任边界。
