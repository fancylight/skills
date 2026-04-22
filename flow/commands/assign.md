---
name: "Flow: Assign"
description: "Generate an instruction package for a child agent"
category: Workflow
tags: [workflow, orchestration, multi-agent]
---

为指定服务生成子 agent 指令包，用户复制给子 agent 会话即可启动工作。

**输入**：`/flow:assign <service-name> [任务描述]`

- `service-name`：必填，目标服务名称（需在 `.flow/config.yaml` 的 services 中）
- 任务描述：可选，不提供则从 tasks.md 中提取未完成任务

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认指定的 service 在配置的 services 列表中
3. 确认有活跃的 change（`.flow/changes/` 下非 `archive/` 的目录）

如有多个活跃 change，使用 **AskUserQuestion** 让用户选择。
如只有一个，自动选中并告知用户。

---

**步骤**

1. **读取需求上下文**

   读取活跃 change 的：
   - `proposal.md` — 需求背景
   - `tasks.md` — 任务清单，找到该服务的未完成任务
   - `next-tasks.md` — 如存在，获取详细任务说明

2. **收集跨服务上下文**

   从 `tasks.md` 中分析：
   - 该服务是否有依赖（`blocked by` 标记）
   - 依赖的服务是否已完成
   - 已完成服务的 api.md 是否可用

   如有已完成的上游服务，读取其 api.md 作为接口契约参考。

3. **确定任务号**

   如配置了 `task_id_prefix`：
   - 生成任务号：`{prefix}-{自增ID}`
   - ID 从 tasks.md 中已有的最大编号 +1

   如未配置前缀，跳过任务号。

4. **生成指令包**

   根据 `.flow/templates/assign.md` 模板（如存在）或默认格式生成：

   ```markdown
   你好，我是 {service-name} 的子 agent。

   ## 启动指引
   请先阅读以下文件：
   1. {onboarding_doc 的绝对路径}
   2. {next-tasks.md 的绝对路径}（找到你的任务）

   ## 当前任务
   根 agent 指派任务：{任务简述}
   任务号：{prefix}-{id}（用于 commit message）

   需求：{具体需求描述}

   ## 跨服务上下文
   {依赖服务状态、已就绪的接口契约}

   ## 工作要求
   1. 创建 TodoList（使用 TaskCreate）
   2. 设计阶段（使用你的 spec 工具，如 /opsx:propose）
   3. 完成后告知用户："设计已完成，请审阅"
   4. 用户审阅通过后开始编码
   5. 完成验证清单（编译通过、测试通过）
   6. 提交代码（格式：{commit_format}）
   7. 执行 /flow:report 提交汇报

   注意：现在只做设计，不写代码。等用户审阅通过后再编码。
   ```

5. **输出指令包**

   将指令包完整输出，提示用户：
   "指令包已生成。复制以上内容到 {service-name} 的子 agent 会话中即可。"

6. **更新 tasks.md**

   在对应服务章节标注已分配：
   - 添加分配日期
   - 标注任务号

---

**约束**

- 指令包中的路径必须是绝对路径（子 agent 在不同目录工作）
- 如服务有 `blocked by` 依赖且依赖未完成，警告用户但不阻止分配
- 如 next-tasks.md 中没有该服务的详细任务，从 tasks.md 提取简要任务列表
- 指令包中不包含根 agent 的内部实现细节，只包含子 agent 需要知道的信息
- 工作要求中的 spec 工具引用从 `child_agent.spec_tool` 配置读取