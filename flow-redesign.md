# Flow Skill 改进设计文档 v3

> 基于完整讨论决策的重整版本。
> 状态：待校验。

---

## 一、核心设计原则

1. **根 agent 职责收窄**：需求拆分、概要设计、维护大需求 task.md、派发任务、查看进度、触发集成测试、归档。**不编码、不提交代码、不更新 task.md 的 spec 完成状态**。

2. **子 agent 自行完成开发循环**：receive 接收任务 → design（如需要）→ apply 编码（内部委托 opsx:apply + 审核子 agent + 自提交）→ report 汇报并更新 task.md。**task.md 的唯一写入者是 flow:report**。**1 task = 1 spec = 1 agent = 1 commit**。

3. **子 agent 入口统一**：无论内联还是独立模式，子 agent 的第一步始终是 `/flow:receive`。receive 判断当前阶段（有 design.md → 直接 apply，无 → 先 design）。

4. **两种工作模式并存**：
   - **根指导模式**：根唤起 → 子 receive → 子设计+自检 → 用户评审 → 子编码循环 → 子 report
   - **用户直接模式**：用户进入子目录 → 使用 flow 命令自动检查 init → 子自主工作

5. **子 agent 内部循环自动化**：编码完成后，内联审核/测试 agent 自动执行，不需要用户中转。

6. **两种 agent 形态**：**独立会话**（用户手动启动的新 Claude Code 进程，有持久记忆）和**内联 agent**（父 agent 通过 Agent tool 启动，无持久记忆）。根 agent 可以启动内联 agent，但无法自动启动独立会话（平台硬限制）。根→子通过文件（task.md）通信。

7. **现阶段 spec 设计由根完成**：知识库不完善阶段，根 agent 与用户协力确定 spec 粒度、边界，并用 spec skills 在子服务创建 proposal + design。子 agent 收到任务时 design.md 已就绪，直接进入 apply。子 agent 自主设计是远期目标，需知识库成熟后启用。

---

## 二、Agent 启动模式

两种 agent 的本质区别是**启动方式**，不是用途：

```
┌──────────────────────────────────────────────────────────────┐
│  独立会话（Independent Session）                              │
│  用户手动在服务目录打开新的 Claude Code 进程                    │
│  · 持久 memory：~/.claude/projects/{项目-服务名}/memory/      │
│  · 拥有独立的 CLAUDE.md、settings、skills                     │
│  · 根 agent 无法自动启动——必须由用户手动操作                   │
├──────────────────────────────────────────────────────────────┤
│  内联 agent（Inline Agent）                                   │
│  由父 agent 通过 Agent tool 启动，运行在父会话的进程内          │
│  · 无持久 memory，随父会话结束而消失                            │
│  · 继承父 agent 的 skills、settings、MCP 工具                  │
│  · 根 agent 和子 agent 都可以启动内联 agent                    │
└──────────────────────────────────────────────────────────────┘
```

**关键约束**：
- 根 agent **可以**通过 Agent tool 启动内联 agent（用于编码、审核、测试等）
- 根 agent **无法**自动启动独立会话——必须由用户手动在服务目录打开 Claude Code
- 子 agent（无论是独立会话还是内联 agent）都可以启动自己的内联 agent（审核、测试）

---

## 三、目录结构定义

### 3.1 根 agent 目录

```
{项目根目录}/
└── .flow/
    ├── config.yaml                   # 项目配置（role: orchestrator）
    ├── onboarding.md                 # ★ 二级 agent 模式说明 + 子 agent 开发规范
    │                                 #   所有子 agent 共享这一份，放根目录
    ├── services.md                   # 服务地图（名称、路径、类型、职责）
    ├── 知识库说明.md                  # 知识库位置、结构、读写规则（如启用）
    └── changes/
        ├── {需求名}-{YYYYMMDD}/      # 大需求目录（开始日期）
        │   ├── 概要设计.md            # 整体方案、服务边界、接口契约草稿、验收标准
        │   └── task.md               # 大需求任务清单（含 spec 粒度定义）
        └── archive/
            └── {需求名}-{YYYYMMDD}-{YYYYMMDD}/  # 归档（开始-结束日期）
```

