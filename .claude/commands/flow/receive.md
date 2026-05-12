---
name: "Flow: Receive"
description: "Child agent receives assigned task, loads work protocol, and enters design phase"
category: Workflow
tags: [workflow, orchestration, multi-agent, executor]
version: "0.2.0"
---

子 agent 接收根 agent 分配的任务，加载工作协议，进入阶段一（设计）。

**输入**：`/flow:receive [spec-name]`
- 无参数：读取本服务所有 spec，列出任务摘要
- 有参数：聚焦单个 spec，加载该 spec 上下文

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 读取 `root_path` 和 `service_name`

如配置不存在，强制提示：
"当前目录未初始化为子 agent。请先执行 `/flow:init` 完成初始化。"

---

**步骤**

1. **加载工作协议**

   读取 `.flow/工作流程.md`，作为本次会话的执行规范。
   将 `root_path` 与当前工作目录拼成绝对路径，用 **Read 工具**读取 `{绝对根路径}/.flow/onboarding.md`，理解二级架构规范。

2. **定位活跃 change**

   将 `root_path` 与当前工作目录拼成绝对路径，用 **Glob 工具**扫描 `{绝对根路径}/.flow/changes/`，排除 `archive/`，找到活跃 change。
   - 一个：自动选中并告知
   - 多个：**AskUserQuestion** 让用户选择
   - 无：提示"根目录无活跃需求，请联系根 agent 执行 /flow:design 创建需求"

3. **读取任务信息**

   读取活跃 change 的 `task.md`，找到本服务（`service_name`）章节，提取：
   - spec 列表（名称、边界、依赖）
   - 未完成项（`- [ ]`）
   - 依赖状态（`blocked by` 标记）

   读取 `概要设计.md`，获取整体背景和接口契约。

4. **检查变更通知**

   扫描 `task.md` 末尾的 `## 变更通知` 章节（如有），展示给用户：
   ```
   ⚠️ 发现变更通知：
   - spec1 边界已调整：{新边界描述}
   - 新增 spec3：{描述}

   请确认是否基于最新版本继续。
   ```

5. **判断当前阶段**

   检查本服务各 spec 的设计文档状态：
   - 所有 spec 无 design.md → **阶段一（设计）**
   - 所有 spec 有 design.md 但有未完成编码 → **阶段二（编码）**
   - 混合状态 → **AskUserQuestion** 让用户确认

6. **创建 TodoList**

   使用 **TaskCreate** 为每个未完成 spec 创建 todo 项。

7. **输出任务摘要**

   ```
   ## 任务接收

   需求：{需求名} | 服务：{service_name} | 当前阶段：{一/二}

   ### 待完成 spec
   - [ ] spec1: {名称}（{边界}）
   - [ ] spec2: {名称}（{边界}，依赖 spec1）

   ### 依赖状态
   - {service-x}：✅ 已完成
   - {service-y}：⏳ 进行中（阻塞 spec1）

   ### 下一步
   阶段一：执行 /flow:design 为每个 spec 创建设计文档并自检。
   阶段二：执行 /flow:apply 按 spec 顺序编码（含审核和测试循环）。
   ```

---

**约束**

- 只读取本服务相关的 spec，不读取其他服务内容
- 依赖未完成时警告用户但不阻止继续
- 工作流程.md 不存在时提示重新执行 `/flow:init`