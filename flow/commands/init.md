---
name: "Flow: Init"
description: "Initialize a multi-agent project or create a new requirement"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.1.0"
---

初始化多 agent 编排项目，或在已有项目中创建新需求。

**两种模式：**
- 当前目录无 `.flow/` → **项目初始化**（收集配置、生成脚手架）
- 当前目录有 `.flow/` → **创建新需求**（分析需求、生成 proposal + tasks）

---

**输入**：`/flow:init` 后的参数为空则进入项目初始化，有内容则作为需求描述创建新需求。

## 模式 A：项目初始化（无 `.flow/` 目录）

**步骤**

1. **检测项目结构**

   扫描当前目录的子目录，识别独立服务/项目：
   - 包含 `pom.xml`、`package.json`、`go.mod`、`Cargo.toml` 等构建文件
   - 包含 `.git/`（独立 git 仓库）
   - 包含 `src/` 等源码目录

   将检测结果展示给用户确认。

2. **收集项目配置**

   使用 **AskUserQuestion** 逐步收集：

   a. **项目名称**：根据目录名建议默认值
   b. **服务列表**：展示检测到的服务，用户确认/编辑/补充
   c. **知识库**：是否有外部知识库？
      - 有：收集路径和结构类型（hierarchical / flat）
      - 无：跳过
   d. **约定**：
      - 任务号前缀（如 "GLW"、"PROJ"）— 可选
      - 分支模式（默认 `feature/<kebab-case>`）
      - 提交格式（默认 `{type}: {description}`）
   e. **子 agent spec 工具**：子 agent 用什么开发流程工具？
      - OpenSpec / 自定义 / 无 — 仅记录，不强制

3. **生成项目脚手架**

   创建以下文件：

   ```
   .flow/
   ├── config.yaml          ← 项目配置
   ├── onboarding.md        ← 子 agent 启动指南（模板）
   ├── services.md          ← 服务地图
   └── templates/
       ├── assign.md        ← 指令包模板
       └── report.md        ← 汇报模板
   ```

   **config.yaml** 结构：
   ```yaml
   project:
     name: "{用户输入}"
     role: "orchestrator"
     created: "{日期}"

   services:
     - name: "{服务名}"
       path: "./{目录}"
       type: "{BFF / data-service / admin / ...}"

   knowledge_base:
     enabled: true/false
     path: "{用户输入}"
     child_write: true
     review_on_archive: true

   conventions:
     task_id_prefix: "{用户输入}"
     branch_pattern: "feature/<kebab-case>"
     commit_format: "{prefix}-{id} {type}: {description}"

   child_agent:
     spec_tool: "{用户输入}"
     onboarding_doc: ".flow/onboarding.md"
   ```

   **onboarding.md**：生成子 agent 启动指南，包含：
   - 角色说明（多 agent 系统中的执行者）
   - 如何读取分配的任务（从根目录的 next-tasks.md）
   - 工作循环：接收任务 → 设计 → 编码 → 验证 → 汇报
   - 汇报格式参考
   - 知识库规则（如启用）
   - 提交约定

   **services.md**：从服务列表生成：
   - 表格：服务名、目录、类型、职责简述
   - 说明子 agent 可参考此文件定位跨服务依赖

4. **初始化子 agent 配置**

   对每个声明的服务，创建：
   ```
   {service-path}/.flow/
   └── config.yaml
   ```

   使用 `child-config.yaml.tmpl` 模板渲染，注入以下变量：

   | 变量名 | 来源 | 说明 |
   |--------|------|------|
   | `project.name` | 用户输入 | 项目名称 |
   | `root_path` | 计算得出 | 从服务目录到根目录的相对路径 |
   | `service_name` | 服务列表 | 当前服务名 |
   | `knowledge_base.enabled` | 用户输入 | 知识库是否启用 |
   | `knowledge_base.path` | 用户输入 | 知识库路径 |
   | `knowledge_base.child_write` | 用户输入 | 子 agent 写权限 |
   | `conventions.task_id_prefix` | 用户输入 | 任务号前缀 |
   | `conventions.branch_pattern` | 用户输入 | 分支命名模式 |
   | `conventions.commit_format` | 用户输入 | 提交格式 |
   | `child_agent.spec_tool` | 用户输入 | 子 agent spec 工具 |
   | `child_agent.onboarding_doc` | 用户输入 | onboarding 文档路径 |

   **重要**：写入服务目录前必须征求用户同意。部分服务可能有独立 git 仓库。

