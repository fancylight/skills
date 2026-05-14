---
name: "Flow: Design"
description: "Design phase — root agent creates overview design, task.md, and per-spec proposal+design; child mode (advanced) for autonomous spec design when knowledge base is mature"
category: Workflow
tags: [workflow, orchestration, multi-agent, design]
version: "0.1.0"
---

设计阶段命令，根据 `role` 自动切换行为：

- **根 agent（orchestrator）**：与用户协力完成概要设计、task.md，并为每个 spec 在子服务创建 proposal + design（现阶段主线）
- **子 agent（executor）**：为每个 spec 做 proposal + design，完成后内联自检（远期目标，需知识库成熟后启用）

---

## 前置检查

读取 `.flow/config.yaml`，确认存在且角色正确。
如不存在，提示："请先执行 `/flow:init` 初始化。"

---

## 根模式（role: orchestrator）

**职责**：生成 `概要设计.md` + `task.md`，并为每个 spec 创建 proposal.md + design.md。

**步骤**

1. **确定 change 目录**

   扫描 `.flow/changes/`，找到活跃 change（排除 `archive/`）。
   - 无活跃 change：使用 **AskUserQuestion** 收集需求名，生成 `{需求名}-{YYYYMMDD}` 目录
   - 一个：自动选中
   - 多个：AskUserQuestion 让用户选择

2. **需求分析**

   根据用户输入（命令参数或对话）分析：
   - 涉及哪些服务？（对照 config.yaml 的 services 列表）
   - 服务间是否有接口依赖？
   - 复杂度：Tier 1（单服务）/ Tier 2（2-5服务）/ Tier 3（5+服务，按 Tier 2 处理）

   如启用知识库，提醒用户查阅相关历史方案。
   如需求不清晰，使用 **AskUserQuestion** 澄清边界。

3. **与用户协力生成 `概要设计.md`**

   **强制交互规则**：根模式设计必须与用户交互，不能自动生成完所有内容。以下节点必须使用 **AskUserQuestion** 暂停确认：
   - 涉及哪些服务、服务间依赖关系确认
   - 接口契约草稿的关键字段/类型确认
   - 验收标准确认
   - 非目标确认

   使用 `overview-design.md.tmpl` 模板渲染，注入以下变量：

   | 变量名 | 来源 | 说明 |
   |--------|------|------|
   | `requirement_title` | 用户输入 | 需求标题 |
   | `services` | config.yaml | 涉及服务列表（name, responsibility, dependency） |
   | `branch_pattern` | config.yaml | 分支模式 |
   | `change_name` | 步骤 1 | change 目录名 |
   | `acceptance_criteria` | 用户输入 | 验收标准（必须章节） |
   | `non_goals` | 用户输入 | 非目标 |

   模板文件：`~/.claude/commands/flow/templates/overview-design.md.tmpl`。

4. **生成 `task.md`**

   读取 `~/.claude/commands/flow/templates/task-md-maintenance.md`，按第 2 节格式规范生成 task.md。

   必须包含：
   - YAML 元数据头（requirement, type, status, tier, branch, services, created, updated）
   - `## 开发顺序` — 依赖拓扑排序，依赖引用必须用 spec ID（c{n}）
   - 每个服务一个 `## {service-name}` 章节，含头部状态行和 spec 条目
   - `## 完成检查清单`
   - spec 条目格式：`- [ ] {spec-id}: {标题}` + 边界 + 依赖

5. **为每个 spec 创建设计文档**

   从 `.flow/config.yaml` 读取 `child_agent.spec_tool` 和服务 `path`。

   按 task.md 的 spec 列表，对每个 spec 按依赖顺序处理（无依赖先做）：

   a. 确定 spec 所属服务 → 从 config.yaml 获取该服务的绝对路径
   b. **spec 父目录**：`{服务绝对路径}/openspec/changes/`（opsx 工具链约定路径）
   c. 使用 spec skills（如 `opsx:propose`）在上述父路径下创建标准 spec 目录 `c{序号}-{kebab-case}/`，内含 proposal.md、design.md 等标准文件

   **design.md 必须章节**：
   - `## 实现方案` — 接口列表、数据结构、逻辑流程
   - `## DDL` — 如涉及数据库变更
   - `## 数据迁移` — 如有数据迁移逻辑
   - `## 单元测试计划` — 必须章节，列出每个接口/功能的测试场景
   - `## 非目标` — 明确不做的事项

   **不手动创建 spec 文件**——spec 文档的创建和维护由 spec skills 负责。
   与用户交互确认关键设计决策。

