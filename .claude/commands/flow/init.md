---
name: "Flow: Init"
description: "Initialize flow scaffold for root or child agent — creates .flow/ config and required files only, no design work"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.2.0"
---

初始化 `.flow/` 必要文件。**只创建配置和规范文档，不做需求分析或设计。**

两种模式由 `role` 决定：
- 当前目录无 `.flow/config.yaml` → 询问角色后初始化
- 当前目录已有 `.flow/config.yaml` → 提示已初始化，无需重复操作

---

## 模式 A：根 agent 初始化（role: orchestrator）

**触发条件**：用户在项目根目录执行，希望作为编排者。

**步骤**

1. **检测项目结构**

   扫描当前目录子目录，识别服务：含 `pom.xml`、`package.json`、`go.mod`、`Cargo.toml`、`.git/`、`src/` 的目录。展示检测结果供用户确认。

2. **收集配置**

   使用 **AskUserQuestion** 收集：
   - 项目名称（默认目录名）
   - 服务列表（确认/编辑检测结果）
   - 知识库：路径（无则跳过）
   - 约定：任务号前缀（可选）、分支模式、提交格式
   - 子 agent spec 工具（如 opsx、无）

3. **生成文件**

   ```
   .flow/
   ├── config.yaml          ← 项目配置（role: orchestrator）
   ├── onboarding.md        ← 二级架构说明 + 子 agent 开发规范（所有子 agent 共享）
   ├── services.md          ← 服务地图
   └── 知识库说明.md         ← 仅在 knowledge_base.enabled=true 时生成
   ```

   **config.yaml**：使用 `config.yaml.tmpl` 模板渲染，注入以下变量：

   | 变量名 | 来源 | 说明 |
   |--------|------|------|
   | `project_name` | 用户输入 | 项目名称 |
   | `services` | 检测结果 | 服务列表（name, path, type, description） |
   | `knowledge_base` | 用户输入 | 是否启用、路径 |
   | `conventions` | 用户输入 | task_id_prefix, branch_pattern, commit_format |
   | `spec_tool` | 用户输入 | 子 agent spec 工具 |

   模板文件：本命令文件所在目录下的 `templates/config.yaml.tmpl`。用 Read 工具读取该文件时，先通过当前命令文件的路径推断出 `templates/` 的绝对路径，再读取。

   **onboarding.md** 内容（模板渲染）：
   - 二级 agent 架构说明（根职责：设计/编排；子职责：实现）
   - 平台限制说明（根无法自动启动子，子可内联启动审核/测试 agent）
   - 子 agent 三阶段工作循环（阶段一设计 → 阶段二编码 → 阶段三汇报）
   - 提交格式、分支规范、知识库读写规则

   **services.md**：使用 `services.md.tmpl` 模板渲染，注入以下变量：

   | 变量名 | 来源 | 说明 |
   |--------|------|------|
   | `project_name` | 用户输入 | 项目名称 |
   | `services` | 检测结果 | 服务列表（name, path, type, description） |

   **注意**：不再提前写入服务子目录，子 agent 自己 init 时注册。

4. **输出摘要**

   展示生成的文件列表，提示：
   "根 agent 初始化完成。使用 `/flow:design` 创建大需求的概要设计和 task.md。"

---

## 模式 B：子 agent 初始化（role: executor）

**触发条件**：用户在服务目录执行，或使用任意 flow 命令时检测到 `.flow/config.yaml` 缺失。

**步骤**

1. **收集配置**

   使用 **AskUserQuestion** 收集：
   - 根目录路径（`root_path`，相对当前目录）
   - 服务名称（`service_name`，默认目录名）
   - 服务描述（`description`，一句话说明该服务的职责）
   - spec 工具（`spec_tool`）
   - 单元测试命令（`test_command`，如 `mvn test`、`npm test`）
   - 是否启用内联审核 agent（默认 true）
   - 是否启用内联测试 agent（默认 true）
   - 知识库维护：自动触发还是每次询问（默认每次询问）

2. **生成文件**

   ```
   .flow/
   ├── config.yaml       ← 服务配置（role: executor）
   └── 工作流程.md        ← 本服务工作循环说明（持久化）
   ```

   **config.yaml**：使用 `child-config.yaml.tmpl` 模板渲染，注入以下变量：

   | 变量名 | 来源 | 说明 |
   |--------|------|------|
   | `project_name` | 根 config.yaml | 项目名称 |
   | `root_path` | 用户输入 | 到根目录的相对路径 |
   | `service_name` | 用户输入 | 当前服务名 |
   | `knowledge_base` | 根 config.yaml | 继承知识库配置 |
   | `conventions` | 根 config.yaml | 继承约定配置 |
   | `spec_tool` | 用户输入 | 本服务 spec 工具 |
   | `test_command` | 用户输入 | 单元测试命令 |
   | `inline_agents` | 用户输入 | 审核/测试/知识库维护配置 |

   模板文件：本命令文件所在目录下的 `templates/child-config.yaml.tmpl`。用 Read 工具读取该文件时，先通过当前命令文件的路径推断出 `templates/` 的绝对路径，再读取。

   **工作流程.md** 内容（模板渲染，注入服务信息）：
   - 基本信息（服务名、根路径、spec 工具、测试命令）
   - 阶段一：设计（receive → design → 自检 → 等待评审）
   - 阶段二：编码（apply → 内联审核 → 单元测试，逐 spec 循环）
   - 阶段三：汇报（report → 知识库判断）

3. **向根注册**

   读取根目录的 config.yaml：将用户输入的 `root_path` 与当前工作目录拼成绝对路径，再加 `/.flow/config.yaml`，用 **Read 工具**按绝对路径读取（不要用 Glob 或相对路径）。在 services 列表中找到或追加本服务条目：
   ```yaml
   - name: "{service_name}"
     path: "{相对根的路径}"
     description: "{description}"
     flow_initialized: true
     flow_initialized_at: "{YYYY-MM-DD}"
   ```

   同步更新根目录的 `services.md`：用 **Read 工具**按绝对路径读取 `{绝对根路径}/.flow/services.md`，在服务列表中找到或追加本服务行（name、path、description、状态）。

   展示两个文件的变更内容，用户确认后一并写入。
   如根 config.yaml 或 services.md 不存在，警告"根目录未初始化"但不中止。

4. **输出摘要**

   提示："子 agent 初始化完成，已向根注册。执行 `/flow:receive` 接收任务。"

---

**约束**

- 只创建文件，不做需求分析、设计或任务拆分
- 根模式：不提前写入服务子目录
- 子模式：从根 config.yaml 继承 knowledge_base 和 conventions 配置，减少重复输入
- 写入根 config.yaml 前必须展示变更并获得用户确认
- 如 `.flow/config.yaml` 已存在，提示已初始化，询问是否重新生成（覆盖）