**onboarding.md 内容**（根目录，所有子 agent 共享）：
- 二级 agent 架构说明（根/子职责边界）
- 子 agent 工作规范（提交格式、分支规范、知识库规则）
- 子 agent 工作循环（阶段一设计 → 阶段二编码 → 阶段三汇报）
- 内联 agent 使用规范（何时启动审核/测试 agent）

**config.yaml（根）**：

```yaml
project:
  name: string
  role: "orchestrator"
  created: "YYYY-MM-DD"

services:
  - name: string                    # 服务标识（kebab-case）
    path: string                    # 相对根目录的路径
    type: string                    # bff / data-service / admin / ...
    description: string             # 一句话职责
    flow_initialized: boolean       # 该服务是否已完成 flow:init
    flow_initialized_at: string     # 初始化日期

knowledge_base:
  enabled: boolean
  path: string                      # 知识库根路径（绝对路径）
  child_write: boolean              # 子 agent 是否可直接写入
  review_on_archive: boolean        # 归档时是否审核知识库变更

conventions:
  task_id_prefix: string            # 任务号前缀，如 "GLW"，可选
  branch_pattern: string            # 如 "feature/<kebab-case>"
  commit_format: string             # 如 "{prefix}-{id} {type}: {description}"

child_agent:
  spec_tool: string                 # 子 agent 使用的 spec 工具，如 "opsx"
  onboarding_doc: ".flow/onboarding.md"
```

---

### 3.2 子 agent 目录

```
{服务目录}/
└── .flow/
    ├── config.yaml                   # 服务配置（role: executor）
    └── 工作流程.md                    # 本服务工作循环说明（持久化，服务级定制）
```

**说明**：
- `onboarding.md` 在根目录，子 agent 通过 `root_path` 读取，不在服务目录重复
- `工作流程.md` 是服务级文件，记录本服务的 spec 工具、测试命令等具体配置

**config.yaml（子）**：

```yaml
project:
  name: string                      # 与根一致
  role: "executor"
  root_path: string                 # 到根目录的相对路径，如 "../../"
  service_name: string              # 当前服务名

knowledge_base:
  enabled: boolean
  path: string
  child_write: boolean

conventions:
  task_id_prefix: string
  branch_pattern: string
  commit_format: string

child_agent:
  spec_tool: string
  onboarding_doc: "{root_path}/.flow/onboarding.md"   # 指向根目录

inline_agents:
  review:
    enabled: boolean                # 默认 true
    knowledge_base_rules_path: string  # 知识库中审核规范路径，可选
  unit_test:
    enabled: boolean                # 默认 true
    test_command: string            # 如 "mvn test" / "npm test"
  knowledge_maintenance:
    enabled: boolean                # 默认 true
    auto_trigger: boolean           # false=每次询问用户；true=自动判断
```

**工作流程.md**（服务目录，持久化）：

```markdown
# {service_name} 工作流程

## 基本信息
- 根目录：{root_path}
- spec 工具：{spec_tool}
- 测试命令：{test_command}
- onboarding：{root_path}/.flow/onboarding.md

## 阶段一：设计

1. 执行 /flow:receive，读取根 task.md 中本服务的 spec 列表
2. 读取 {root_path}/.flow/changes/{change}/概要设计.md 和知识库
3. 为每个 spec 创建 proposal.md + design.md
4. 执行 /flow:design 进行自检（内联评审 agent）
5. 自检通过后告知用户："设计完成，请评审"
6. 评审通过 → 进入阶段二；评审驳回 → 修改后重新自检

## 阶段二：编码

1. 按 spec 依赖顺序逐个执行 apply
2. 每个 spec 完成后自动触发：
   a. 内联审核 agent（审核代码与 spec 一致性）
   b. 单元测试（{test_command}）
3. 审核/测试通过 → 下一个 spec；失败 → 修复后重试
4. 所有 spec 完成 → 执行 /flow:report

## 阶段三：汇报

1. /flow:report 生成结构化汇报
2. 自动更新根 task.md（勾选完成的 spec）
3. 强制判断知识库维护（不可跳过）
4. 结束
```