6. **展示并确认，写入文件**

   展示所有产物（概要设计.md、task.md、各 spec 的 proposal.md + design.md）供用户审阅，确认后写入。
   提示："设计完成。使用 `/flow:assign <service>` 分配任务给子 agent 进行编码。"

---

## 子模式（role: executor）【远期目标】

**前置条件**：知识库成熟后启用。当前主线由根模式完成 spec 设计。

**职责**：为本服务每个 spec 做 proposal + design，内联自检，输出评审报告。

**前置**：已执行 `/flow:receive`，已知当前活跃 change 和 spec 列表。

**步骤**

1. **读取 spec 列表**

   从根 `task.md` 中找到本服务（`service_name`）章节，提取：
   - 每个 spec 的名称、边界定义、依赖关系

2. **读取参考文档**

   - 将 `root_path` 与当前工作目录拼成绝对路径，用 **Read 工具**读取 `{绝对根路径}/.flow/changes/{change}/概要设计.md` — 整体方案和接口契约草稿
   - 知识库相关文档（如启用）

3. **为每个 spec 创建设计文档**

   **目录命名规范**：spec 工作目录必须使用格式 `c{序号}-{kebab-case描述}`，如：
   - `c1-config-data-layer`
   - `c3-float-data-layer`
   - `c5-float-util`

   序号与 task.md 中该服务 spec 的出现顺序一致（c1, c2, c3...）。

   在每个 spec 工作目录下创建：
   - `proposal.md`：spec 的背景、目标、非目标
   - `design.md`：具体实现方案、涉及的接口/数据结构

   **design.md 必须章节**：

   - `## 实现方案` — 接口列表、数据结构、逻辑流程
   - `## DDL` — 如涉及数据库变更（CREATE TABLE / ALTER TABLE，含字段名、类型、约束、索引）
   - `## 数据迁移` — 如有数据迁移逻辑
   - `## 单元测试计划` — **必须章节**。列出每个接口/功能的测试场景：
     | 测试场景 | 输入 | 期望输出 | 涉及的类/方法 |
     |----------|------|----------|--------------|
     | 正常查询 | userId=1 | 返回权限列表 | PermissionService.query |
     | 空结果 | userId=999 | 返回空列表 | PermissionService.query |
   - `## 非目标` — 明确不做的事项

   按依赖顺序处理（无依赖的 spec 先做）。

4. **内联启动设计评审 agent**

   使用 **Agent tool** 启动内联评审 agent，传入：
   - 本服务所有 spec 的 proposal.md + design.md 路径
   - `概要设计.md` 路径
   - task.md 中本服务的 spec 边界定义

   评审 agent 检查维度（**专注，不发散**）：
   - 每个 spec 边界是否与 task.md 定义一致
   - 依赖的接口是否在概要设计中有定义
   - spec 间依赖顺序是否与 task.md 一致
   - 接口路径/字段是否与概要设计契约草稿对齐
   - **❌ spec 目录命名是否符合 `c{序号}-{描述}` 格式**
   - **❌ design.md 是否包含 `## 单元测试计划` 章节，且覆盖了所有接口/功能点**

5. **输出自检报告**

   ```
   ## 设计自检报告

   ### spec1: {名称}
   - ✅ 边界符合 task.md 定义
   - ✅ 依赖接口在概要设计中已定义
   - ⚠️ 差异：响应字段比概要设计多了 extra_field，请确认

   ### spec2: {名称}
   - ❌ 问题：依赖的 token 格式在概要设计中未定义

   ### 总结
   通过：1 个 | 有差异（可接受）：1 个 | 有问题（需修改）：1 个
   ```

   - 无 ❌：告知用户"设计完成，自检通过，请评审"
   - 有 ❌：提示"请修改后重新执行 /flow:design"

---

**约束**

- 根模式：`验收标准` 是必须章节，不可省略
- 根模式：**子 agent 的 spec 文档由 spec skills（`child_agent.spec_tool`）创建和维护**，不直接手写 spec 文件
- 子模式【远期】：spec 目录命名 `c{序号}-{kebab-case描述}`，design.md 必须含 `## 单元测试计划`
- 子模式【远期】：评审有 ⚠️ 但无 ❌ 时照常输出"自检通过"，差异在报告中注明