5. **输出摘要**

   展示：
   - 项目名称和根路径
   - 已配置的服务数量
   - 知识库状态
   - 约定配置
   - 提示："项目已初始化。使用 `/flow:init <需求描述>` 创建需求。"

---

## 模式 B：创建新需求（`.flow/` 已存在）

**步骤**

1. **读取项目配置**

   读取 `.flow/config.yaml` 获取：项目名、服务列表、知识库配置、约定。

2. **分析需求**

   根据用户输入（参数或对话），判断：
   - 需求内容是什么？
   - 涉及哪些服务？
   - 是否有跨服务依赖？
   - 复杂度等级：
     - Tier 1：单服务，无跨服务变更
     - Tier 2：2-5 个服务，有明确依赖链
     - Tier 3：5+ 个服务，需分阶段上线（当前尚未实现，按 Tier 2 处理）

   如需求不清晰，使用 **AskUserQuestion** 澄清：
   - 涉及哪些服务？
   - 预期范围？
   - 已知约束或依赖？

   如配置了知识库，提醒用户查阅相关知识获取上下文。

3. **确定 change 名称**

   从需求描述生成 kebab-case 名称。
   如 "统一登录系统" → `unified-login-system`

   请用户确认或修改。

4. **生成需求产物**

   创建：
   ```
   .flow/changes/{change-name}/
   ├── proposal.md
   ├── tasks.md
   └── next-tasks.md    （仅 Tier 2+ 生成）
   ```

   **proposal.md** 结构：
   ```markdown
   # {需求标题}

   ## 背景
   {为什么要做这个需求}

   ## 目标
   {要达到什么效果}

   ## 涉及服务
   | 服务 | 职责 | 依赖 |
   |------|------|------|
   | {名称} | {做什么} | {依赖谁} |

   ## 开发顺序
   1. {service-a}（无依赖，先开发）
   2. {service-b}（依赖 service-a 的接口）

   ## 接口契约
   {跨服务 API 定义 — 初稿可粗略}

   ## 分支策略
   分支：{branch-pattern}/{change-name}
   所有服务使用相同分支名。

   ## 非目标
   {明确不做的事项}
   ```

   **tasks.md** 结构：
   ```markdown
   ---
   requirement: {标题}
   status: planning
   tier: {1/2/3}
   branch: {分支名}
   services: [{服务列表}]
   created: {日期}
   updated: {日期}
   ---

   ## 开发顺序

   1. {service} — {原因}
   2. {service} — {原因}

   ---

   ## {service-name}
   > child agent change: `{待创建}`

   - [ ] {任务描述}
   - [ ] {任务描述}

   ## {service-name}
   > child agent change: `{待创建}`
   > blocked by: [{service}] {接口}

   - [ ] {任务描述}
   ```

   **next-tasks.md**（仅 Tier 2+）：
   ```markdown
   # {服务名} 待开发任务

   ## 上下文
   {与整体需求的关系简述}

   ---

   ## 任务 1: {标题}

   ### 需求
   {具体要实现什么}

   ### 涉及接口/文件
   {需要修改的内容}

   ### 注意事项
   {约束、边界条件}

   ---

   ## 待明确问题
   1. {问题}
   ```

5. **展示并确认**

   将生成的产物展示给用户审阅。
   用户确认后写入文件。

   提示："需求已创建。使用 `/flow:assign <service-name>` 分配任务给子 agent。"

---

**约束**

- 不硬编码任何项目特定的路径、名称或约定 — 全部从 `.flow/config.yaml` 读取
- 模式 A 中，写入服务子目录前必须征求用户同意
- 模式 B 中，写入文件前必须展示产物供用户审阅
- 如配置了知识库，在需求分析阶段提醒用户查阅相关知识
- Tier 分级影响生成内容（next-tasks.md 仅 Tier 2+ 生成）
- change 名称必须 kebab-case，不含日期（日期在元数据中）
- 如同名 change 已存在，询问用户处理方式（重命名 / 继续 / 取消）