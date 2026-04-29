---
name: "Flow: Design"
description: "Design phase — root agent creates overview design and task.md; child agent creates per-spec proposal+design with inline self-review"
category: Workflow
tags: [workflow, orchestration, multi-agent, design]
version: "0.1.0"
---

设计阶段命令，根据 `role` 自动切换行为：

- **根 agent（orchestrator）**：与用户协力完成概要设计和 task.md
- **子 agent（executor）**：为每个 spec 做 proposal + design，完成后内联自检

---

## 前置检查

读取 `.flow/config.yaml`，确认存在且角色正确。
如不存在，提示："请先执行 `/flow:init` 初始化。"

---

## 根模式（role: orchestrator）

**职责**：生成 `概要设计.md` + `task.md`（含 spec 粒度定义和验收标准）。

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

   结构：
   ```markdown
   # {需求标题}

   ## 背景
   {为什么要做}

   ## 目标
   {要达到什么效果}

   ## 涉及服务
   | 服务 | 职责 | 依赖 |
   |------|------|------|
   | {name} | {做什么} | {依赖谁} |

   ## 开发顺序
   1. {service-a}（无依赖，先开发）
   2. {service-b}（依赖 service-a 的接口）

   ## 接口契约草稿
   {跨服务 API 定义初稿}

   ## 分支策略
   分支：{branch-pattern}/{change-name}，所有服务使用同一分支名。

   ## 验收标准
   {集成测试的依据，必须章节，描述端到端可验证的行为}

   ## 非目标
   {明确不做的事项}
   ```

4. **生成 `task.md`**

   按服务分组，每个 spec 含名称 + 一句话边界 + 依赖：

   ```markdown
   ---
   requirement: {标题}
   type: feature
   status: planning
   tier: {1/2/3}
   branch: {分支名}
   services: [{服务列表}]
   created: {YYYY-MM-DD}
   updated: {YYYY-MM-DD}
   ---

   ## 开发顺序

   1. {service-b}（无依赖）
   2. {service-a}（依赖 service-b spec1）

   ---

   ## {service-b}

   > 状态：📋 待开始 | 分配日期：—

   - [ ] spec1: {名称}
         边界：{一句话，明确不做什么}
         依赖：无
   - [ ] spec2: {名称}
         边界：{一句话}
         依赖：spec1

   ## {service-a}

   > 状态：⏳ 阻塞（等待 service-b spec1）| 分配日期：—

   - [ ] spec1: {名称}
         边界：{一句话}
         依赖：service-b spec1（{接口描述}）
   ```

5. **展示并确认，写入文件**

   展示生成的两个文件供用户审阅，确认后写入。
   提示："设计完成。使用 `/flow:assign <service>` 分配任务给子 agent。"

---

## 子模式（role: executor）

**职责**：为本服务每个 spec 做 proposal + design，内联自检，输出评审报告。

**前置**：已执行 `/flow:receive`，已知当前活跃 change 和 spec 列表。

**步骤**

1. **读取 spec 列表**

   从根 `task.md` 中找到本服务（`service_name`）章节，提取：
   - 每个 spec 的名称、边界定义、依赖关系

2. **读取参考文档**

   - `{root_path}/.flow/changes/{change}/概要设计.md` — 整体方案和接口契约草稿
   - 知识库相关文档（如启用）

3. **为每个 spec 创建设计文档**

   在 spec 工作区（如 `openspec/changes/{spec-name}/`）创建：
   - `proposal.md`：spec 的背景、目标、非目标
   - `design.md`：具体实现方案、涉及的接口/数据结构

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
- 子模式：评审只检查与概要设计/task.md 的一致性，不评价方案优劣，不检查代码
- 子模式：有 ⚠️ 但无 ❌ 时照常输出"自检通过"，差异在报告中注明
- change 目录名格式：`{需求名}-{YYYYMMDD}`（需求名为 kebab-case）