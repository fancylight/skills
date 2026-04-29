---
name: "Flow: Assign"
description: "Root agent generates an instruction package for a child agent, including spec list, overview design path, and work phase guidance"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.2.0"
---

为指定服务生成子 agent 指令包，用户复制给子 agent 会话即可启动工作。

**输入**：`/flow:assign <service-name>`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认指定的 service 在 services 列表中，且 `flow_initialized: true`
   - 若 `flow_initialized: false`，提示："该服务尚未初始化，子 agent 收到指令包后需先执行 /flow:init"
3. 确认有活跃 change；多个时 **AskUserQuestion** 选择

---

**步骤**

1. **读取需求上下文**

   读取活跃 change 的：
   - `概要设计.md` — 整体方案和接口契约
   - `task.md` — 找到该服务的 spec 列表（含边界、依赖）

2. **分析依赖状态**

   从 task.md 中找到该服务的 `blocked by` 标记：
   - 依赖服务已完成（`[x]`）→ 读取其 api.md 作为接口契约参考
   - 依赖服务未完成 → 警告用户但不阻止分配

3. **确定任务号**（如配置了 `task_id_prefix`）

   从 task.md 已有的最大编号 +1，生成 `{prefix}-{id}`。

4. **生成指令包**

   ```
   你好，我是 {service_name} 的子 agent。

   ## 启动指引
   请先阅读：
   1. {onboarding_path}（二级架构说明和开发规范）
   2. 确认本服务的 .flow/config.yaml 存在，否则先执行 /flow:init

   ## 当前任务
   需求：{change-name}
   {task_id 如有：任务号：{prefix}-{id}}

   ## 待完成 Spec
   {每个 spec 一行：- spec{n}: {名称}（边界：{边界}，依赖：{依赖}）}

   ## 参考文档
   - 概要设计：{概要设计.md 绝对路径}
   - 知识库：{knowledge_base_path 如启用}

   ## 跨服务上下文
   {cross_service_context：依赖服务状态、已就绪接口契约}

   ## 工作要求
   1. 执行 /flow:receive 接收任务（自动加载工作协议）
   2. 执行 /flow:design 完成 spec 设计并自检
   3. 设计评审通过后进入编码（每个 spec：apply → 内联审核 → 单元测试）
   4. 所有 spec 完成后执行 /flow:report
   {commit_format 如有：提交格式：{commit_format}}

   注意：先做设计，等评审通过再编码。
   ```

5. **更新 task.md**

   在对应服务章节追加：
   - 分配日期
   - 任务号（如有）

---

**约束**

- 指令包中的路径必须是绝对路径
- 指令包不包含根 agent 内部实现细节
- 不阻止分配有依赖未完成的服务，但必须在指令包中注明依赖状态