---
name: "Flow: Change"
description: "Root agent handles requirement changes mid-development — updates overview design and task.md, appends change notification for child agents"
category: Workflow
tags: [workflow, orchestration, multi-agent, change-management]
version: "0.1.0"
---

根 agent 处理大需求进行中的业务变更。更新概要设计和 task.md，写入变更通知供子 agent 下次 receive 时感知。

**输入**：`/flow:change [change-name]`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃 change（多个则 AskUserQuestion 选择）

---

**步骤**

1. **读取当前状态**

   读取活跃 change 的：
   - `概要设计.md` — 当前整体方案
   - `task.md` — 当前任务和 spec 状态（了解哪些已完成、哪些进行中）

2. **收集变更信息**

   使用 **AskUserQuestion** 收集：
   - 变更类型：需求调整 / 接口契约变更 / 服务增减 / 优先级调整
   - 变更描述（具体改了什么）
   - 变更原因
   - 影响的服务和 spec（可多选）

3. **更新 `概要设计.md`**

   在文件末尾追加变更记录章节（不覆盖原内容）：

   ```markdown
   ## 变更记录

   ### {YYYY-MM-DD} — {变更类型}
   **变更内容**：{描述}
   **影响服务**：{服务列表}
   **原因**：{原因}
   **对应 task.md 调整**：{调整说明}
   ```

   如变更影响接口契约，同步更新 `## 接口契约草稿` 章节。

4. **更新 `task.md`**

   - 修改受影响 spec 的名称/边界/依赖
   - 如有新增服务，追加新服务章节
   - 如有删除服务，将对应章节标注为 `~~已取消~~`
   - 更新元数据头 `updated` 日期和 `status`（如需要）

5. **写入变更通知**

   在 task.md 末尾追加或更新 `## 变更通知（待子 agent 感知）` 章节：

   ```markdown
   ## 变更通知（待子 agent 感知）

   - {service-a}：spec1 边界调整 — {新边界描述}，请重新评审 design
   - {service-b}：新增 spec3 — {描述}，请接收新任务
   - {service-c}：spec2 已取消
   ```

6. **输出变更摘要**

   展示所有修改内容，用户确认后写入文件。
   提示："变更已更新。受影响子 agent 下次执行 `/flow:receive` 时会读到变更通知。"

---

**约束**

- 变更通知由子 agent 下次 receive 时主动读取，根 agent 不主动推送
- 不修改已完成（`[x]`）的 spec 内容，只追加说明
- 变更记录追加而不覆盖，保留完整历史
- 展示变更摘要并获得用户确认后才写入文件