---

### 3.3 task.md 结构（根维护）

```markdown
---
requirement: string
type: feature / hotfix / refactor
status: planning / in_progress / completed / archived
tier: 1 / 2 / 3
branch: string
services: [service-a, service-b]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

## 开发顺序

1. service-b（无依赖，先开发）
2. service-a（依赖 service-b 的权限查询接口）

---

## service-b

> 状态：📋 待开始 | 分配日期：—

- [ ] spec1: 实现权限查询接口
      边界：只查询，不做权限修改
      依赖：无
- [ ] spec2: 实现权限缓存
      边界：本地缓存，TTL 5分钟
      依赖：spec1

## service-a

> 状态：⏳ 阻塞（等待 service-b spec1 完成）| 分配日期：—

- [ ] spec1: 实现登录接口
      边界：认证逻辑，不做权限判断
      依赖：service-b spec1（权限查询接口）
- [ ] spec2: 实现 token 刷新
      边界：刷新逻辑，复用登录的 token 生成
      依赖：spec1

## 变更通知（待子 agent 感知）

- service-a：spec1 边界调整，请重新评审 design  ← flow:change 写入
```

---

## 四、命令清单

### 4.1 所有命令概览

| 命令 | 根 agent | 子 agent | 说明 |
|------|:--------:|:--------:|------|
| `/flow:init` | ✅ 模式A | ✅ 模式B | 初始化必要文件（不含设计） |
| `/flow:design` | ✅ 根模式 | ✅ 子模式 | 根：概要设计+task；子：spec设计+自检 |
| `/flow:assign` | ✅ | — | 派发任务给子 agent（内联/独立两种模式），子入口是 receive |
| `/flow:receive` | — | ✅ | 接收任务，加载工作协议 |
| `/flow:apply` | — | ✅ | 阶段二编码：按 spec 顺序执行编码→审核→测试循环 |
| `/flow:report` | — | ✅ | 汇报，更新根 task.md，触发知识库维护 |
| `/flow:status` | ✅ | — | 查看大需求进度 |
| `/flow:verify` | ✅ | — | 跨服务接口契约验证 |
| `/flow:test` | ✅ | — | 触发集成测试（HTTP/MQ/DB） |
| `/flow:change` | ✅ | — | 大需求变更（更新概要设计+task.md） |
| `/flow:archive` | ✅ | — | 归档大需求，填写结束日期 |
| `/flow:hotfix` | ✅ | — | 在 task.md 写入 hotfix 条目 + 用 spec skills 创建子服务 spec 目录，然后走 assign 派发 |

---

### 4.2 命令详细说明

#### `flow:init` — 初始化必要文件

**职责**：只创建 `.flow/` 下的必要文件，不做需求分析或设计。

**模式 A：根 agent 初始化**

触发条件：当前目录无 `.flow/config.yaml`，用户希望作为根 agent 工作。

生成文件：
```
.flow/
├── config.yaml        ← 收集项目名、服务列表、知识库配置、约定
├── onboarding.md      ← 二级架构说明 + 子 agent 开发规范（模板生成）
├── services.md        ← 服务地图（从服务列表生成）
└── 知识库说明.md       ← 仅在 knowledge_base.enabled=true 时生成
```

注意：不再提前在服务目录生成子 agent 配置，由子 agent 自己 init 时注册。

**模式 B：子 agent 初始化**

触发条件：当前目录无 `.flow/config.yaml`，或用户使用任意 flow 命令时检测到缺失。

步骤：
1. AskUserQuestion 收集：根目录路径、服务名称、spec 工具、测试命令、inline_agents 配置
2. 生成 `.flow/config.yaml`（role: executor）
3. 生成 `.flow/工作流程.md`（从模板渲染，注入服务信息）
4. **向根注册**：读取并更新 `{root_path}/.flow/config.yaml` 的 services 列表
5. 输出摘要

