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

3. **生成结构化汇报并写入进度文件**

   定位进度文件（同 apply 方式：扫描 `.flow/{change}/spec/progress-*.md`，选进行中且匹配当前 spec 的文件）。

   在进度文件的进度行之后追加以下章节（不覆盖进度行，它们保留为历史记录）：

   ```markdown
   ---

   ## 汇报

   【基本信息】
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

   完成后，将文件头部的状态行更新为 `- [REPORT] ✅ 已完成 — {date}`。

   **重复执行处理**：如果定位到的进度文件已含汇报章节（`## 汇报`），说明此 spec 曾被 change 重开并重新执行。先将旧文件改名为 `progress-{timestamp}-completed-{当前时间戳}.md`，再用新时间戳创建新进度文件（含 assign 行 + 本次报告）。

4. **更新根 task.md**


   将 `root_path` 与当前工作目录拼成绝对路径，用 **Read 工具**读取 `{绝对根路径}/.flow/changes/{active-change}/task.md`：
   - **spec 条目**：将已完成 spec 勾选为 `[x]`，条目末尾添加 `完成：{date} commit {hash}`；**清除**旧的 `⚠️ 设计修正` 标记
   - **hotfix 条目**：如果是 hotfix（`### Hotfix` 下），`[ ]` → `[x]`，追加 `完成：{date} commit {hash}` + `修复：{1行描述}`
   - **重写**服务头部状态行（替换，不追加）
   - 同步勾选相关检查清单条目
   - 更新元数据头 `updated` 日期
   - 如存在 `## 变更通知` 章节且本服务相关条目已处理，删除对应行

   如无法写入（权限问题），跳过并在汇报中注明。

4.5 **更新发版记录.md**

   定位 `{root_path}/.flow/changes/{active-change}/发版记录.md`（路径同 task.md）。

   按本服务 `service_name` 在表格中找到对应行：

   - **DDL 列**：本 spec 涉及数据库变更（DDL 语句）时，在表格 DDL 列填入 `见下方 DDL`，并在文件末尾 `### DDL` 章节追加 SQL block（标注仓库名）：```` ```sql {repo}\n...\n``` ````
   - **配置列**：本 spec 涉及配置变更（YAML/properties 等）时，在表格配置列填入 `见下方配置`，并在文件末尾 `### 配置文件` 章节追加：`### {repo}（{文件名}, commit {hash}）` + 配置代码块
   - **SQL 风险与 EXPLAIN 证据**：本 spec 涉及数据访问契约风险时，在同名章节追加查询入口、风险形态、最终列表 SQL/分页 count SQL 的 evidence、环境、验收结论、豁免（如有）与回滚方案；不得写「待补」或仅指向源码。

   不涉及 DDL 或配置变更时保持表格原有 `—` 不变。

4.6 **同步接口到 Apifox**

   **前置**：检测 Apifox MCP 是否可用。若未配置，提示"Apifox MCP 未配置，跳过接口同步"，不阻断流程。

   读取根目录 `{root_path}/.flow/changes/{active-change}/开发文档.md` 的 **§3.2.4** 接口表格，逐一处理：

   | 表格状态 | 操作 |
   |---------|------|
   | 已有 Apifox 链接 + ✏️修改 | 使用 Apifox MCP 更新接口定义（从代码/spec design.md 取最终字段） |
   | 待录入 Apifox + 🆕新增 | 使用 Apifox MCP 创建接口，写入完整定义 |
   | 待录入 Apifox + ✏️修改 | 提示"接口 {名称} 需先在 Apifox 中手动创建，再重新 report 同步" |

   **构建 POST 接口 requestBody 的格式要求**：

   Apifox MCP 的 `createHttpEndpoint` / `updateHttpEndpoint` 在处理 POST 请求体时，必须使用 **jsonSchema 模式**，否则 Apifox 页面 Body 显示为空：

   ```json
   {
     "requestBody": {
       "type": "application/json",
       "required": true,
       "parameters": [],
       "jsonSchema": {
         "type": "object",
         "properties": {
           "fieldName": { "type": "integer", "format": "int64", "description": "说明" }
         },
         "required": ["fieldName"],
         "x-apifox-orders": ["fieldName"]
       }
     }
   }
   ```

   ❌ 错误写法：`"type": "json"` + 字段放 `parameters[]`（API 不报错但 UI 不渲染）
   ✅ 正确写法：`"type": "application/json"` + `"parameters": []` + 字段放 `jsonSchema.properties`

   对于 GET 接口，参数仍放在 `parameters.query[]` 中，不受此影响。

   **兜底规则**：若接口的表格状态无法匹配以上任一条（如地址列写的是"待补充"、"无"等模糊值，或变更类型缺失），**禁止静默跳过**。必须在汇报中逐条列出此类接口，说明"未匹配到可执行的分支，请人工确认 Apifox 操作"，并给出建议（创建 / 更新 / 暂不处理）。

   同步完成后，更新 `开发文档.md` 的接口表格：
   - "待录入 Apifox" / "待补充" / "无" → 替换为实际 Apifox 链接
   - 链接格式：`[Apifox 接口](https://app.apifox.com/link/project/{projectId}/apis/api-{entityId})`

   追加进度：`- [REPORT] Apifox 同步完成 — {n}个（新增 {a}/更新 {b}）`

