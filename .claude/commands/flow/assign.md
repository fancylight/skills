---
name: "Flow: Assign"
description: "Root agent assigns specs to child agents — lease-v1 root-mediated review + serial report lease; legacy inline path retained for in-flight changes."
category: Workflow
tags: [workflow, orchestration, multi-agent]
version: "0.4.0"
---

为指定服务派发任务给子 agent。支持 spec 和 hotfix。**根 agent 只负责编排与租约，不编码、不提交、不更新 task.md spec 完成状态。**

**输入**：`/flow:assign <service-name>`

协议：`~/.claude/commands/flow/docs/control-plane.md`。

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认指定 service 在 services 列表且 `flow_initialized: true`；否则提示先在服务目录 `/flow:init`
3. 确认有活跃 change；多个时 **AskUserQuestion** 选择
4. 解析 `protocol_version`（change 覆盖根 config；缺省 `legacy`）
5. **design 门禁（lease-v1 与新 design 产物）**：对本 change 执行 `/flow:verify` 且 `verify_mode=design`（§A+§C+§D+§E+§F.1–§F.3）。存在 §A/§C/§D/§E/§F **ERROR** 时**停止派发**。存在 **WARN** 时对照报告末尾「编排人 WARN 确认清单」**逐项** AskUserQuestion（确认 / 回 design 修 / waive 并说明）；未确认不得 assign。
   - 若 change 仍无 domain-model / 操作链路等新产物（纯 legacy change），design verify 可能大量 SKIP/WARN——按报告处理，不得假装 PASS。
6. 对每个选中服务仓库检查期望分支与干净基线；OpenSpec 可 apply，阻断 spec 时停止。
7. 只派发依赖就绪的 specs。仅在不同仓库或隔离 worktree 之间并行。

---

**步骤**

1. **读取需求上下文**（只取概要信息，不读设计正文）

   - `task.md` — 该服务 spec 列表与 `### Hotfix`
   - 子服务 `.flow/config.yaml` — `inline_agents.knowledge_maintenance.auto_trigger`
   - 不读 design.md / fix.md 正文

2. **依赖与 KB 责任**

   - 依赖未完成 → 警告但不阻止（用户确认后）
   - `auto_trigger: false` → 子 agent report 只出 KB 提示，根需后续 `/flow:kb`

3. **任务号与时间戳**（若配置 `task_id_prefix`）

   最大编号 +1，AskUserQuestion 确认。进度文件时间戳：`{YYYYMMDD-HHmmss}`。

4. **分配模式**

   AskUserQuestion：
   - **内联执行**：根用 Agent tool 为每个 spec 启一个内联 agent
   - **独立指令包**：输出提示词，用户在服务目录粘贴

5. **选择任务**

   展示未完成项；AskUserQuestion 多选。**1 task = 1 agent = 1 commit**。

6. **生成提示词**

   读取 `~/.claude/commands/flow/templates/child-agent-prompt.md`，严格替换变量（含 `{protocol_version}`）。不增删模板段落。

7. **创建进度文件**

   `{服务绝对路径}/.flow/{change_name}/spec/progress-{timestamp}.md`：

   ```
   # {spec_name} — 进度与报告
   需求：{change_name}
   服务：{service_name}
   时间戳：{timestamp}
   protocol_version：{protocol_version}

   - [ASSIGN] {date} — 已分配，等待接收
   ```

8. **执行分配**

   **模式 A：内联**

   按依赖顺序启动 Agent；hotfix 可优先/并行。

   #### lease-v1 根循环（每个执行 agent）

   1. 子 agent：`receive → apply`，实现完成后输出 `[REVIEW_REQUEST]` 并停止编码。
   2. 根启动同级 peer review（`/flow:review` 或 Agent + review 提示），将 `[REVIEW_RESULT]` 作为 **follow-up 注入同一执行子 agent**。
   3. 连续 3 轮 REJECT → `[REVIEW_LOOP] STOPPED`，停止该 spec。
   4. PASS 后子 agent 测+提交，输出 `[REPORT_REQUEST]`。
   5. 根**每次只向一个**执行 agent 发放 `[REPORT_LEASE_GRANTED]`，恢复其执行 `/flow:report`，等待 `[REPORT] complete` 再释放租约、处理下一个。
   6. 更新根调度状态，继续解锁 specs。

   #### legacy

   每个内联 agent 自行 `receive → apply（内联 review）→ report`。根只按序启动与收结果，**不**实现租约循环。

   **模式 B：独立指令包**

   输出提示词；lease-v1 须在包内写明：实现后回根会话贴 `[REVIEW_REQUEST]`，不得本地直 report。

9. **更新 task.md 元数据**

   按 `task-md-maintenance.md` §3.5：**替换**服务头部状态行（开发中 / 分配日期 / 模式 / 任务号）。**不**更新 spec 完成状态。

---

**约束**

- 根**不**读 design 正文、**不**编码、**不**提交、**不**更新 spec `[x]`
- **1 task = 1 spec = 1 agent = 1 commit**
- lease-v1：根必须实现 review 中继与串行 report 租约；词法见 control-plane.md
- 派发输出从简：1 行确认（服务、spec、任务号、模式、protocol）