约束：向根注册前展示变更内容，用户确认后写入；根 config.yaml 不存在时警告但不中止。

---

#### `flow:design` — 设计阶段（双角色）

**根模式（role: orchestrator）**

职责：与用户协力完成概要设计和 task.md（含 spec 粒度定义和验收标准），并为每个 spec 在子服务创建 proposal + design。

前置：必须有活跃 change 目录（`flow:init` 已创建）。

步骤：
1. 读取 config.yaml 获取服务列表和知识库配置
2. AskUserQuestion 收集需求描述（如未提供）
3. 与用户协力分析：涉及服务、服务边界、依赖关系、接口契约草稿
4. 生成 `概要设计.md`：
   - 背景与目标
   - 涉及服务及职责
   - 服务间接口契约草稿
   - 开发顺序（按依赖）
   - **验收标准**（集成测试的依据，必须章节）
   - 非目标
5. 生成 `task.md`：按服务分组，每个 spec 含 spec-id + 边界 + 依赖
6. 使用 spec skills（`child_agent.spec_tool`）为每个 spec 在子服务创建 proposal + design
7. 展示产物供用户审阅，确认后写入

**子模式（role: executor）【远期目标】**

前置条件：知识库成熟后启用。当前主线由根模式完成 spec 设计。

职责：为本服务每个 spec 做 proposal + design，完成后内联自检，输出评审报告。

前置：已执行 `flow:receive`，已读取 spec 列表。

步骤：
1. 读取根 task.md 中本服务的 spec 列表（名称、边界、依赖）
2. 读取 `概要设计.md` + 知识库（如启用）
3. 为每个 spec 创建 proposal.md + design.md
4. 内联启动设计评审 agent，传入：
   - 所有 spec 的 proposal.md + design.md
   - 概要设计.md
   - task.md 中本服务的 spec 边界定义
5. 评审 agent 检查维度（专注，不发散）：
   - 每个 spec 边界是否与 task.md 定义一致
   - 依赖接口是否在概要设计中有定义
   - spec 间依赖顺序是否与 task.md 一致
   - 接口路径/字段是否与概要设计契约草稿对齐
6. 输出自检报告（✅/⚠️/❌ 三级）
7. 无 ❌ → 告知用户"设计完成，自检通过，请评审"
   有 ❌ → 提示修改后重新执行

约束：评审只检查与概要设计/task.md 的一致性，不评价方案优劣，不检查代码。

---

#### `flow:assign` — 派发任务（根）

`flow:assign` 是子 agent 开发的**入口**。根 agent 按 spec 粒度派发任务：**1 task = 1 spec = 1 agent = 1 commit**。

根 agent 只负责生成提示词和派发，**不做任何编码、提交、task.md 更新**。

**两种模式**：

- **独立指令包**：根 agent 为每个 spec 输出独立提示词，用户手动在新终端逐个粘贴
- **内联执行**：根 agent 按依赖顺序，为每个 spec 使用 Agent tool 启动一个子 agent

**提示词内容**（每个 spec 独立一份）：

| 信息 | 说明 |
|------|------|
| 工作目录 | 服务绝对路径 |
| 服务名 | 来自 config.yaml |
| root_path | 根目录路径 |
| 唯一任务 | spec_name（只此一个 spec） |
| 第一步指令 | 执行 `/flow:receive {spec_name}` |

提示词聚焦单个 spec，不包含其他 spec 的细节。

**内联模式约束**：
- 根 agent 按依赖顺序逐 spec 启动子 agent（依赖 spec 先完成再启动后续）
- 无依赖的 spec 可并行启动
- 每个子 agent 启动后第一件事是目录验证（pwd + git remote -v）
- 根 agent 不读取 design.md、不编码、不提交、不更新 task.md
- 每个子 agent 自行完成：receive → design（如需要）→ apply（单 spec）→ report

**独立模式约束**：
- 每个 spec 独立一份指令包
- 指令包指引第一步是 `/flow:receive {spec_name}`（由 receive 判断阶段）

---

#### `flow:receive` — 接收任务（子）

