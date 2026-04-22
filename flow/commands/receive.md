---
name: "Flow: Receive"
description: "Child agent receives and starts an assigned task"
category: Workflow
tags: [workflow, orchestration, multi-agent, executor]
version: "0.1.0"
---

子 agent 接收根 agent 分配的任务并启动工作。

**输入**：`/flow:receive` 无参数。自动从配置和根目录读取任务。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 从配置读取 `root_path` 和 `service_name`

如配置不存在，提示用户：
"当前目录未配置为子 agent。请先在根目录执行 `/flow:init` 初始化项目。"

---

**步骤**

1. **定位根目录活跃需求**

   扫描 `{root_path}/.flow/changes/` 目录：
   - 排除 `archive/` 子目录
   - 剩余的即为活跃需求

   如有多个活跃需求，使用 **AskUserQuestion** 让用户选择。
   如只有一个，自动选中。

2. **读取任务信息**

   读取活跃 change 的：
   - `tasks.md` — 找到本服务（`service_name`）的任务章节
   - `next-tasks.md` — 如存在，获取详细任务说明
   - `proposal.md` — 获取需求背景

   提取本服务的：
   - 未完成任务列表（`- [ ]` 项）
   - 任务号（如有）
   - 依赖状态（`blocked by` 标记）
   - 跨服务上下文

3. **读取 onboarding 文档**

   读取 `{root_path}/.flow/onboarding.md`，理解工作规范。

4. **输出任务摘要**

   展示：
   ```
   ## 任务接收

   需求：{需求名称}
   服务：{service_name}
   任务号：{prefix}-{id}（如有）

   ### 待完成任务
   - [ ] {任务 1}
   - [ ] {任务 2}
   ...

   ### 依赖状态
   - {service-x}：✅ 已完成（api.md 可用）
   - {service-y}：⏳ 进行中

   ### 工作流程
   1. 创建 TodoList
   2. 设计阶段（使用 spec 工具）
   3. 用户审阅
   4. 编码实现
   5. 验证清单
   6. 提交 + /flow:report
   ```

5. **创建 TodoList**

   使用 **TaskCreate** 为每个待完成任务创建 todo 项。

6. **等待用户确认开始**

   "任务已加载，准备开始。先进入设计阶段？"

---

**约束**

- 只读取本服务相关的任务，不读取其他服务的任务
- 如有 `blocked by` 依赖且依赖未完成，警告但不阻止
- 如根目录无活跃需求，提示用户联系根 agent 创建需求
- 读取 onboarding.md 后按其中的规范执行后续工作