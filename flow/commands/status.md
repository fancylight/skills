---
name: "Flow: Status"
description: "View requirement progress across all services"
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.1.0"
---

查看需求在所有服务中的进度，聚合展示。

**输入**：`/flow:status [change-name]`

- `change-name`：可选，指定查看哪个需求。不提供则显示所有活跃需求。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 读取项目配置获取服务列表

---

**步骤**

1. **扫描活跃需求**

   列出 `.flow/changes/` 下非 `archive/` 的目录。

   如指定了 change-name，只查看该需求。
   如未指定且有多个活跃需求，全部展示。

2. **对每个活跃需求，读取 tasks.md**

   解析元数据头获取：需求名称、状态、Tier、分支、涉及服务。

   解析任务列表：
   - 按服务分组统计 `[x]`（完成）和 `[ ]`（未完成）
   - 识别 `blocked by` 依赖关系

3. **扫描各服务的实际状态**

   对每个涉及的服务，检查其目录：
   - 是否有活跃的 spec change（如 `openspec/changes/` 下非 archive 的目录）
   - 是否有已归档的 spec change
   - 是否有 api.md 产出

   综合判断服务状态（按以下优先级，高优先级优先）：

   **状态优先级**
   1. ⏳ 阻塞：有 `blocked by` 依赖且依赖未完成
   2. 🔄 开发中：有活跃的 spec change
   3. 📋 待开始：tasks.md 中有任务但无 spec change
   4. ✅ 完成：tasks.md 中该服务所有任务已 [x]，且有归档的 change
   5. ❓ 未知：无法访问服务目录或缺少信息

   判定规则：逐项检查，命中高优先级即停止，不再检查低优先级。

4. **输出进度报告**

   ```
   ## 需求进度：{需求名称}

   状态：{status}  |  Tier：{tier}  |  分支：{branch}
   进度：{完成服务数}/{总服务数} 服务完成

   | 服务 | 状态 | 任务进度 | 当前 change |
   |------|------|---------|------------|
   | {name} | ✅ 完成 | 3/3 | (archived) |
   | {name} | 🔄 开发中 | 1/4 | {change-name} |
   | {name} | ⏳ 阻塞 | 0/2 | 等待 {service} |
   | {name} | 📋 待开始 | 0/3 | — |

   ### 未完成任务
   - [ ] {service}: {任务描述}
   - [ ] {service}: {任务描述}（阻塞于 {dependency}）

   ### 建议下一步
   - 分配 {service} 的任务：`/flow:assign {service}`
   - {service} 阻塞中，等待 {dependency} 完成
   ```

   如有多个活跃需求，依次展示每个需求的进度。

---

**约束**

- 只读操作，不修改任何文件
- 服务状态判断基于 tasks.md + 实际目录扫描，两者综合
- 如某服务目录不存在或无法访问，标注为"未知"
- 建议下一步基于依赖关系自动推导：优先推荐无阻塞的服务