输入：`/flow:receive [spec-name]`。有参数时聚焦单个 spec，无参数时读取所有本服务 spec。

新增步骤（现有步骤之后）：

1. 读取 `.flow/工作流程.md` 作为本次会话执行协议
2. 读取根 task.md，检查变更通知章节（如有），展示给用户
3. 判断当前阶段：
   - 指定 spec 无 design.md → 阶段一（设计）
   - 指定 spec 有 design.md → 阶段二（编码）
4. 输出阶段启动摘要，引导执行 `/flow:design`（阶段一）或 `/flow:apply {spec-name}`（阶段二）

---

#### `flow:apply` — 阶段二编码（子）

输入：`/flow:apply {spec-name}`（必传，由 `/flow:receive` 确定后传入）。

职责：完成单个 spec 的编码循环。编码委托给 spec_tool（如 opsx:apply），spec_tool 自行读取 spec 文件。子 agent 自行唤起审核 agent、运行测试、提交代码。

步骤：
1. 验证 spec 的 `design.md` 存在
2. **编码**：使用 spec_tool，不手动转述 design.md
3. **审核**：内联审核 agent，检查代码与 design.md 的一致性
4. **测试**：执行 `inline_agents.unit_test.test_command`
5. **提交**：暂存代码文件 + 本 spec 目录的 spec 文件，git commit（commit 记录由 report 写入 task.md）
6. 输出结果，提示执行 `/flow:report`

约束：
- 每个 agent 只处理一个 spec（**1 spec = 1 commit**）
- **不读取 task.md 找 spec**——spec 已由 `/flow:receive` 确定
- **不手动读取 design.md 并转述**——spec_tool 自行读取
- 不更新 task.md（唯一写入者是 `/flow:report`）
- 审核和测试重试各最多 3 次，超限必须停止

#### `flow:report` — 汇报（子）

`flow:report` 是 **task.md 的唯一写入者**。子 agent 完成编码后提交结构化汇报，更新根 task.md，强制触发知识库维护判断。

新增：
- 汇报增加**测试结果章节**（单元测试通过情况）
- report 完成后**强制知识库判断**（必须回答，只能说"不需要"，不能跳过）
- 知识库触发条件：新业务规则、坑点发现、接口变更（bug 修复和内部重构不触发）
- **task.md 更新权收归 report**：apply 和 assign 均不更新 task.md

---

#### `flow:hotfix` — 创建 hotfix 条目（根）

触发：`/flow:hotfix <service-name> "bug 描述"`

步骤：
1. 在根 task.md 对应服务的 `### Hotfix` 子章节下追加条目
2. 使用 `child_agent.spec_tool` 配置的 spec skills 在子服务创建标准 spec 目录 `hotfix-{YYYYMMDD}-{slug}/`（内含 proposal.md、design.md 等标准文件）
3. 提示用户执行 `/flow:assign <service>` 派发 hotfix

约束：
- **根 agent 只创建条目和触发 spec skills，不编码**
- hotfix 编码走 assign → receive → apply 通道（与 spec 相同）
- 子 agent 的 spec 文档由 spec skills 维护，flow 命令不直接手写 spec 文件
- hotfix 条目放在 `### Hotfix` 子章节，不影响 spec 条目和开发顺序

---

#### `flow:test` — 集成测试（根）

触发：`/flow:test [change-name]`

前置：task.md 所有 spec 已完成（全部 [x]）

步骤：
1. 读取概要设计.md 的**验收标准**章节
2. AskUserQuestion 确认本地测试环境（各服务地址、DB、MQ）
3. 内联启动集成测试 agent，传入验收标准 + 环境配置
4. 集成测试 agent 执行：HTTP 调用 / MQ 发送+结果验证 / DB 直查
5. 输出测试报告
6. 全通过 → 建议 `flow:verify` + `flow:archive`；有失败 → 标注失败服务，建议重新 `flow:assign`

---

#### `flow:change` — 需求变更（根）

触发：`/flow:change [change-name]`