4.7 **回写 `开发文档.md`**

   读取 `~/.claude/commands/flow/templates/dev-doc-update-rules.md` 与 `dev-doc-maintenance.md`（尤其 §4.1 / §4.2 / §4.3）。

   从本 spec 的 OpenSpec `design.md` 与 commit **改写**为人读内容更新根 `开发文档.md`：

   - **§3.2.4**：本 spec 相关接口行（「服务」列 = 可部署服务名；与 4.6 Apifox 同步结果一致）
   - **§3.2.2**：有 DDL 时更新字段语义 + 兼容策略；完整 SQL 放 §4.2，禁止「见发版记录」
   - **§3.2.3**：有新链路时更新数据流转（服务/接口路径级；禁止类名流水）
   - **§3.2.1**：业务规则有收敛时更新
   - **§4.1**：补全/拆分本 spec 涉及的**可部署服务**行（禁止用 git 仓库名冒充服务；多模块仓拆多行）
   - **§4.2**：**直接写入** DDL/SQL 或配置；无则写「无」；禁止「详见发版记录 / openspec / 本地路径」
   - **§4.3**：只写**业务验收语义**；禁止测试类名、本机地址、启动清单、commit hash、spec id

   禁止写入 spec 名、`c{n}-`、本地路径、类名堆砌、完整 JSON。
   在汇报中增加 **【开发文档】** 小节，列出更新的章节。

5. **强制知识库维护判断**（不可跳过）

   根据 `inline_agents.knowledge_maintenance.auto_trigger`：

   **auto_trigger: true**：
   判断本次工作是否涉及：新业务规则、坑点发现、接口变更。
   涉及 → 执行 `/flow:kb {change-name}` 完成 KB 写入和提交。
   不涉及（bug 修复、内部重构、代码格式调整）→ 跳过。

   **auto_trigger: false（默认）**：
   输出以下 KB 维护提示，供根 agent 后续执行：

   ```
   ## KB 维护提示
   Change：{change-name}
   完成 spec：{spec 列表}
   变更类型：[新业务规则 / 坑点发现 / 接口变更 / 不需要]
   建议维护内容：{简要说明哪些内容可能需要记录}
   
   根 agent 请执行 /flow:kb {change-name} 完成知识库维护。
   ```

   不自动写入——`auto_trigger: false` 时 KB 维护由根 agent 负责（assign 时已提前告知）。

6. **输出汇报**

   完整输出汇报文本，并说明：
   - 根 task.md 更新状态（成功/失败原因）
   - 知识库维护状态（已触发/不需要/已跳过）

   提示：
   "汇报完成。请将完成情况告知根 agent，由根 agent 执行 /flow:status 查看整体进度。"

---

**约束**

- task.md 维护规则详见 `~/.claude/commands/flow/templates/task-md-maintenance.md`
- 知识库判断步骤不可跳过，用户必须明确回答
- 只更新本服务相关的 task.md 条目，不修改其他服务
- 汇报格式必须结构化，便于根 agent 解析
- 更新 task.md 时**重写**条目和服务头部，**不追加**
