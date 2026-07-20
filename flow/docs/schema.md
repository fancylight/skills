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

## 9. 概要设计.md

由 `/flow:design`（根模式）生成，位于 `.flow/changes/{change-name}/概要设计.md`。

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