步骤：
1. 读取当前 change 的概要设计.md 和 task.md
2. AskUserQuestion 收集：变更类型、描述、原因、影响服务/spec
3. 更新概要设计.md：追加变更记录章节
4. 更新 task.md：修改受影响 spec，在末尾追加变更通知章节
5. 提示：受影响子 agent 下次 receive 时会读到变更通知

约束：变更通知由子 agent 下次 receive 时主动读取，根不主动推送。

---

#### `flow:status` / `flow:verify` / `flow:archive` — 小改

- `flow:status`：识别 spec 粒度完成情况（区分 spec 完成数/总数）；识别 hotfix 类型
- `flow:verify`：不变
- `flow:archive`：归档时将目录名补充结束日期（`{需求名}-{开始日期}-{结束日期}`）

---

## 五、完整工作流场景图

### 场景一：根指导模式（Tier 2，跨服务大需求）

```
用户提需求
    │
    ▼
根 /flow:init                         创建 .flow/ 必要文件
    │
    ▼
根 /flow:design                       与用户协力：概要设计.md + task.md
    │                                 + 用 spec skills 为每个 spec 创建 proposal + design
    ▼
根 /flow:assign <service-b>           按依赖顺序，无依赖先分配
    → 选择模式：内联执行 / 独立指令包
    │
    │  内联模式：
    │    根按顺序为每个 spec 启动一个子 agent：
    │    Agent(spec1) → receive → apply → report
    │    Agent(spec2) → receive → apply → report
    │  独立模式：根为每个 spec 输出独立指令包
    │  ← 用户按依赖顺序逐个粘贴
    ▼
子 agent(spec1) 检查 .flow/config.yaml
    → 不存在 → /flow:init（子模式）→ 向根注册
    → 存在 → 继续
    │
    ▼
子 /flow:receive spec1                  聚焦单 spec，design.md 已存在 → 直接进入阶段二
    │
    ▼
子 /flow:apply spec1
    → opsx:apply → 内联审核 → 单元测试 → commit
    → 失败自动修复重试（最多 3 次）
    │
    ▼
子 /flow:report
    → 更新根 task.md（spec1 [x]）  ← 唯一写入点
    → 强制知识库判断
    │
    │  ← spec1 完成后，根启动 spec2 agent（同循环）
    ▼
（所有 spec 完成，service-b ✅）
    │
    │  ← 用户告知根 agent：service-b 已完成
    ▼
根 /flow:status                       service-b ✅，service-a 解除阻塞
    │
    ▼
根 /flow:assign <service-a>           ... 同上循环
    │
    ▼
（所有服务完成）
    │
    ▼
根 /flow:test                         集成测试（HTTP/MQ/DB）
    │
    ▼
根 /flow:verify                       接口契约一致性验证
    │
    ▼
根 /flow:archive                      归档，目录名补充结束日期
```

---

### 场景二：用户直接模式（Tier 1，单服务）

```
用户进入服务目录，打开 Claude Code
    │
    ▼
用户执行任意 flow 命令
    → 检查 .flow/config.yaml
    → 不存在 → 强制提示执行 /flow:init（子模式）
    → 存在 → 继续
    │
    ▼
用户与子 agent 协商任务
    → 子 agent 自行走：设计 → 编码循环 → report
    → /flow:report 更新根 task.md（如有根的话）
```

---

### 场景三：Hotfix 模式

```
用户发现 bug，在根目录
    │
    ▼
根 /flow:hotfix <service> "bug 描述"
    → 在 task.md 写入 ### Hotfix 条目
    → 用 spec skills 在子服务创建 hotfix spec 目录
    │
    ▼
根 /flow:assign <service>
    → 派发 hotfix 任务（task_type=hotfix，跳过用户设计评审）
    │
    ▼
子 /flow:receive hotfix-xxx
    → spec 已有 design.md → 直接进入阶段二
    │
    ▼
子 /flow:apply hotfix-xxx
    → 编码 → 内联审核 → 单元测试 → commit
    │
    ▼
子 /flow:report
    → 更新 task.md ### Hotfix 条目为 [x]
    → 知识库：只记录坑点/根因
```

---

### 场景四：需求变更（进行中大需求）

