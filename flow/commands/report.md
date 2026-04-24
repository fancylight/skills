---
name: "Flow: Report"
description: "Child agent submits a structured completion report"
category: Workflow
tags: [workflow, orchestration, multi-agent, executor]
version: "0.1.0"
---

子 agent 完成任务后提交结构化汇报，同时尝试更新根目录 tasks.md。

**输入**：`/flow:report` 无参数。自动收集当前工作信息。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 从配置读取 `root_path` 和 `service_name`

---

**步骤**

1. **收集工作信息**

   **越权行为自检（agent 必须执行）**：
   - [ ] 本次工作是否只修改了本服务目录内的文件？
   - [ ] 是否未擅自修改接口契约（与 next-tasks.md / proposal.md 中的约定一致）？
   - [ ] 是否未在其他服务中创建或修改文件？
   - [ ] 如涉及知识库写入，是否先向用户确认？
   - [ ] 如涉及数据库结构变更，是否先向用户确认？

   如以上任何一项未勾选，在汇报的【遗留问题】中明确列出越权行为及原因。

   自动检测：
   - **Git 提交**：读取 git log，按以下规则定位本次工作的 commit：
     1. 优先匹配：commit message 包含当前任务号格式（`{task_id_prefix}-{id}`）
     2. 次优匹配：自上次 `/flow:receive` 执行时间起、或最近 24 小时内的 commit
     3. 兜底：最近 5 个 commit，由用户确认
   - **Change 名称**：扫描本服务的 spec 工作区（如 `openspec/changes/`），找到最近活跃的 change
   - **接口变更**：扫描是否有 `api.md` 或 `{service}-api.md` 文件

   无法自动检测的信息，使用 **AskUserQuestion** 收集：
   - 功能简述（一句话）
   - 是否有遗留问题
   - 是否有知识库更新

2. **生成结构化汇报**

   根据 `{root_path}/.flow/templates/report.md`（如存在）或默认格式：

   ```markdown
   【归档汇报】
   服务：{service_name}
   Change：{change-name}
   功能：{一句话描述}
   Commit：{commit-id}

   【接口变更】
   - 新增：{METHOD} {path}（见 api.md）
   - 需要上游：{service} 提供 {METHOD} {path}（见 {service}-api.md）

   【知识库更新】
   - {path} — {说明}

   【遗留问题】
   - {问题描述}
   ```

   如某个章节无内容，省略该章节。

3. **尝试更新根目录 tasks.md**

   读取 `{root_path}/.flow/changes/{active-change}/tasks.md`：
   - 找到本服务章节
   - 将已完成的任务勾选 `[x]`
   - 如有新完成的任务不在列表中，追加到章节末尾
   - 更新元数据头的 `updated` 日期

   同时更新 `next-tasks.md`（如存在）：
   - 删除已完成的任务条目

   如无法写入根目录（权限问题），跳过并在汇报中说明。

4. **输出汇报**

   将汇报文本完整输出。

   如成功更新了根 tasks.md：
   "汇报已生成，根目录 tasks.md 已更新。"

   如未能更新：
   "汇报已生成。请将以上内容转达给根 agent，或手动更新根目录 tasks.md。"

---

**约束**

- 汇报格式必须结构化，便于根 agent 解析
- 只更新本服务相关的 tasks.md 条目，不修改其他服务的内容
- 如 git log 中找不到相关 commit，让用户手动提供 commit ID
- 知识库更新章节：如子 agent 在工作过程中写入了知识库，在此列出变更
- **必须在汇报前完成越权行为自检清单**
- 如发现越权行为，如实汇报并在【遗留问题】中说明，不得隐瞒