---
name: "Flow: Assign"
description: "Root agent assigns work to a child agent — inline execution or instruction package for independent session"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.3.0"
---

为指定服务派发任务给子 agent。支持 spec 和 hotfix 两种类型。**根 agent 只负责生成提示词和派发，不编码、不提交、不更新 task.md spec 状态。**

**输入**：`/flow:assign <service-name>`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认指定的 service 在 services 列表中，且 `flow_initialized: true`
   - 若 `flow_initialized: false`，提示："该服务尚未初始化，请先在服务目录执行 /flow:init"
3. 确认有活跃 change；多个时 **AskUserQuestion** 选择

---

**步骤**

1. **读取需求上下文**（只取概要信息，不读设计内容）

   读取活跃 change 的：
   - `task.md` — 找到该服务的 spec 列表（只取名称和依赖状态）和 `### Hotfix` 子章节（如有）
   - 子服务的 `.flow/config.yaml` — 读取 `inline_agents.knowledge_maintenance.auto_trigger`
   - 不读取 design.md 或 fix.md 内容——那是子 agent 的工作

2. **分析依赖状态和 KB 责任**

   从 task.md 中检查该服务的 `blocked by` 标记：
   - 依赖服务已完成（`[x]`）→ 注明接口契约已就绪
   - 依赖服务未完成 → 警告用户但不阻止分配

   根据 `auto_trigger` 确定 KB 维护责任：
   - `true`：子 agent 在 report 时自动维护，根 agent 无需关注
   - `false`：子 agent report 只输出 KB 维护提示，**根 agent 需要在子 agent 完成后执行 `/flow:kb`**

3. **确定任务号和时间戳**（如配置了 `task_id_prefix`）

   从 task.md 已有的最大编号 +1，计算建议编号。使用 **AskUserQuestion** 让用户确认或修改。

   生成进度文件时间戳：`{YYYYMMDD-HHmmss}`（当前时刻），用于进度文件名。

4. **选择分配模式**

   使用 **AskUserQuestion** 选择：
   - **内联执行**：根 agent 使用 Agent tool 为每个 spec 启动一个**内联 agent**（无持久记忆，随根会话结束而消失）。适合小需求、spec 少的场景。
   - **独立指令包**：根 agent 输出提示词，用户在服务目录手动启动**独立会话**（有持久记忆，适合长期工作）。适合大需求、spec 多的场景。

5. **选择任务并生成清单**

   从 task.md 提取本服务所有未完成项（spec + hotfix），展示给用户。
   使用 **AskUserQuestion** 让用户选择本次要派发的任务（可多选）。**1 task = 1 agent = 1 commit**。

6. **生成提示词**（每个任务独立一份）

   读取 `~/.claude/commands/flow/templates/child-agent-prompt.md`，替换变量后传给子 agent。
   **严格按模板内容，不添加、不删减。** 模板变量：
   - `{service_name}`、`{服务绝对路径}`、`{root_path 绝对路径}`
   - `{change_name}`、`{spec_name}`、`{timestamp}`、`{task_type}`
   - `{kb_auto_trigger}` — 步骤1读取的 `auto_trigger` 值

7. **创建进度文件**

   为每个选中任务创建进度文件，供子 agent 写入各阶段状态。

   - 创建目录 `{服务绝对路径}/.flow/{change_name}/spec/`（如不存在）
   - 创建文件 `progress-{timestamp}.md`，写入初始内容：

   ```
   # {spec_name} — 进度与报告
   需求：{change_name}
   服务：{service_name}
   时间戳：{timestamp}

   - [ASSIGN] {date} — 已分配，等待接收
   ```

8. **执行分配**

   **模式 A：内联执行**

   按依赖顺序，**每个任务启动一个内联 agent**（Agent tool）。hotfix 无依赖，可优先或并行执行：
   ```
   hotfix-xxx（无依赖，跳过设计）→ 内联 agent 1 → 等待完成
   spec1（无依赖）→ 内联 agent 2 → 等待完成
   spec2（依赖 spec1）→ 内联 agent 3 → 等待完成
   ```

   每个内联 agent 自行完成：receive → apply → report。
   根 agent 只负责按顺序启动和接收结果，**不编码、不提交、不更新 task.md**。
   派发后告知用户进度文件位置：`{服务绝对路径}/.flow/{change_name}/spec/progress-{timestamp}.md`。

   **模式 B：独立指令包**

   为每个任务输出独立指令包，用户在服务目录手动启动**独立会话**后粘贴，按依赖顺序逐个粘贴。hotfix 可优先执行。

8. **更新 task.md 元数据**

   读取 `~/.claude/commands/flow/templates/task-md-maintenance.md`，按第 3.5 节（分配任务）操作。

   **替换**对应服务章节的头部状态行为：
   ```
   > 状态：🔄 开发中 | 分配日期：{date} | 模式：{内联/独立} | 任务号：{id}
   ```
   
   只更新头部状态行，**不追加**历史分配记录，**不更新 spec 完成状态**——那是 `/flow:report` 的职责。

---

**约束**

- task.md 维护规则详见 `~/.claude/commands/flow/templates/task-md-maintenance.md`
- **1 task = 1 spec = 1 agent = 1 commit**
- 根 agent **不**读取 design.md 内容、**不**编码、**不**提交、**不**更新 spec 完成状态
- 服务头部状态行**替换**，**不追加**历史分配记录
- 内联模式：每个 agent 启动后第一件事是自检（输出协议 + 验证 flow skills），不通过立即终止
- **派发输出从简**：只输出 1 行确认（服务、spec、任务号、模式），不渲染表格、不描述 agent 后续流程