```
业务需求变化
    │
    ▼
根 /flow:change
    → 更新概要设计.md（追加变更记录）
    → 更新 task.md（修改 spec，追加变更通知章节）
    │
    │  ← 受影响子 agent 下次 /flow:receive 时读到变更通知
    ▼
子 /flow:receive
    → 展示变更通知
    → 若阶段一未完成：直接修改 spec，重新 /flow:design
    → 若阶段一已完成阶段二未开始：重新 /flow:design
    → 若阶段二已完成：走 /flow:change（已归档则新建 change）
```

---

## 六、模板变更清单

### 新增模板

| 文件 | 生成时机 | 内容 |
|------|---------|------|
| `templates/工作流程.md.tmpl` | `flow:init`（子模式） | 服务级工作循环（含服务信息、阶段说明） |
| `templates/fix.md.tmpl` | `flow:hotfix` | bug 描述、复现、根因、修复方案 |
| `templates/integration-test.md.tmpl` | `flow:test` | 集成测试用例（HTTP/MQ/DB） |

### 修改模板

| 文件 | 修改内容 |
|------|---------|
| `templates/onboarding.md.tmpl` | 改为根目录共享版：二级架构说明 + 子 agent 规范 |
| `templates/child-config.yaml.tmpl` | 增加 `inline_agents` 配置节 |
| `templates/assign.md.tmpl` | 增加 spec 列表、概要设计路径、阶段说明 |
| `templates/config.yaml.tmpl`（根） | 增加 services 的 `flow_initialized` 字段 |

---

## 七、改动影响范围总览

| 文件 | 改动类型 | 核心改动 |
|------|---------|---------|
| `commands/init.md` | 修改 | 双模式重构，子模式增加向根注册，职责收窄（不含设计） |
| `commands/receive.md` | 修改 | 增加变更通知检查、阶段判断、工作流程.md 加载 |
| `commands/report.md` | 修改 | 强制知识库判断、测试结果章节 |
| `commands/status.md` | 小改 | spec 粒度进度、hotfix 类型识别 |
| `commands/archive.md` | 小改 | 归档目录名补充结束日期 |
| `commands/design.md` | 新增 | 双角色设计命令（根：概要设计；子：spec设计+自检） |
| `commands/hotfix.md` | 修改 | 从子 agent 命令改为根 agent 命令：写入 task.md hotfix 条目 + 触发 spec skills 创建目录 |
| `commands/test.md` | 新增 | 集成测试触发 |
| `commands/apply.md` | 新增 | 阶段二编码循环（编码→审核→测试，自动重试） |
| `commands/change.md` | 新增 | 需求变更协议 |
| `templates/onboarding.md.tmpl` | 修改 | 改为根目录共享版 |
| `templates/child-config.yaml.tmpl` | 修改 | 增加 inline_agents |
| `templates/assign.md.tmpl` | 修改 | 增加 spec 列表和阶段说明 |
| `templates/config.yaml.tmpl` | 修改 | 增加 flow_initialized |
| `templates/工作流程.md.tmpl` | 新增 | 服务级工作循环规范 |
| `templates/fix.md.tmpl` | ~~新增~~ 废弃 | hotfix 改用 spec skills 创建标准 spec 目录，不再使用 fix.md |
| `templates/integration-test.md.tmpl` | 新增 | 集成测试用例模板 |
| `docs/schema.md` | 修改 | 新字段和文件格式补充 |
| `docs/paradigm-v3-root-perspective.md` | 重写为 v4 | 反映新架构、双角色模式、三阶段工作循环 |

**总计**：5 个新命令，5 个修改命令，3 个新模板，4 个修改模板，2 个文档更新。

---

## 八、遗留问题

1. **spec 自主拆分里程碑**：当前阶段根定义 spec 粒度，这是知识库不完善的务实选择。后续以知识库覆盖率作为放开条件，具体标准待定。

2. **集成测试用例质量**：依赖概要设计.md 的验收标准章节，flow:design（根模式）需要强制要求用户写清楚验收标准，否则集成测试无法生成有意义的用例。
