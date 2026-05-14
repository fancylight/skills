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

   读取 `~/.claude/commands/flow/templates/task-md-maintenance.md`，按第 3.3 节（变更重开）和第 3.4 节（新增 spec）操作。

   **核心规则：优先修正原 spec，而非新建 spec。**

   - **变更影响已完成（`[x]`）的 spec** → 重开：`[x]` → `[ ]`，**清除**旧的 `完成：date commit hash`，条目末尾添加 `⚠️ 设计修正（{date}）：{1行简述}，详见变更通知`。条目不超过 6 行。
   - **变更影响未完成的 spec** → 直接修改 spec 的边界/依赖描述（重写条目，不追加）
   - **全新范围的变更** → 才新建 spec（必须是没有现有 spec 能覆盖的全新工作范围）
   - 如有新增服务，追加新服务章节
   - 如有删除服务，将对应章节标注为 `~~已取消~~`
   - 更新元数据头 `updated` 日期和 `status`（如需要）
   - 同步更新 `开发顺序` 和 `完成检查清单`

5. **同步修改子服务 spec 文件**

   对于步骤 4 中被重新打开的 spec，使用 spec skills 更新子服务的 spec 文件。

   从 `.flow/config.yaml` 读取 `child_agent.spec_tool`。

   使用对应的 spec skills（如 `opsx:propose`）更新 spec 目录下的 design.md，追加变更记录段：

   ```
   ## 变更记录 — {YYYY-MM-DD}

   变更类型：{设计修正 / 需求调整 / 接口契约变更}
   变更内容：{具体修改了什么}
   原因：{为什么需要修改}
   影响：{哪些文件/接口需要调整}
   注意：此 spec 已被修正，下次 /flow:apply 时需按新设计执行
   ```

   **不手动修改 spec 文件**——spec 文档的创建和维护由 spec skills 负责。
   **这是必须步骤，不可跳过。不修改子服务 design.md 会导致子 agent 拿到过时设计。**

6. **写入变更通知**

   按 `~/.claude/commands/flow/templates/task-md-maintenance.md` 第 2.6 节格式，在 task.md 末尾 `## 变更通知（待子 agent 感知）` 章节追加 **1 行索引**：

   ```
   - **{service}**：{spec-id} {变更类型} — {1行简述}
   ```

   **不在变更通知中展开详细修改内容**——详细信息记录在 `概要设计.md` 变更记录 + 子服务 `design.md` 变更记录段。

7. **输出变更摘要**

   展示所有修改内容，用户确认后写入文件。
   提示："变更已更新。受影响子 agent 下次执行 `/flow:receive` 时会读到变更通知。"

---

**约束**

- task.md 维护规则详见 `~/.claude/commands/flow/templates/task-md-maintenance.md`
- **已完成（`[x]`）的 spec 被变更影响时，必须重开原 spec，而非新建。只有全新范围才新建。**
- 重开 spec 时**必须清除**旧的完成记录（日期、commit hash），**不能**保留删除线旧记录
- 变更通知只写 1 行索引，详细内容记录在 `概要设计.md` 和子服务 `design.md`
- **子 agent 的 spec 文档由 spec skills（`child_agent.spec_tool`）创建和维护**，根 agent 不手动修改 spec 文件
- 根 agent 必须同步更新子服务的 design.md，不能只更新根 task.md