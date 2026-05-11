---
name: "Flow: Assign"
description: "Root agent assigns work to a child agent — inline execution or instruction package for independent session"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.3.0"
---

为指定服务派发任务给子 agent。**根 agent 只负责生成提示词和派发，不编码、不提交、不更新 task.md spec 状态。**

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
   - `task.md` — 找到该服务的 spec 列表（只取名称和依赖状态）
   - 不读取 design.md 内容——那是子 agent 的工作

2. **分析依赖状态**

   从 task.md 中检查该服务的 `blocked by` 标记：
   - 依赖服务已完成（`[x]`）→ 注明接口契约已就绪
   - 依赖服务未完成 → 警告用户但不阻止分配

3. **确定任务号**（如配置了 `task_id_prefix`）

   从 task.md 已有的最大指定编号 +1，生成 `{prefix}-{id}`。

4. **选择分配模式**

   使用 **AskUserQuestion** 选择：
   - **内联执行**：根 agent 使用 Agent tool 为每个 spec 启动一个**内联 agent**（无持久记忆，随根会话结束而消失）。适合小需求、spec 少的场景。
   - **独立指令包**：根 agent 输出提示词，用户在服务目录手动启动**独立会话**（有持久记忆，适合长期工作）。适合大需求、spec 多的场景。

5. **生成任务清单**

   从 task.md 提取本服务所有未完成 spec，生成任务列表。**1 task = 1 spec = 1 agent = 1 commit**。

   对每个 spec，分配独立的提示词和独立的 agent。

6. **生成提示词**（每个 spec 独立一份）

   ```
   你是 {service_name} 的内联 agent。

   ## 环境信息
   - 工作目录：{服务绝对路径}
   - 根目录：{root_path 绝对路径}
   - 活跃需求：{change_name}
   - 你的唯一任务：{spec_name}

   ## 【重要：你拥有完整的 skill 系统】
   你必须使用 Skill tool 调用 flow 命令（不是手动模拟命令步骤）：
   - Skill tool, skill="flow:receive", args="{spec_name}"  → 接收任务
   - Skill tool, skill="flow:apply", args="{spec_name}"    → 编码→审核→测试循环
   - Skill tool, skill="flow:report"                      → 提交完成报告（必须调用）

   用法示例：Skill("flow:receive", "c3-float-data-layer")

   ## 工作要求
   只完成这一个 spec。完成后必须使用 Skill tool 调用 flow:report 汇报。
   ```

7. **执行分配**

   **模式 A：内联执行**

   按 spec 依赖顺序，**每个 spec 启动一个内联 agent**（Agent tool）：
   ```
   spec1（无依赖）→ 内联 agent 1 → 等待完成
   spec2（依赖 spec1）→ 内联 agent 2 → 等待完成
   spec3（依赖 spec1）→ 内联 agent 3 → 等待完成
   ```

   每个内联 agent 自行完成：receive → design（如需要）→ apply（单 spec）→ report。
   根 agent 只负责按顺序启动和接收结果，**不编码、不提交、不更新 task.md**。

   依赖的 spec 必须先完成再启动后续。无依赖的 spec 可并行。

   **模式 B：独立指令包**

   为每个 spec 输出独立指令包，用户在服务目录手动启动**独立会话**后粘贴：

   ```
   📋 spec1 指令包
   ---
   {提示词内容}
   ---

   📋 spec2 指令包
   ---
   {提示词内容}
   ---
   ```

   提示用户：按依赖顺序逐个粘贴。

8. **更新 task.md 元数据**

   在对应服务章节追加：
   - 分配日期
   - 分配模式（内联/独立）
   - 每个 spec 对应的任务号（如有）

   只更新元数据，**不更新 spec 完成状态**——那是 `/flow:report` 的职责。

---

**约束**

- **1 task = 1 spec = 1 agent = 1 commit**：每个 spec 独立分配一个 agent
- 两种模式共享同一份提示词结构
- 根 agent **不**读取 design.md 内容、**不**编码、**不**提交代码、**不**更新 spec 完成状态
- 内联模式：根 agent 按依赖顺序逐 spec 启动 agent，每个 agent 独立完成 receive→apply→report
- 内联模式：每个 agent 启动后第一件事是目录验证（pwd + git remote -v），不匹配则拒绝操作
- 内联模式：依赖的 spec 必须先完成再启动后续 spec；无依赖的 spec 可并行
- 独立模式：每个 spec 独立一份指令包，用户按依赖顺序逐个粘贴
- 独立模式：指令包指引第一步是 `/flow:receive {spec_name}`（由 receive 判断阶段）
- 不阻止分配有依赖未完成的服务，但会警告用户