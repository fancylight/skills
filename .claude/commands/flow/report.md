---
name: "Flow: Report"
description: "Child agent submits structured completion report, updates root task.md, and triggers knowledge base maintenance"
category: Workflow
tags: [workflow, orchestration, multi-agent, executor]
version: "0.2.0"
---

子 agent 完成编码后提交结构化汇报。**`/flow:report` 是 task.md 的唯一写入者**——根 agent（assign）和编码阶段（apply）均不更新 spec 完成状态。

**输入**：`/flow:report` 无参数，自动收集当前工作信息。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: executor`
2. 读取 `root_path`、`service_name`、`inline_agents.knowledge_maintenance` 配置

---

**步骤**

1. **收集工作信息**

   自动检测：
   - **Git 提交**：读取 git log，按以下规则定位本次 commit：
     1. 优先：commit message 包含任务号格式（`{task_id_prefix}-{id}`）
     2. 次选：自上次 `/flow:receive` 执行后的 commit
     3. 兜底：最近 5 个 commit，由用户确认
   - **活跃 change**：扫描 spec 工作区，找到最近活跃的 change
   - **接口变更**：扫描是否有 `api.md` 或 `{service}-api.md` 文件

   无法自动检测的信息，使用 **AskUserQuestion** 收集：
   - 功能简述（一句话）
   - 是否有遗留问题

2. **工作流程合规检查**

   自检本次工作是否按设计的流程执行，逐项核查：

   | 检查项 | 预期流程 | 验证方式 |
   |--------|----------|----------|
   | 接收任务 | 执行了 `/flow:receive` | `.flow/changes/{change}/` 目录存在 |
   | 设计阶段 | 先设计再编码 | 各 spec 的 `design.md` 存在且早于编码 commit |
   | 设计评审 | 设计经过评审（自检或用户评审） | `design.md` 中有评审记录或用户确认记录 |
   | 编码工具 | 使用 spec_tool（如 opsx:apply）编码，由 /flow:apply 驱动 | git commit message 包含任务号格式 |
   | 审核循环 | 编码后经过审核 agent | agent 自报（是否启动了审核 agent） |
   | 测试循环 | 审核通过后执行单元测试 | 测试命令被执行（agent 自报） |
   | 提交规范 | commit message 符合格式 | 检查 git log 中的 message 格式 |

   对每项输出：✅ 符合 / ⚠️ 跳过（说明原因） / ❌ 违规（说明偏差）

   **重要**：如存在违规项，必须在汇报中突出标注，提示根 agent 关注。

3. **生成结构化汇报**（含流程合规）

   ```markdown
   【归档汇报】
   服务：{service_name}
   Change：{change-name}
   功能：{一句话描述}
   Commit：{commit-id}

   【流程合规】
   - 接收任务：✅ / ⚠️ / ❌
   - 设计阶段：✅ / ⚠️ / ❌
   - 设计评审：✅ / ⚠️ / ❌
   - 编码工具：✅ / ⚠️ / ❌
   - 审核循环：✅ / ⚠️ / ❌
   - 测试循环：✅ / ⚠️ / ❌
   - 提交规范：✅ / ⚠️ / ❌

   【测试验证】
   单元测试：✅ 通过（X/X）/ ❌ 失败（详情见下）
   集成测试：⏳ 待根 agent 触发 /flow:test

   【接口变更】（如有）
   - 新增：{METHOD} {path}（见 api.md）
   - 修改：{METHOD} {path}（见 api.md）

   【知识库更新】（如有）
   - {path} — {说明}

   【遗留问题】（如有）
   - {问题描述}
   ```

4. **更新根 task.md**

   将 `root_path` 与当前工作目录拼成绝对路径，用 **Read 工具**读取 `{绝对根路径}/.flow/changes/{active-change}/task.md`：
   - 找到本服务章节，将已完成 spec 勾选为 `[x]`
   - 如有新完成项不在列表中，追加到章节末尾
   - 更新元数据头 `updated` 日期
   - 如存在 `## 变更通知` 章节且本服务相关条目已处理，删除对应行

   如无法写入（权限问题），跳过并在汇报中注明。

5. **强制知识库维护判断**（不可跳过）

   根据 `inline_agents.knowledge_maintenance.auto_trigger`：

   **auto_trigger: false（默认）**：
   使用 **AskUserQuestion** 询问：
   > "本次工作是否需要维护知识库？（新业务规则 / 坑点发现 / 接口变更 / 不需要）"

   **auto_trigger: true**：
   判断本次工作是否涉及：新业务规则、坑点发现、接口变更 → 是则自动触发。

   **触发知识库维护**（需要时）：
   使用 **Agent tool** 启动内联知识库维护 agent，传入：
   - 本次 change 内容摘要
   - 知识库路径（来自 config.yaml）
   - 变更类型（新规则/坑点/接口）

   内联 agent 执行：列出拟写入内容 → 展示给用户确认 → 写入知识库。

   **不触发的情况**：bug 修复、内部重构、代码格式调整。

6. **输出汇报**

   完整输出汇报文本，并说明：
   - 根 task.md 更新状态（成功/失败原因）
   - 知识库维护状态（已触发/不需要/已跳过）

   提示：
   "汇报完成。请将完成情况告知根 agent，由根 agent 执行 /flow:status 查看整体进度。"

---

**约束**

- 知识库判断步骤不可跳过，用户必须明确回答（即使选"不需要"）
- 只更新本服务相关的 task.md 条目，不修改其他服务内容
- 汇报格式必须结构化，便于根 agent 解析
- git log 找不到相关 commit 时，让用户手动提供 commit ID